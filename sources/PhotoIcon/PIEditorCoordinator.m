#import "PIEditorCoordinator.h"
#import "PICropViewController.h"
#import "PIStore.h"
#import "PIBlockCompatibility.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>

@interface PIHostController : UIViewController
@property(nonatomic, copy) void (^onReady)(void);
@property(nonatomic) BOOL started;
@end
@implementation PIHostController
@synthesize onReady = _onReady;
- (void)setOnReady:(void (^)(void))callback {
    // ARC's typed block assignment calls objc_retainBlock / _Block_copy.
    // A synthesized copy setter instead sends copyWithZone: to the incoming
    // stack block, whose legacy arm64e isa has not been signed by libclosure.
    _onReady = callback;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.started) {
        self.started = YES;
        dispatch_async(dispatch_get_main_queue(), ^{ if (self.onReady) self.onReady(); });
    }
}
@end

@interface PINavigationController : UINavigationController
@end
@implementation PINavigationController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ?
        UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}
@end

static UIImage *PIDownsamplePhoto(NSURL *url) {
    if (!url) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url,
        (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});
    if (!source) return nil;
    // Decode an orientation-corrected preview, including HEIC, rather than a
    // potentially enormous full-size panorama inside SpringBoard.
    NSDictionary *options = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (id)kCGImageSourceCreateThumbnailWithTransform:@YES,
        (id)kCGImageSourceThumbnailMaxPixelSize:@2048,
        (id)kCGImageSourceShouldCacheImmediately:@YES
    };
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!image) return nil;
    UIImage *result = [UIImage imageWithCGImage:image scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(image);
    return result;
}

@interface PIEditorCoordinator () <PHPickerViewControllerDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, weak) UIWindow *previousKeyWindow;
@property(nonatomic, strong) UINavigationController *navigation;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) NSProgress *photoProgress;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic) CGFloat cornerRatio;
@property(nonatomic) int lockToken;
@property(nonatomic) BOOL closing;
- (void)closeAnimated;
@end

