#import "PISpringBoardImages.h"
#import "PIHookSupport.h"
#include <math.h>

@interface NSObject (PIAdditionalCacheInterfaces)
- (SBIconImageInfo)iconImageInfo;
- (void)purgeAllCachedImages;
- (void)purgeAllCachedFolderImages;
- (void)rebuildAllCachedFolderImages;
- (void)informObserversOfUpdateForAllFolderIcons;
- (void)rebuildImagesReferencingIcons:(id)icons;
@end

static PIIconRenderer PIRender;
static NSHashTable *PIFolderCaches;
static NSHashTable *PIIconCaches;
static NSHashTable *PILegacyIcons;
static BOOL PIRefreshScheduled;

static void PITrackCache(id cache, BOOL folder) {
    @synchronized (PIFolderCaches) {
        [(folder ? PIFolderCaches : PIIconCaches) addObject:cache];
    }
}
static UIImage *PIImageInCache(id cache, SBIcon *icon, BOOL masked) {
    PITrackCache(cache, NO);
    @synchronized (PIFolderCaches) { if (icon) [PILegacyIcons addObject:icon]; }
    if (![cache respondsToSelector:@selector(iconImageInfo)]) return nil;
    return PIRender(icon, [cache iconImageInfo], masked);
}
static UIImage *PIThumbnail(SBIcon *icon, CGSize size, CGFloat scale) {
    @synchronized (PIFolderCaches) { if (icon) [PILegacyIcons addObject:icon]; }
    SBIconImageInfo info = {size, scale, MIN(size.width, size.height) * 0.2237};
    return PIRender(icon, info, YES);
}

// Return per-identifier immutable artwork. Never write a supplied native image,
// native layer, shared cache entry, or another icon view's presentation.
static UIImage *(*PIOrigIconInfo)(id,SEL,SBIconImageInfo);
static UIImage *PIIconInfo(id self, SEL cmd, SBIconImageInfo info) {
    @synchronized (PIFolderCaches) { [PILegacyIcons addObject:self]; }
    return PIRender(self,info,YES) ?: PIOrigIconInfo(self,cmd,info);
}
static UIImage *(*PIOrigLegacyLeafImage)(id,SEL,SBIconImageInfo);
static UIImage *PILegacyLeafImage(id self,SEL cmd,SBIconImageInfo info) {
    return PIRender(self,info,YES) ?: PIOrigLegacyLeafImage(self,cmd,info);
}
static UIImage *(*PIOrigIconTraits)(id,SEL,SBIconImageInfo,id,NSUInteger);
static UIImage *PIIconTraits(id self,SEL cmd,SBIconImageInfo info,id traits,NSUInteger options) {
    return PIRender(self,info,YES) ?: PIOrigIconTraits(self,cmd,info,traits,options);
}
static UIImage *(*PIOrigLeafImage)(id,SEL,SBIconImageInfo,id,NSUInteger);
static UIImage *PILeafImage(id self,SEL cmd,SBIconImageInfo info,id traits,NSUInteger options) {
    return PIRender(self,info,YES) ?: PIOrigLeafImage(self,cmd,info,traits,options);
}
static CALayer *PILayerForIcon(SBIcon *icon, SBIconImageInfo info) {
    UIImage *image = PIRender(icon,info,YES);
    if (!image) return nil;
    CALayer *layer;
    // The icon model can be queried by background image-cache workers.
    [CATransaction begin];
    @try {
        [CATransaction setDisableActions:YES];
        layer = [CALayer layer];
        layer.bounds = (CGRect){CGPointZero,info.size};
        layer.contents = (__bridge id)image.CGImage;
        layer.contentsScale = image.scale;
        layer.contentsGravity = kCAGravityResize;
    } @finally {
        [CATransaction commit];
    }
    return layer;
}
static CALayer *(*PIOrigIconLayer)(id,SEL,SBIconImageInfo,id,NSUInteger);
static CALayer *PIIconLayer(id self,SEL cmd,SBIconImageInfo info,id traits,NSUInteger options) {
    return PILayerForIcon(self,info) ?: PIOrigIconLayer(self,cmd,info,traits,options);
}
static CALayer *(*PIOrigLeafLayer)(id,SEL,SBIconImageInfo,id,NSUInteger);
static CALayer *PILeafLayer(id self,SEL cmd,SBIconImageInfo info,id traits,NSUInteger options) {
    return PILayerForIcon(self,info) ?: PIOrigLeafLayer(self,cmd,info,traits,options);
}

