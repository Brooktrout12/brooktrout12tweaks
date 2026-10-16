#import "Compatibility.h"
#import "PIPrivate.h"
#import "PIStore.h"
#import "PIEditorCoordinator.h"
#import "PIBlockCompatibility.h"
#import "PISpringBoardImages.h"
#import <objc/runtime.h>
#import <math.h>

static NSHashTable *PIImageViews;
static NSCache *PIMaskedImages;
static char PIClockOriginalHandsHidden;
static char PIPhotoLayerKey;
static char PIPhotoIdentifierKey;
static char PIPhotoBindingKey;
static char PIPhotoUpdatingKey;
static char PIOriginalMenuProviderKey;
static char PIWrappedMenuProviderKey;
static NSString *const PIChangeType = @"com.brooktrout12.photoicon.change";
static NSString *const PIAdjustType = @"com.brooktrout12.photoicon.adjust";
static NSString *const PIRestoreType = @"com.brooktrout12.photoicon.restore";
static NSString *const PIBookmarkMenuIdentifier = @"com.brooktrout12.photoicon.bookmark-menu";

static BOOL PIIsBookmarkIcon(SBIcon *icon) {
    return [icon respondsToSelector:@selector(isBookmarkIcon)] && [icon isBookmarkIcon];
}

static NSString *PIIdentifierForIcon(SBIcon *icon) {
    if (PIIsBookmarkIcon(icon)) {
        SBHBookmark *bookmark = [icon respondsToSelector:@selector(bookmark)] ?
            [(SBHBookmarkIcon *)icon bookmark] : nil;
        if ([bookmark respondsToSelector:@selector(isAppClip)] && bookmark.isAppClip) return nil;
        id identifier = [bookmark respondsToSelector:@selector(identifier)] ? bookmark.identifier : nil;
        // Some bookmark icon subclasses expose the same persistent identity
        // directly through UIWebClip rather than an SBHBookmark wrapper.
        if (![identifier isKindOfClass:NSString.class] || ![identifier length]) {
            UIWebClip *clip = [icon respondsToSelector:@selector(webClip)] ?
                [(SBHBookmarkIcon *)icon webClip] : nil;
            identifier = [clip respondsToSelector:@selector(identifier)] ? clip.identifier : nil;
        }
        if (![identifier isKindOfClass:NSString.class] || ![identifier length]) return nil;
        // Use the persistent individual bookmark identity, never its URL,
        // title, Safari's bundle ID, or a temporary view/object address.
        // The prefix keeps bookmark keys separate from existing app keys.
        return [@"webclip:" stringByAppendingString:identifier];
    }
    if (![icon respondsToSelector:@selector(applicationBundleID)]) return nil;
    if ([icon respondsToSelector:@selector(isApplicationIcon)] && ![icon isApplicationIcon]) return nil;
    id identifier = [icon applicationBundleID];
    return [identifier isKindOfClass:NSString.class] && [identifier length] ? identifier : nil;
}

static NSString *PIIdentifierForView(SBIconView *view) {
    if (![view respondsToSelector:@selector(icon)]) return nil;
    return PIIdentifierForIcon(view.icon);
}

static NSString *PIIdentifierForImageView(SBIconImageView *view) {
    NSString *identifier = PIIdentifierForIcon(view.icon);
    SBIconView *owner = view.iconView;
    // During reuse the image view and its labelled parent may briefly refer
    // to different icons. Wait for the binding to finish before showing a photo.
    if (owner && ![identifier isEqualToString:PIIdentifierForView(owner)]) return nil;
    return identifier;
}

