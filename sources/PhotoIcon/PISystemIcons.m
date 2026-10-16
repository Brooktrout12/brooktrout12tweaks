#import "Compatibility.h"
#import "PISystemIconReader.h"
#import "PIHookSupport.h"
#import "PIPrivate.h"
#include <mach-o/dyld.h>
#include <stdatomic.h>

// Minimal declarations checked against the iOS 18 runtime headers. Optional
// framework hooks are registered again when an image is loaded lazily.
@interface NSObject (PISystemIconInterfaces)
- (NSString *)bundleIdentifier;
- (NSString *)identityString;
- (NSURL *)url;
- (CGSize)size;
- (CGFloat)scale;
- (CGFloat)continuousCornerRadius;
- (BOOL)shouldApplyMask;
- (id)initWithCGImage:(CGImageRef)image scale:(CGFloat)scale;
+ (NSString *)bundleIdentifierForIdentityString:(NSString *)identity error:(NSError **)error;
@end
@protocol PIImageGeometry <NSObject>
- (CGSize)size;
- (CGFloat)scale;
@end

static NSString *PIIconIdentifier(id icon) {
    if ([icon respondsToSelector:@selector(bundleIdentifier)]) {
        id value = [icon bundleIdentifier];
        if ([value isKindOfClass:NSString.class] && [value length]) return value;
    }
    if ([icon respondsToSelector:@selector(identityString)]) {
        id identity = [icon identityString];
        Class resolver = NSClassFromString(@"LSApplicationIdentity");
        if ([identity isKindOfClass:NSString.class] &&
            [resolver respondsToSelector:@selector(bundleIdentifierForIdentityString:error:)])
            return [resolver bundleIdentifierForIdentityString:identity error:nil];
    }
    if ([icon respondsToSelector:@selector(url)]) {
        id url = [icon url];
        // Never turn a document/file-type icon into its owning app's icon.
        if ([url isKindOfClass:NSURL.class] && [url isFileURL] &&
            [[url pathExtension] isEqualToString:@"app"])
            return [NSBundle bundleWithURL:url].bundleIdentifier;
    }
    return nil;
}
static id PIIconServicesImage(id icon, id descriptor) {
    Class descriptorClass = NSClassFromString(@"ISImageDescriptor");
    Class imageClass = NSClassFromString(@"ISImage");
    if (![descriptor isKindOfClass:descriptorClass] ||
        ![imageClass instancesRespondToSelector:@selector(initWithCGImage:scale:)]) return nil;
    NSString *identifier = PIIconIdentifier(icon);
    if (!identifier) return nil;
    CGSize size = [descriptor size];
    CGFloat scale = [(id<PIImageGeometry>)descriptor scale];
    CGFloat radius = [descriptor respondsToSelector:@selector(continuousCornerRadius)] ?
        [descriptor continuousCornerRadius] : MIN(size.width,size.height)*0.2237;
    BOOL mask = [descriptor respondsToSelector:@selector(shouldApplyMask)] ? [descriptor shouldApplyMask] : YES;
    UIImage *photo = PISharedImage(identifier,size,scale,radius,mask);
    return photo ? [[imageClass alloc] initWithCGImage:photo.CGImage scale:photo.scale] : nil;
}