@implementation PIEditorCoordinator
+ (instancetype)sharedCoordinator {
    static PIEditorCoordinator *coordinator;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ coordinator = [PIEditorCoordinator new]; });
    return coordinator;
}
- (instancetype)init {
    if ((self = [super init])) {
        _lockToken = NOTIFY_TOKEN_INVALID;
        __weak typeof(self) weakSelf = self;
        notify_register_dispatch("com.apple.springboard.lockstate", &_lockToken,
            dispatch_get_main_queue(), ^(int token) {
                uint64_t locked = 0;
                if (notify_get_state(token, &locked) == NOTIFY_STATUS_OK && locked) [weakSelf close];
            });
    }
    return self;
}
- (BOOL)prepareWindowFromIconView:(UIView *)iconView identifier:(NSString *)identifier {
    if (self.window || !identifier.length) return NO;
    UIWindowScene *scene = iconView.window.windowScene;
    if (!scene) {
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if ([candidate isKindOfClass:UIWindowScene.class] &&
                candidate.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)candidate;
                break;
            }
        }
    }
    if (!scene) {
        NSLog(@"[PhotoIcon] No active SpringBoard window scene; editor was not opened.");
        return NO;
    }
    for (UIWindow *window in scene.windows) if (window.isKeyWindow) self.previousKeyWindow = window;
    self.identifier = identifier;
    self.sessionID = NSUUID.UUID.UUIDString;
    PIHostController *host = [PIHostController new];
    host.title = @"PhotoIcon";
    host.view.backgroundColor = UIColor.systemBackgroundColor;
    host.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(close)];
    self.statusLabel = [UILabel new];
    self.statusLabel.text = @"Choose a photo for your icon";
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [host.view addSubview:self.statusLabel];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [host.view addSubview:self.spinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:host.view.centerXAnchor],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:host.view.centerYAnchor],
        [self.statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:host.view.leadingAnchor constant:24],
        [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:host.view.trailingAnchor constant:-24],
        [self.spinner.centerXAnchor constraintEqualToAnchor:host.view.centerXAnchor],
        [self.spinner.bottomAnchor constraintEqualToAnchor:self.statusLabel.topAnchor constant:-24]
    ]];
    self.navigation = [[PINavigationController alloc] initWithRootViewController:host];
    self.navigation.modalInPresentation = YES;
    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    self.window.frame = scene.coordinateSpace.bounds;
    self.window.windowLevel = UIWindowLevelNormal + 100;
    // Reveal SpringBoard underneath while the editor slides offscreen.
    self.window.backgroundColor = UIColor.clearColor;
    self.window.opaque = NO;
    self.window.rootViewController = self.navigation;
    return YES;
}
- (void)editBundleIdentifier:(NSString *)identifier fromIconView:(UIView *)iconView
    cornerRatio:(CGFloat)cornerRatio useSavedPhoto:(BOOL)useSavedPhoto {
    if (![self prepareWindowFromIconView:iconView identifier:identifier]) return;
    self.cornerRatio = cornerRatio;
    __weak typeof(self) weakSelf = self;
    PIHostController *host = (PIHostController *)self.navigation.topViewController;
    host.onReady = ^{
        typeof(self) self = weakSelf;
        if (!self.window) return;
        UIImage *saved = useSavedPhoto ? [[PIStore sharedStore] sourceForBundleIdentifier:identifier] : nil;
        if (saved) [self showCropForImage:saved crop:[[PIStore sharedStore] cropForBundleIdentifier:identifier]];
        else [self choosePhoto];
    };
    [self.window makeKeyAndVisible];
}
- (void)showError:(NSError *)error allowRetry:(BOOL)retry {
    if (!self.window) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"PhotoIcon"
        message:error.localizedDescription ?: @"The photo could not be opened. Please choose another image."
        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    if (retry) [alert addAction:[UIAlertAction actionWithTitle:@"Choose Another Photo"
        style:UIAlertActionStyleDefault handler:PI_SYSTEM_BLOCK(^(UIAlertAction *action) { [weakSelf choosePhoto]; })]];
    [alert addAction:[UIAlertAction actionWithTitle:retry ? @"Cancel" : @"OK"
        style:UIAlertActionStyleCancel handler:PI_SYSTEM_BLOCK(^(UIAlertAction *action) {
            if ([weakSelf.navigation.topViewController isKindOfClass:PIHostController.class]) [weakSelf close];
        })]];
    [self.navigation.topViewController presentViewController:alert animated:YES completion:nil];
}
- (void)choosePhoto {
    if (!self.window || self.navigation.presentedViewController) return;
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.selectionLimit = 1;
    config.filter = PHPickerFilter.imagesFilter;
    config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFullScreen;
    [self.navigation presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    NSString *session = self.sessionID;
    __weak typeof(self) weakSelf = self;
    // Both selection and Cancel reach this call. UIKit retains the completion
    // immediately, so it must already be a runtime-copied block on arm64e.
    [picker dismissViewControllerAnimated:YES completion:PI_SYSTEM_BLOCK(^{
        typeof(self) self = weakSelf;
        if (!self.window || ![session isEqualToString:self.sessionID]) return;
        if (!results.count) {
            if ([self.navigation.topViewController isKindOfClass:PIHostController.class]) [self close];
            return;
        }
        self.statusLabel.text = @"Opening photo…";
        [self.spinner startAnimating];
        [self.navigation setToolbarHidden:YES animated:NO];
        [self.navigation popToRootViewControllerAnimated:NO];
        NSItemProvider *provider = results.firstObject.itemProvider;
        self.photoProgress = [provider loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier
            completionHandler:PI_SYSTEM_BLOCK(^(NSURL *url, NSError *error) {
                @autoreleasepool {
                    // The provider owns this temporary URL; decode before this block returns.
                    UIImage *image = PIDownsamplePhoto(url);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        typeof(self) self = weakSelf;
                        if (!self.window || ![session isEqualToString:self.sessionID]) return;
                        self.photoProgress = nil;
                        [self.spinner stopAnimating];
                        if (image) [self showCropForImage:image crop:nil];
                        else [self showError:error allowRetry:YES];
                    });
                }
            })];
    })];
}
- (void)showCropForImage:(UIImage *)image crop:(NSDictionary *)crop {
    if (!self.window) return;
    PICropViewController *editor = [[PICropViewController alloc] initWithImage:image
        crop:crop cornerRatio:self.cornerRatio];
    __weak typeof(self) weakSelf = self;
    __weak PICropViewController *weakEditor = editor;
    NSString *identifier = self.identifier;
    NSString *session = self.sessionID;
    editor.onCancel = ^{ [weakSelf closeAnimated]; };
    editor.onChoosePhoto = ^{ [weakSelf choosePhoto]; };
    editor.onSave = ^(UIImage *icon, NSDictionary *newCrop) {
        weakEditor.saving = YES;
        [[PIStore sharedStore] saveImage:icon source:image crop:newCrop forBundleIdentifier:identifier
            completion:PI_SYSTEM_BLOCK(^(NSError *error) {
                typeof(self) self = weakSelf;
                if (![session isEqualToString:self.sessionID]) return;
                if (error) {
                    weakEditor.saving = NO;
                    [self showError:error allowRetry:NO];
                } else {
                    [self closeAnimated];
                }
            })];
    };
    [self.navigation pushViewController:editor animated:NO];
}
- (void)restoreBundleIdentifier:(NSString *)identifier fromIconView:(UIView *)iconView {
    if (![self prepareWindowFromIconView:iconView identifier:identifier]) return;
    NSString *session = self.sessionID;
    __weak typeof(self) weakSelf = self;
    PIHostController *host = (PIHostController *)self.navigation.topViewController;
    host.onReady = ^{
        weakSelf.statusLabel.text = @"Restoring original icon…";
        [weakSelf.spinner startAnimating];
        [[PIStore sharedStore] removeIconForBundleIdentifier:identifier completion:PI_SYSTEM_BLOCK(^(NSError *error) {
            typeof(self) self = weakSelf;
            if (![session isEqualToString:self.sessionID]) return;
            if (error) [self showError:error allowRetry:NO];
            else [self close];
        })];
    };
    [self.window makeKeyAndVisible];
}
- (void)closeAnimated {
    if (!self.window || self.closing) return;
    self.closing = YES;
    self.sessionID = nil;
    [self.photoProgress cancel];
    self.photoProgress = nil;

    UIWindow *window = self.window;
    UIView *panel = self.navigation.view;
    panel.userInteractionEnabled = NO;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    CGAffineTransform destination = CGAffineTransformTranslate(panel.transform, 0, CGRectGetHeight(window.bounds));
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:reduceMotion ? 0.15 : 0.32 delay:0
        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
        animations:PI_SYSTEM_BLOCK(^{
            if (reduceMotion) panel.alpha = 0;
            else panel.transform = destination;
        }) completion:PI_SYSTEM_BLOCK(^(BOOL finished) {
            typeof(self) self = weakSelf;
            // Locking can close this window before the animation finishes.
            // A late callback must never tear down a subsequently opened editor.
            if (self.window == window) [self close];
        })];
}
- (void)close {
    self.sessionID = nil;
    [self.photoProgress cancel];
    self.photoProgress = nil;
    UIWindow *window = self.window;
    UINavigationController *navigation = self.navigation;
    UIWindow *previousKeyWindow = self.previousKeyWindow;
    // Clear the session's window identity before interrupting animations;
    // animation completion may run during cleanup and must become a no-op.
    self.window = nil;
    self.navigation = nil;
    self.previousKeyWindow = nil;
    self.closing = NO;
    self.spinner = nil;
    self.statusLabel = nil;
    self.identifier = nil;
    window.hidden = YES;
    [navigation dismissViewControllerAnimated:NO completion:nil];
    if (navigation.isViewLoaded) [navigation.view.layer removeAllAnimations];
    window.rootViewController = nil;
    if (previousKeyWindow && !previousKeyWindow.hidden) [previousKeyWindow makeKeyWindow];
}
@end