static UIImage *PIImageForIcon(SBIcon *icon, SBIconImageInfo info, BOOL masked) {
    NSString *identifier = PIIdentifierForIcon(icon);
    if (!identifier) return nil;
    UIImage *photo = [[PIStore sharedStore] imageForBundleIdentifier:identifier];
    if (!photo) return nil;
    if (!isfinite(info.size.width) || !isfinite(info.size.height) ||
        info.size.width <= 0 || info.size.height <= 0 || info.size.width > 512 || info.size.height > 512 ||
        !isfinite(info.scale) || info.scale < 1 || info.scale > 4 ||
        !isfinite(info.continuousCornerRadius)) return nil;
    NSString *key = [NSString stringWithFormat:@"%@:%p:%.4f:%.4f:%.4f:%.4f:%d", identifier,
        photo, info.size.width, info.size.height, info.scale, info.continuousCornerRadius, masked];
    UIImage *result = [PIMaskedImages objectForKey:key];
    if (result) return result;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = info.scale;
    format.opaque = YES;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:info.size format:format];
    UIImage *square = [renderer imageWithActions:PI_SYSTEM_BLOCK(^(UIGraphicsImageRendererContext *context) {
        [photo drawInRect:(CGRect){CGPointZero, info.size}];
    })];
    Class iconClass = NSClassFromString(@"SBIcon");
    result = masked ? [iconClass iconImageFromUnmaskedImage:square info:info] : square;
    if (result) [PIMaskedImages setObject:result forKey:key cost:
        CGImageGetWidth(result.CGImage)*CGImageGetHeight(result.CGImage)*4];
    return result;
}