#define PI_CACHE_SIMPLE(NAME, MASKED) \
static UIImage *(*NAME##Original)(id,SEL,SBIcon *); \
static UIImage *NAME(id self,SEL cmd,SBIcon *icon) { \
    return PIImageInCache(self,icon,MASKED) ?: NAME##Original(self,cmd,icon); \
}
PI_CACHE_SIMPLE(PICachedImage, YES)
PI_CACHE_SIMPLE(PICacheImage, YES)
PI_CACHE_SIMPLE(PICachedUnmaskedImage, NO)
PI_CACHE_SIMPLE(PICacheUnmaskedImage, NO)

#define PI_CACHE_APPEARANCE(NAME) \
static UIImage *(*NAME##Original)(id,SEL,SBIcon *,id,NSUInteger); \
static UIImage *NAME(id self,SEL cmd,SBIcon *icon,id appearance,NSUInteger options) { \
    return PIImageInCache(self,icon,YES) ?: NAME##Original(self,cmd,icon,appearance,options); \
}
PI_CACHE_APPEARANCE(PICacheAppearance)
PI_CACHE_APPEARANCE(PICachedAppearance)
PI_CACHE_APPEARANCE(PIRealAppearance)
PI_CACHE_APPEARANCE(PICacheTraits)
PI_CACHE_APPEARANCE(PICachedTraits)

#define PI_GRID_IMAGE(NAME) \
static UIImage *(*NAME##Original)(id,SEL,SBIcon *,id,NSUInteger *); \
static UIImage *NAME(id self,SEL cmd,SBIcon *icon,id appearance,NSUInteger *attributes) { \
    PITrackCache(self,YES); \
    UIImage *native = NAME##Original(self,cmd,icon,appearance,attributes); \
    if (![native isKindOfClass:UIImage.class]) return native; \
    return PIThumbnail(icon,native.size,native.scale) ?: native; \
}
PI_GRID_IMAGE(PISharedGridImage)
PI_GRID_IMAGE(PILocalGridImage)
#define PI_GRID_SIMPLE(NAME) \
static UIImage *(*NAME##Original)(id,SEL,SBIcon *,id); \
static UIImage *NAME(id self,SEL cmd,SBIcon *icon,id appearance) { \
    PITrackCache(self,YES); \
    UIImage *native = NAME##Original(self,cmd,icon,appearance); \
    if (![native isKindOfClass:UIImage.class]) return native; \
    return PIThumbnail(icon,native.size,native.scale) ?: native; \
}
PI_GRID_SIMPLE(PISharedGridSimple)
PI_GRID_SIMPLE(PILocalGridSimple)

// iOS 17 folder miniatures use the one-argument cache selector.
#define PI_GRID_LEGACY(NAME) \
static UIImage *(*NAME##Original)(id,SEL,SBIcon *); \
static UIImage *NAME(id self,SEL cmd,SBIcon *icon) { \
    PITrackCache(self,YES); \
    UIImage *native = NAME##Original(self,cmd,icon); \
    if (![native isKindOfClass:UIImage.class]) return native; \
    return PIThumbnail(icon,native.size,native.scale) ?: native; \
}
PI_GRID_LEGACY(PISharedGridLegacy)
PI_GRID_LEGACY(PILocalGridLegacy)

static CALayer *PIReplacementMiniLayer(SBIcon *icon, CALayer *native) {
    if (![native isKindOfClass:CALayer.class]) return native;
    CGSize size = native.bounds.size;
    CGFloat scale = native.contentsScale;
    if (!isfinite(scale) || scale < 1 || scale > 4) scale = 3;
    UIImage *image = PIThumbnail(icon,size,scale);
    if (!image) return native;
    CALayer *layer;
    [CATransaction begin];
    @try {
        [CATransaction setDisableActions:YES];
        layer = [CALayer layer];
        layer.name = @"PhotoIcon.folderMiniature";
        layer.bounds = native.bounds;
        layer.anchorPoint = native.anchorPoint;
        layer.position = native.position;
        layer.transform = native.transform;
        layer.opacity = native.opacity;
        layer.hidden = native.hidden;
        layer.contentsGravity = kCAGravityResize;
        layer.contentsScale = image.scale;
        layer.contents = (__bridge id)image.CGImage;
    } @finally {
        [CATransaction commit];
    }
    return layer;
}
static CALayer *(*PIOrigGridLayer)(id,SEL,SBIcon *,id,NSUInteger *);
static CALayer *PIGridLayer(id self,SEL cmd,SBIcon *icon,id appearance,NSUInteger *attributes) {
    PITrackCache(self,YES);
    return PIReplacementMiniLayer(icon,PIOrigGridLayer(self,cmd,icon,appearance,attributes));
}
static CALayer *(*PIOrigGridLayerSimple)(id,SEL,SBIcon *,id);
static CALayer *PIGridLayerSimple(id self,SEL cmd,SBIcon *icon,id appearance) {
    PITrackCache(self,YES);
    return PIReplacementMiniLayer(icon,PIOrigGridLayerSimple(self,cmd,icon,appearance));
}

static void PIRefreshCaches(void *unused) {
    PIRefreshScheduled = NO;
    NSArray *folders;
    NSArray *icons;
    NSArray *legacyIcons;
    @synchronized (PIFolderCaches) {
        folders = PIFolderCaches.allObjects;
        icons = PIIconCaches.allObjects;
        legacyIcons = PILegacyIcons.allObjects;
    }
    for (id cache in icons) {
        if ([cache respondsToSelector:@selector(purgeAllCachedImages)]) [cache purgeAllCachedImages];
    }
    for (id cache in folders) {
        // Rebuild only folder composites via iOS 17's native cache API. Do not
        // reload or mutate the icon model's shared image state.
        if (legacyIcons.count && [cache respondsToSelector:@selector(rebuildImagesReferencingIcons:)])
            [cache rebuildImagesReferencingIcons:legacyIcons];
        if ([cache respondsToSelector:@selector(purgeAllCachedFolderImages)]) [cache purgeAllCachedFolderImages];
        if ([cache respondsToSelector:@selector(rebuildAllCachedFolderImages)]) [cache rebuildAllCachedFolderImages];
        if ([cache respondsToSelector:@selector(informObserversOfUpdateForAllFolderIcons)])
            [cache informObserversOfUpdateForAllFolderIcons];
    }
}
void PIRefreshAdditionalSpringBoardImages(void) {
    // The existing store notification is delivered on the main queue.
    if (PIRefreshScheduled) return;
    PIRefreshScheduled = YES;
    dispatch_async_f(dispatch_get_main_queue(), NULL, PIRefreshCaches);
}

void PIInstallAdditionalSpringBoardImages(PIIconRenderer renderer) {
    PIRender = renderer;
    PIFolderCaches = [NSHashTable weakObjectsHashTable];
    PIIconCaches = [NSHashTable weakObjectsHashTable];
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 17)
        PILegacyIcons = [NSHashTable weakObjectsHashTable];
    NSString *infoType = [NSString stringWithUTF8String:@encode(SBIconImageInfo)];
    Class icon = NSClassFromString(@"SBIcon");
    Class leaf = NSClassFromString(@"SBLeafIcon");
    PIHookMethod(icon,@selector(iconImageWithInfo:),(IMP)PIIconInfo,(IMP *)&PIOrigIconInfo,"@",@[infoType]);
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 17)
        PIHookMethod(leaf,@selector(generateIconImageWithInfo:),(IMP)PILegacyLeafImage,
            (IMP *)&PIOrigLegacyLeafImage,"@",@[infoType]);
    PIHookMethod(icon,@selector(iconImageWithInfo:traitCollection:options:),(IMP)PIIconTraits,
        (IMP *)&PIOrigIconTraits,"@",@[infoType,@"@",@"Q"]);
    PIHookMethod(leaf,@selector(makeIconImageWithInfo:traitCollection:options:),(IMP)PILeafImage,
        (IMP *)&PIOrigLeafImage,"@",@[infoType,@"@",@"Q"]);
    PIHookMethod(icon,@selector(iconLayerWithInfo:traitCollection:options:),(IMP)PIIconLayer,
        (IMP *)&PIOrigIconLayer,"@",@[infoType,@"@",@"Q"]);
    PIHookMethod(leaf,@selector(makeIconLayerWithInfo:traitCollection:options:),(IMP)PILeafLayer,
        (IMP *)&PIOrigLeafLayer,"@",@[infoType,@"@",@"Q"]);
    Class cache = NSClassFromString(@"SBHIconImageCache");
#define PI_SIMPLE(SELECTOR, NAME) PIHookMethod(cache,NSSelectorFromString(@SELECTOR),(IMP)NAME,(IMP *)&NAME##Original,"@",@[@"@"])
    PI_SIMPLE("imageForIcon:",PICacheImage);
    PI_SIMPLE("cachedImageForIcon:",PICachedImage);
    PI_SIMPLE("cachedUnmaskedImageForIcon:",PICachedUnmaskedImage);
    PI_SIMPLE("unmaskedImageForIcon:",PICacheUnmaskedImage);
#undef PI_SIMPLE
#define PI_APPEARANCE(SELECTOR, NAME) PIHookMethod(cache,NSSelectorFromString(@SELECTOR),(IMP)NAME,(IMP *)&NAME##Original,"@",@[@"@",@"@",@"Q"])
    PI_APPEARANCE("imageForIcon:imageAppearance:options:",PICacheAppearance);
    PI_APPEARANCE("cachedImageForIcon:imageAppearance:options:",PICachedAppearance);
    PI_APPEARANCE("realImageForIcon:imageAppearance:options:",PIRealAppearance);
    PI_APPEARANCE("imageForIcon:compatibleWithTraitCollection:options:",PICacheTraits);
    PI_APPEARANCE("cachedImageForIcon:compatibleWithTraitCollection:options:",PICachedTraits);
#undef PI_APPEARANCE
    Class shared = NSClassFromString(@"SBFolderIconImageSharedCache");
    Class local = NSClassFromString(@"SBFolderIconImageCache");
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 17) {
        PIHookMethod(shared,@selector(gridCellImageForIcon:),(IMP)PISharedGridLegacy,
            (IMP *)&PISharedGridLegacyOriginal,"@",@[@"@"]);
        PIHookMethod(local,@selector(gridCellImageForIcon:),(IMP)PILocalGridLegacy,
            (IMP *)&PILocalGridLegacyOriginal,"@",@[@"@"]);
    }
    SEL grid = @selector(gridCellImageForIcon:imageAppearance:imageAttributes:);
    PIHookMethod(shared,grid,(IMP)PISharedGridImage,(IMP *)&PISharedGridImageOriginal,"@",@[@"@",@"@",@"^Q"]);
    PIHookMethod(local,grid,(IMP)PILocalGridImage,(IMP *)&PILocalGridImageOriginal,"@",@[@"@",@"@",@"^Q"]);
    PIHookMethod(shared,@selector(gridCellImageForIcon:imageAppearance:),(IMP)PISharedGridSimple,
        (IMP *)&PISharedGridSimpleOriginal,"@",@[@"@",@"@"]);
    PIHookMethod(local,@selector(gridCellImageForIcon:imageAppearance:),(IMP)PILocalGridSimple,
        (IMP *)&PILocalGridSimpleOriginal,"@",@[@"@",@"@"]);
    PIHookMethod(shared,@selector(gridCellLayerForIcon:imageAppearance:imageAttributes:),(IMP)PIGridLayer,
        (IMP *)&PIOrigGridLayer,"@",@[@"@",@"@",@"^Q"]);
    PIHookMethod(shared,@selector(gridCellLayerForIcon:imageAppearance:),(IMP)PIGridLayerSimple,
        (IMP *)&PIOrigGridLayerSimple,"@",@[@"@",@"@"]);
}