#define PI_DESCRIPTOR_HOOK(NAME) \
static id (*NAME##Original)(id,SEL,id); \
static id NAME(id self,SEL cmd,id descriptor) { \
    return PIIconServicesImage(self,descriptor) ?: NAME##Original(self,cmd,descriptor); \
}
PI_DESCRIPTOR_HOOK(PIISImage)
PI_DESCRIPTOR_HOOK(PIISLegacyImage)
PI_DESCRIPTOR_HOOK(PIISPreparedImage)
PI_DESCRIPTOR_HOOK(PIISConcreteImage)
PI_DESCRIPTOR_HOOK(PIISGeneratedImage)
PI_DESCRIPTOR_HOOK(PIISCachedImage)
PI_DESCRIPTOR_HOOK(PIISStoredImage)

static UIImage *(*PIUIFormatOriginal)(id,SEL,NSString *,int);
static UIImage *PIUIFormat(id self,SEL cmd,NSString *identifier,int format) {
    UIImage *native = PIUIFormatOriginal(self,cmd,identifier,format);
    return PISharedImageMatching(identifier,native) ?: native;
}
static UIImage *(*PIUIScaleOriginal)(id,SEL,NSString *,int,CGFloat);
static UIImage *PIUIScale(id self,SEL cmd,NSString *identifier,int format,CGFloat scale) {
    UIImage *native = PIUIScaleOriginal(self,cmd,identifier,format,scale);
    return PISharedImageMatching(identifier,native) ?: native;
}
static UIImage *(*PIUIStyleOriginal)(id,SEL,NSString *,int,CGFloat,NSInteger);
static UIImage *PIUIStyle(id self,SEL cmd,NSString *identifier,int format,CGFloat scale,NSInteger style) {
    UIImage *native = PIUIStyleOriginal(self,cmd,identifier,format,scale,style);
    return PISharedImageMatching(identifier,native) ?: native;
}

static UIImage *(*PISearchImageOriginal)(id,SEL,CGFloat,BOOL);
static UIImage *PISearchImage(id self,SEL cmd,CGFloat scale,BOOL dark) {
    UIImage *native = PISearchImageOriginal(self,cmd,scale,dark);
    NSString *identifier = [self respondsToSelector:@selector(bundleIdentifier)] ? [self bundleIdentifier] : nil;
    return PISharedImageMatching(identifier,native) ?: native;
}

static UIImage *(*PIActivityImageOriginal)(id,SEL,NSString *,NSInteger);
static UIImage *PIActivityImage(id self,SEL cmd,NSString *identifier,NSInteger style) {
    UIImage *native = PIActivityImageOriginal(self,cmd,identifier,style);
    return PISharedImageMatching(identifier,native) ?: native;
}
static UIImage *(*PIActivitySettingsOriginal)(id,SEL,NSString *,NSInteger);
static UIImage *PIActivitySettings(id self,SEL cmd,NSString *identifier,NSInteger style) {
    UIImage *native = PIActivitySettingsOriginal(self,cmd,identifier,style);
    return PISharedImageMatching(identifier,native) ?: native;
}
static void (*PIActivityDeliveryOriginal)(id,SEL,id,NSString *,NSInteger,id,int,BOOL,id);
static void PIActivityDelivery(id self,SEL cmd,id native,NSString *identifier,NSInteger category,
    id contentSize,int format,BOOL placeholder,id uti) {
    id replacement = nil;
    if ([native isKindOfClass:UIImage.class]) {
        replacement = PISharedImageMatching(identifier,native);
    } else {
        Class imageClass = NSClassFromString(@"ISImage");
        Class foundationImage = NSClassFromString(@"IFImage");
        if ([native isKindOfClass:foundationImage] &&
            [imageClass instancesRespondToSelector:@selector(initWithCGImage:scale:)]) {
            CGSize size = [native size];
            UIImage *photo = PISharedImage(identifier,size,[(id<PIImageGeometry>)native scale],MIN(size.width,size.height)*0.2237,YES);
            if (photo) replacement = [[imageClass alloc] initWithCGImage:photo.CGImage scale:photo.scale];
        }
    }
    PIActivityDeliveryOriginal(self,cmd,replacement ?: native,identifier,category,contentSize,
        format,replacement ? NO : placeholder,uti);
}

// Spotlight can host SpringBoardHome icon views in its own process. These
// read-only image providers use the export, never the editor's private store.
static UIImage *PIExternalHomeImage(id icon, SBIconImageInfo info, BOOL masked) {
    if (![icon respondsToSelector:@selector(applicationBundleID)] ||
        ([icon respondsToSelector:@selector(isApplicationIcon)] && ![icon isApplicationIcon])) return nil;
    return PISharedImage([icon applicationBundleID],info.size,info.scale,info.continuousCornerRadius,masked);
}
static UIImage *(*PIExternalIconOriginal)(id,SEL,SBIconImageInfo,id,NSUInteger);
static UIImage *PIExternalIcon(id self,SEL cmd,SBIconImageInfo info,id traits,NSUInteger options) {
    return PIExternalHomeImage(self,info,YES) ?: PIExternalIconOriginal(self,cmd,info,traits,options);
}
static UIImage *(*PIExternalLegacyIconOriginal)(id,SEL,SBIconImageInfo);
static UIImage *PIExternalLegacyIcon(id self,SEL cmd,SBIconImageInfo info) {
    return PIExternalHomeImage(self,info,YES) ?: PIExternalLegacyIconOriginal(self,cmd,info);
}
static UIImage *(*PIExternalLeafOriginal)(id,SEL,SBIconImageInfo,id,NSUInteger);
static UIImage *PIExternalLeaf(id self,SEL cmd,SBIconImageInfo info,id traits,NSUInteger options) {
    return PIExternalHomeImage(self,info,YES) ?: PIExternalLeafOriginal(self,cmd,info,traits,options);
}

static void PIInstallSystemIconHooks(void) {
    Class ui = object_getClass(UIImage.class);
    PIHookMethod(ui,NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:"),
        (IMP)PIUIFormat,(IMP *)&PIUIFormatOriginal,"@",@[@"@",@"i"]);
    PIHookMethod(ui,NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:"),
        (IMP)PIUIScale,(IMP *)&PIUIScaleOriginal,"@",@[@"@",@"i",@"d"]);
    PIHookMethod(ui,NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:style:"),
        (IMP)PIUIStyle,(IMP *)&PIUIStyleOriginal,"@",@[@"@",@"i",@"d",@"q"]);
    Class icon = NSClassFromString(@"ISIcon");
    Class concrete = NSClassFromString(@"ISConcreteIcon");
#define PI_DESC(CLASS, SELECTOR, NAME) PIHookMethod(CLASS,NSSelectorFromString(@SELECTOR),(IMP)NAME,(IMP *)&NAME##Original,"@",@[@"@"])
    PI_DESC(icon,"imageForDescriptor:",PIISImage);
    PI_DESC(icon,"imageForImageDescriptor:",PIISLegacyImage);
    PI_DESC(icon,"prepareImageForDescriptor:",PIISPreparedImage);
    PI_DESC(concrete,"imageForDescriptor:",PIISConcreteImage);
    PI_DESC(concrete,"generateImageWithDescriptor:",PIISGeneratedImage);
    PI_DESC(concrete,"_cachedImageForDescriptor:",PIISCachedImage);
    PI_DESC(concrete,"_imageFromStoreForDescriptor:",PIISStoredImage);
#undef PI_DESC
    PIHookMethod(NSClassFromString(@"SearchUIAppIconImage"),NSSelectorFromString(@"loadImageWithScale:isDarkStyle:"),
        (IMP)PISearchImage,(IMP *)&PISearchImageOriginal,"@",@[@"d",@"B"]);
    Class activity = object_getClass(NSClassFromString(@"UIActivity"));
    PIHookMethod(activity,NSSelectorFromString(@"_activityImageForApplicationBundleIdentifier:userInterfaceStyle:"),
        (IMP)PIActivityImage,(IMP *)&PIActivityImageOriginal,"@",@[@"@",@"q"]);
    PIHookMethod(activity,NSSelectorFromString(@"_activitySettingsImageForApplicationBundleIdentifier:userInterfaceStyle:"),
        (IMP)PIActivitySettings,(IMP *)&PIActivitySettingsOriginal,"@",@[@"@",@"q"]);
    PIHookMethod(NSClassFromString(@"SFUIActivityImageProvider"),NSSelectorFromString(
        @"_handleIconImage:identifier:activityCategory:contentSizeCategory:iconFormat:placeholder:uti:"),
        (IMP)PIActivityDelivery,(IMP *)&PIActivityDeliveryOriginal,"v",@[@"@",@"@",@"q",@"@",@"i",@"B",@"@"]);
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        NSString *info = [NSString stringWithUTF8String:@encode(SBIconImageInfo)];
        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 17)
            PIHookMethod(NSClassFromString(@"SBIcon"),@selector(iconImageWithInfo:),
                (IMP)PIExternalLegacyIcon,(IMP *)&PIExternalLegacyIconOriginal,"@",@[info]);
        PIHookMethod(NSClassFromString(@"SBIcon"),@selector(iconImageWithInfo:traitCollection:options:),
            (IMP)PIExternalIcon,(IMP *)&PIExternalIconOriginal,"@",@[info,@"@",@"Q"]);
        PIHookMethod(NSClassFromString(@"SBLeafIcon"),@selector(makeIconImageWithInfo:traitCollection:options:),
            (IMP)PIExternalLeaf,(IMP *)&PIExternalLeafOriginal,"@",@[info,@"@",@"Q"]);
    }
}
static atomic_bool PIHookInstallPending;
static void PIInstallAfterImageLoad(void *unused) {
    atomic_store(&PIHookInstallPending,false);
    @autoreleasepool { PIInstallSystemIconHooks(); }
}
static void PIDynamicImageAdded(const struct mach_header *header, intptr_t slide) {
    // dyld's notification may precede Objective-C initialization. Do not look
    // up classes or execute Objective-C while its loader lock is held.
    if (!atomic_exchange(&PIHookInstallPending,true))
        dispatch_async_f(dispatch_get_main_queue(),NULL,PIInstallAfterImageLoad);
}
__attribute__((constructor)) static void PIStartSystemIcons(void) {
    @autoreleasepool {
        if (!BTSupportsIOS17And18()) return;
        PIInstallSystemIconHooks();
        _dyld_register_func_for_add_image(PIDynamicImageAdded);
    }
}