static __attribute__((noinline)) void PIClearPhotoPresentation(SBIconImageView *view) {
    CALayer *photoLayer = objc_getAssociatedObject(view, &PIPhotoLayerKey);
    if (photoLayer) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        photoLayer.contents = nil;
        [photoLayer removeFromSuperlayer];
        [CATransaction commit];
    }
    objc_setAssociatedObject(view, &PIPhotoLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &PIPhotoIdentifierKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static __attribute__((noinline)) void PIUpdatePhotoPresentation(SBIconImageView *view) {
    if (objc_getAssociatedObject(view, &PIPhotoBindingKey) ||
        objc_getAssociatedObject(view, &PIPhotoUpdatingKey)) return;
    NSString *identifier = PIIdentifierForImageView(view);
    if (!identifier) { PIClearPhotoPresentation(view); return; }
    SBIconImageInfo info = view.iconImageInfo;
    if (view.showsSquareCorners) info.continuousCornerRadius = 0;
    UIImage *image = PIImageForIcon(view.icon, info, YES);
    if (!image || ![identifier isEqualToString:PIIdentifierForImageView(view)]) {
        PIClearPhotoPresentation(view);
        return;
    }
    NSString *previousIdentifier = objc_getAssociatedObject(view, &PIPhotoIdentifierKey);
    if (previousIdentifier && ![previousIdentifier isEqualToString:identifier])
        PIClearPhotoPresentation(view);

    objc_setAssociatedObject(view, &PIPhotoUpdatingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CALayer *photoLayer = objc_getAssociatedObject(view, &PIPhotoLayerKey);
    if (!photoLayer) {
        photoLayer = [CALayer layer];
        photoLayer.name = @"PhotoIcon.artwork";
        objc_setAssociatedObject(view, &PIPhotoLayerKey, photoLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(view, &PIPhotoIdentifierKey, identifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
    // Keep Apple's displayedImage, contentsLayer and image-cache entries native.
    // The only mutable custom layer belongs exclusively to this one icon view.
    CALayer *root = view.layer;
    // iOS 17 keeps artwork on the view's backing layer and has no
    // contentsLayer accessor. iOS 18 retains its existing sublayer path.
    CALayer *native = [view respondsToSelector:@selector(contentsLayer)] ? view.contentsLayer : nil;
    BOOL followsNative = native && native != root && native.superlayer == root &&
        native.bounds.size.width > 0 && native.bounds.size.height > 0;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    photoLayer.contents = (__bridge id)image.CGImage;
    photoLayer.contentsScale = image.scale;
    photoLayer.contentsGravity = kCAGravityResize;
    if (followsNative) {
        photoLayer.bounds = native.bounds;
        photoLayer.position = native.position;
        photoLayer.anchorPoint = native.anchorPoint;
        photoLayer.transform = native.transform;
        photoLayer.opacity = native.opacity;
        photoLayer.hidden = native.hidden;
        // Put the photo above the native artwork but below progress subviews.
        NSArray *layers = root.sublayers;
        NSUInteger nativeIndex = [layers indexOfObjectIdenticalTo:native];
        NSUInteger photoIndex = [layers indexOfObjectIdenticalTo:photoLayer];
        if (photoLayer.superlayer != root || photoIndex != nativeIndex + 1)
            [root insertSublayer:photoLayer above:native];
    } else {
        CGRect frame = view.visibleBounds;
        if (CGRectIsEmpty(frame)) frame = view.bounds;
        photoLayer.transform = CATransform3DIdentity;
        photoLayer.anchorPoint = CGPointMake(0.5, 0.5);
        photoLayer.frame = frame;
        photoLayer.opacity = 1;
        photoLayer.hidden = NO;
        if (photoLayer.superlayer != root || root.sublayers.firstObject != photoLayer)
            [root insertSublayer:photoLayer atIndex:0];
    }
    [CATransaction commit];
    objc_setAssociatedObject(view, &PIPhotoUpdatingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static CGFloat PICornerRatio(SBIconView *view) {
    CGSize size = view.iconImageSize;
    UIView *imageView = [view _iconImageView];
    CGFloat radius = [imageView respondsToSelector:@selector(continuousCornerRadius)] ?
        [(SBIconImageView *)imageView continuousCornerRadius] : view.iconImageCornerRadius;
    return size.width > 0 && radius > 0 ? radius / size.width : 0.2237;
}

static BOOL PIOwnShortcut(SBSApplicationShortcutItem *item) {
    if (![item respondsToSelector:@selector(type)]) return NO;
    return [item.type isEqualToString:PIChangeType] || [item.type isEqualToString:PIAdjustType] ||
        [item.type isEqualToString:PIRestoreType];
}

static void PIPerformIconAction(SBIconView *view, NSString *type, NSString *expectedIdentifier) {
    NSString *identifier = PIIdentifierForView(view);
    if (!identifier || ![identifier isEqualToString:expectedIdentifier]) return;
    CGFloat ratio = PICornerRatio(view);
    // Let SpringBoard finish dismissing the context menu before opening Photos.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // A menu may outlive a recycled icon view. Never retarget an action.
        if (![identifier isEqualToString:PIIdentifierForView(view)]) return;
        if ([type isEqualToString:PIRestoreType]) {
            [[PIEditorCoordinator sharedCoordinator] restoreBundleIdentifier:identifier fromIconView:view];
        } else {
            [[PIEditorCoordinator sharedCoordinator] editBundleIdentifier:identifier fromIconView:view
                cornerRatio:ratio useSavedPhoto:[type isEqualToString:PIAdjustType]];
        }
    });
}

static __attribute__((noinline)) UIMenu *PIMenuWithBookmarkActions(UIMenu *nativeMenu,
    SBIconView *view, NSString *identifier) {
    if (!PIIsBookmarkIcon(view.icon) || ![identifier isEqualToString:PIIdentifierForView(view)]) {
        return nativeMenu;
    }
    // Append to the menu the original provider actually returned. Suggestions
    // can be discarded by that provider, leaving suggestion-only additions invisible.
    NSMutableArray *items = [NSMutableArray new];
    for (UIMenuElement *element in nativeMenu.children) {
        if ([element isKindOfClass:UIMenu.class] &&
            [[(UIMenu *)element identifier] isEqualToString:PIBookmarkMenuIdentifier]) continue;
        [items addObject:element];
    }
    NSArray *types = [[PIStore sharedStore] hasIconForBundleIdentifier:identifier] ?
        @[PIChangeType, PIAdjustType, PIRestoreType] : @[PIChangeType];
    NSMutableArray *actions = [NSMutableArray new];
    __weak SBIconView *weakView = view;
    for (NSString *type in types) {
        NSString *title = [type isEqualToString:PIChangeType] ? @"Change Icon…" :
            ([type isEqualToString:PIAdjustType] ? @"Adjust Icon…" : @"Restore Original Icon");
        NSString *symbol = [type isEqualToString:PIChangeType] ? @"photo" :
            ([type isEqualToString:PIAdjustType] ? @"crop" : @"arrow.counterclockwise");
        UIAction *action = [UIAction actionWithTitle:title image:[UIImage systemImageNamed:symbol]
            identifier:type handler:PI_SYSTEM_BLOCK(^(UIAction *selectedAction) {
                PIPerformIconAction(weakView, type, identifier);
            })];
        [actions addObject:action];
    }
    [items addObject:[UIMenu menuWithTitle:@"" image:nil identifier:PIBookmarkMenuIdentifier
        options:UIMenuOptionsDisplayInline children:actions]];
    // Retain the root menu's metadata and every native child, including Share
    // Bookmark and Delete Bookmark. The original configuration/preview stays.
    return [nativeMenu menuByReplacingChildren:items];
}

%group PIViewImages
%hook SBIconImageView
- (void)didMoveToWindow {
    %orig;
    [PIImageViews addObject:self];
    PIUpdatePhotoPresentation(self);
}
- (void)layoutSubviews {
    %orig;
    PIUpdatePhotoPresentation(self);
}
- (void)setIcon:(SBIcon *)icon location:(NSString *)location animated:(BOOL)animated {
    id wasBinding = objc_getAssociatedObject(self, &PIPhotoBindingKey);
    objc_setAssociatedObject(self, &PIPhotoBindingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PIClearPhotoPresentation(self);
    %orig;
    objc_setAssociatedObject(self, &PIPhotoBindingKey, wasBinding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PIUpdatePhotoPresentation(self);
    // The parent SBIconView may finish changing its icon after this setter.
    [self setNeedsLayout];
}
- (void)prepareForReuse {
    id wasBinding = objc_getAssociatedObject(self, &PIPhotoBindingKey);
    objc_setAssociatedObject(self, &PIPhotoBindingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PIClearPhotoPresentation(self);
    %orig;
    objc_setAssociatedObject(self, &PIPhotoBindingKey, wasBinding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end
%end

%group PIViewImages18
%hook SBIconImageView
- (void)updateImageContentsWithImage:(UIImage *)image imageAppearance:(id)appearance
    isRealContentsImage:(BOOL)real animated:(BOOL)animated {
    %orig;
    PIUpdatePhotoPresentation(self);
}
- (void)applyImageSublayer:(CALayer *)layer animated:(BOOL)animated {
    %orig;
    PIUpdatePhotoPresentation(self);
}
%end
%end

%group PIViewImages17
%hook SBIconImageView
- (void)updateImageAnimated:(BOOL)animated {
    %orig;
    PIUpdatePhotoPresentation(self);
}
%end
%end

%group PIClockImages
%hook SBHClockApplicationIconImageView
- (BOOL)shouldShowHourMinuteHands {
    if ([[PIStore sharedStore] hasIconForBundleIdentifier:PIIdentifierForIcon(self.icon)]) return NO;
    return %orig;
}
- (BOOL)shouldShowSecondsHand {
    if ([[PIStore sharedStore] hasIconForBundleIdentifier:PIIdentifierForIcon(self.icon)]) return NO;
    return %orig;
}
- (void)updateImageAnimated:(BOOL)animated {
    %orig;
    BOOL custom = [[PIStore sharedStore] hasIconForBundleIdentifier:PIIdentifierForIcon(self.icon)];
    NSNumber *original = objc_getAssociatedObject(self, &PIClockOriginalHandsHidden);
    if (custom) {
        if (!original) objc_setAssociatedObject(self, &PIClockOriginalHandsHidden,
            @([self areHandsHidden]), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self setHandsHidden:YES animated:NO];
    } else if (original) {
        [self setHandsHidden:original.boolValue animated:NO];
        objc_setAssociatedObject(self, &PIClockOriginalHandsHidden, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
%end
%end

%group PIMenu
%hook SBIconView
- (NSArray *)effectiveApplicationShortcutItems {
    NSArray *original = %orig;
    // Bookmarks use native UIActions below; they do not have app shortcuts.
    if (PIIsBookmarkIcon(self.icon)) return original;
    NSString *identifier = PIIdentifierForView(self);
    if (!identifier) return original;
    Class itemClass = NSClassFromString(@"SBSApplicationShortcutItem");
    if (!itemClass) return original;
    NSMutableArray *items = [NSMutableArray new];
    for (SBSApplicationShortcutItem *item in original) if (!PIOwnShortcut(item)) [items addObject:item];
    NSArray *types = [[PIStore sharedStore] hasIconForBundleIdentifier:identifier] ?
        @[PIChangeType,PIAdjustType,PIRestoreType] : @[PIChangeType];
    for (NSString *type in types) {
        SBSApplicationShortcutItem *item = [itemClass new];
        item.type = type;
        item.localizedTitle = [type isEqualToString:PIChangeType] ? @"Change Icon…" :
            ([type isEqualToString:PIAdjustType] ? @"Adjust Icon…" : @"Restore Original Icon");
        item.userInfo = @{@"bundleIdentifier":identifier};
        [items addObject:item];
    }
    return items;
}
+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)identifier
    forIconView:(SBIconView *)view {
    if (!PIOwnShortcut(item)) {
        %orig;
        return;
    }
    // Resolve the icon itself, rather than trusting the shortcut payload.
    PIPerformIconAction(view, item.type, PIIdentifierForView(view));
}
%end
%end

%group PIBookmarkMenus
%hook SBIconView
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
    configurationForMenuAtLocation:(CGPoint)location {
    UIContextMenuConfiguration *configuration = %orig;
    BOOL bookmark = PIIsBookmarkIcon(self.icon);
    NSString *identifier = PIIdentifierForView(self);
    if (!bookmark || !identifier || !configuration) return configuration;
    if (![configuration respondsToSelector:@selector(actionProvider)] ||
        ![configuration respondsToSelector:@selector(setActionProvider:)]) {
        return configuration;
    }
    UIContextMenuActionProvider originalProvider = configuration.actionProvider;
    // Repeated configuration requests must not build a chain of our wrappers.
    // If UIKit replaced the provider itself, preserve its new one instead.
    if (originalProvider == objc_getAssociatedObject(configuration, &PIWrappedMenuProviderKey)) {
        originalProvider = (UIContextMenuActionProvider)objc_getAssociatedObject(configuration, &PIOriginalMenuProviderKey);
    } else {
        objc_setAssociatedObject(configuration, &PIOriginalMenuProviderKey,
            originalProvider, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    __weak SBIconView *weakView = self;
    configuration.actionProvider = PI_SYSTEM_BLOCK(^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        UIMenu *nativeMenu = originalProvider ? originalProvider(suggestedActions) : nil;
        if (!nativeMenu) nativeMenu = [UIMenu menuWithTitle:@"" children:suggestedActions ?: @[]];
        return PIMenuWithBookmarkActions(nativeMenu, weakView, identifier);
    });
    objc_setAssociatedObject(configuration, &PIWrappedMenuProviderKey,
        configuration.actionProvider, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return configuration;
}
%end
%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
            !BTSupportsIOS17And18()) return;
        Class imageView = NSClassFromString(@"SBIconImageView");
        Class iconView = NSClassFromString(@"SBIconView");
        Class icon = NSClassFromString(@"SBIcon");
        // Unsupported revisions should leave the Home Screen intact. Do not add
        // hooks for absent private selectors or expose a non-working menu entry.
        BOOL modernImageUpdates = [imageView instancesRespondToSelector:@selector(contentsLayer)] &&
            [imageView instancesRespondToSelector:@selector(applyImageSublayer:animated:)] &&
            [imageView instancesRespondToSelector:@selector(updateImageContentsWithImage:imageAppearance:isRealContentsImage:animated:)];
        BOOL legacyImageUpdates = [imageView instancesRespondToSelector:@selector(updateImageAnimated:)];
        BOOL renderOK = [icon respondsToSelector:@selector(iconImageFromUnmaskedImage:info:)] &&
            [imageView instancesRespondToSelector:@selector(iconImageInfo)] &&
            [imageView instancesRespondToSelector:@selector(iconView)] &&
            [imageView instancesRespondToSelector:@selector(visibleBounds)] &&
            [imageView instancesRespondToSelector:@selector(setIcon:location:animated:)] &&
            [imageView instancesRespondToSelector:@selector(prepareForReuse)] &&
            (modernImageUpdates || legacyImageUpdates);
        BOOL menuOK = [iconView instancesRespondToSelector:@selector(effectiveApplicationShortcutItems)] &&
            [iconView respondsToSelector:@selector(activateShortcut:withBundleIdentifier:forIconView:)];
        if (!renderOK || !menuOK) {
            NSLog(@"[PhotoIcon] Required icon interfaces unavailable (render=%d, menu=%d).",renderOK,menuOK);
            return;
        }
        PIImageViews = [NSHashTable weakObjectsHashTable];
        PIMaskedImages = [NSCache new];
        PIMaskedImages.totalCostLimit = 24*1024*1024;
        [PIStore sharedStore];
        PIInstallAdditionalSpringBoardImages(PIImageForIcon);
        %init(PIViewImages);
        if (modernImageUpdates) {
            %init(PIViewImages18);
        } else {
            %init(PIViewImages17);
        }
        %init(PIMenu);
        BOOL bookmarkMenuOK = [iconView instancesRespondToSelector:
            @selector(contextMenuInteraction:configurationForMenuAtLocation:)];
        if (bookmarkMenuOK) {
            %init(PIBookmarkMenus);
        } else {
            NSLog(@"[PhotoIcon] Bookmark menu interface unavailable; app editing remains enabled.");
        }
        Class clock = NSClassFromString(@"SBHClockApplicationIconImageView");
        if ([clock instancesRespondToSelector:@selector(shouldShowHourMinuteHands)] &&
            [clock instancesRespondToSelector:@selector(shouldShowSecondsHand)] &&
            [clock instancesRespondToSelector:@selector(setHandsHidden:animated:)] &&
            [clock instancesRespondToSelector:@selector(areHandsHidden)]) {
            %init(PIClockImages);
        }
        // Capture this existing cache in both observers. Without a local
        // capture Clang makes a global block, and _Block_copy returns that same
        // legacy unsigned-isa object; ARC's release then crashes at startup.
        // Capturing the cache forces a real runtime-initialized heap copy.
        NSCache *maskedImages = PIMaskedImages;
        [[NSNotificationCenter defaultCenter] addObserverForName:PIIconsDidChangeNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:PI_SYSTEM_BLOCK(^(NSNotification *notification) {
                [maskedImages removeAllObjects];
                PIRefreshAdditionalSpringBoardImages();
                NSString *identifier = notification.object;
                for (SBIconImageView *view in PIImageViews.allObjects) {
                    NSString *presented = objc_getAssociatedObject(view, &PIPhotoIdentifierKey);
                    if ([PIIdentifierForImageView(view) isEqualToString:identifier] ||
                        [presented isEqualToString:identifier]) {
                        [view updateImageAnimated:NO];
                        PIUpdatePhotoPresentation(view);
                    }
                }
            })];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:PI_SYSTEM_BLOCK(^(NSNotification *notification) {
                [maskedImages removeAllObjects];
            })];
    }
}
