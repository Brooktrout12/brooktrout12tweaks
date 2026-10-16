#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>
#import <stdarg.h>
#import "BSPreferences.h"

// Runtime-only declarations: private classes and functions are never hard-linked.
@interface BSFilterAPI : NSObject
+ (id)filterWithType:(NSString *)type;
- (void)setName:(NSString *)name;
@end

static BOOL bsEnabled = YES;
static double bsDuration = BS_DEFAULT_DURATION;
static unsigned bsManualSleepDepth;
static unsigned bsInstallAttempts;
static BOOL bsHooksInstalled, bsRendererAvailable;
static BOOL bsPrivateIsDouble, bsPublicIsDouble;
static IMP bsOriginalPrivate, bsOriginalPublic;
static IMP bsOriginalWake, bsOriginalSleep, bsOriginalPerformWake, bsOriginalReverse;
static CFTypeRef (*bsCaptureScreen)(void);

static void BSSetStatus(NSString *stage, NSString *detail) {
    @try {
        [NSFileManager.defaultManager createDirectoryAtPath:BS_STATUS_PATH.stringByDeletingLastPathComponent
            withIntermediateDirectories:YES attributes:nil error:NULL];
        NSDictionary *status = @{ @"Version":BS_VERSION, @"Stage":stage,
            @"Detail":detail, @"Timestamp":NSDate.date,
            @"OS":NSProcessInfo.processInfo.operatingSystemVersionString,
            @"Process":NSProcessInfo.processInfo.processName };
        [status writeToFile:BS_STATUS_PATH atomically:YES];
    } @catch (__unused NSException *exception) {}
}

static void BSLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void BSLog(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[BlurSleep] %@", message);
    // Only interface names and timing/state are logged. Never screen content.
    @try {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSDictionary *attributes = [fm attributesOfItemAtPath:BS_LOG_PATH error:NULL];
        if ([attributes[NSFileSize] unsignedLongLongValue] > 49152)
            [fm removeItemAtPath:BS_LOG_PATH error:NULL];
        [fm createDirectoryAtPath:BS_LOG_PATH.stringByDeletingLastPathComponent
            withIntermediateDirectories:YES attributes:nil error:NULL];
        if (![fm fileExistsAtPath:BS_LOG_PATH]) [fm createFileAtPath:BS_LOG_PATH contents:nil attributes:nil];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:BS_LOG_PATH];
        [handle seekToEndOfFile];
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", NSDate.date, message];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    } @catch (__unused NSException *exception) {}
}

static BOOL BSTypeMatches(const char *actual, char expected) {
    while (*actual && strchr("rnNoORV", *actual)) actual++;
    return expected == 'B' ? (*actual == 'B' || *actual == 'c') : *actual == expected;
}

static BOOL BSMethodMatches(Class cls, const char *name, const char *signature) {
    Method method = cls ? class_getInstanceMethod(cls, sel_registerName(name)) : NULL;
    if (!method || method_getNumberOfArguments(method) != strlen(signature) + 1) return NO;
    char type[128]; method_getReturnType(method, type, sizeof(type));
    if (!BSTypeMatches(type, signature[0])) return NO;
    for (unsigned i=1; signature[i]; i++) {
        method_getArgumentType(method, i+1, type, sizeof(type));
        if (!BSTypeMatches(type, signature[i])) return NO;
    }
    return YES;
}

static BOOL BSScreenOn(id controller) {
    if (BSMethodMatches([controller class], "screenIsOn", "B"))
        return ((BOOL (*)(id,SEL))objc_msgSend)(controller, sel_registerName("screenIsOn"));
    if (BSMethodMatches([controller class], "screenIsOff", "B"))
        return !((BOOL (*)(id,SEL))objc_msgSend)(controller, sel_registerName("screenIsOff"));
    return NO;
}

@interface BSOverlayController : UIViewController
@end
@implementation BSOverlayController
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }
@end

@interface BSOverlayWindow : UIWindow
@end
@implementation BSOverlayWindow
// Never take focus or intercept the hardware-button recognizers / native lock.
- (BOOL)canBecomeKeyWindow { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { (void)point; (void)event; return nil; }
@end

@interface BSAnimator : NSObject {
    BSAnimationState _state;
    BSOverlayWindow *_window;
    UIImageView *_imageView;
    NSTimer *_cleanupTimer;
}
- (BOOL)startWithDuration:(double)duration;
- (BOOL)isActive;
- (double)remaining;
- (void)cancel;
- (void)cleanupTimerFired:(NSTimer *)timer;
@end

static BSAnimator *bsAnimator;

@implementation BSAnimator
- (BOOL)isActive { return _state.active; }
- (double)remaining { return BSRemaining(&_state, CACurrentMediaTime()); }

- (void)clearWindow {
    [_cleanupTimer invalidate]; _cleanupTimer = nil;
    _window.hidden = YES;
    [_imageView.layer removeAllAnimations];
    _imageView.layer.filters = nil;
    _imageView.image = nil;
    _imageView = nil;
    _window.rootViewController = nil;
    _window = nil;
}

- (void)cancel {
    BSCancel(&_state);
    [self clearWindow];
}

- (void)cleanupTimerFired:(NSTimer *)timer {
    uint64_t token = [timer.userInfo unsignedLongLongValue];
    if (BSExpire(&_state, token)) [self clearWindow];
}

- (BOOL)startWithDuration:(double)duration {
    if (!NSThread.isMainThread || _state.active || !bsCaptureScreen) return NO;
    @try {
        // The UIKit Create function returns a retained UIImage. Move its +1
        // ownership to ARC explicitly, matching the C Create convention.
        UIImage *image = CFBridgingRelease(bsCaptureScreen());
        if (!image || !image.CGImage || image.size.width < 2 || image.size.height < 2) {
            BSSetStatus(@"Snapshot failed",@"The renderer could not capture the screen. Copy diagnostics.");
            BSLog(@"Snapshot unavailable; using the native transition."); return NO;
        }
        Class filterClass = NSClassFromString(@"CAFilter");
        id filter = [(id)filterClass filterWithType:@"gaussianBlur"];
        if (!filter) {
            BSSetStatus(@"Renderer unavailable",@"The Gaussian filter could not be created.");
            BSLog(@"Gaussian filter unavailable."); return NO;
        }
        [filter setName:@"sleepBlur"];
        [filter setValue:@0 forKey:@"inputRadius"];
        // Avoid transparent/dark seams along the screen edges while blurring.
        [filter setValue:@YES forKey:@"inputNormalizeEdges"];

        CGRect bounds = UIScreen.mainScreen.bounds;
        UIWindowScene *scene = nil;
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if (![candidate isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *ws = (UIWindowScene *)candidate;
            if (ws.screen != UIScreen.mainScreen) continue;
            if (!scene) scene = ws;
            if (ws.activationState == UISceneActivationStateForegroundActive) { scene = ws; break; }
        }
        _window = scene ? [[BSOverlayWindow alloc] initWithWindowScene:scene]
                        : [[BSOverlayWindow alloc] initWithFrame:bounds];
        _window.frame = bounds;
        _window.windowLevel = 10000;
        _window.backgroundColor = UIColor.blackColor;
        _window.userInteractionEnabled = NO;
        _window.accessibilityElementsHidden = YES;
        if (BSMethodMatches(_window.class, "_setSecure:", "vB"))
            ((void (*)(id,SEL,BOOL))objc_msgSend)(_window, sel_registerName("_setSecure:"), YES);
        BSOverlayController *controller = [[BSOverlayController alloc] init];
        _window.rootViewController = controller;
        controller.view.frame = bounds;
        controller.view.backgroundColor = UIColor.blackColor;
        _imageView = [[UIImageView alloc] initWithFrame:controller.view.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        _imageView.image = image;
        _imageView.layer.filters = @[filter];
        [controller.view addSubview:_imageView];

        double animationDuration = BSClampDuration(duration);
        uint64_t token = BSBegin(&_state, CACurrentMediaTime(), animationDuration);
        [CATransaction begin];
        @try {
        [CATransaction setDisableActions:YES];
        _window.hidden = NO;
        [controller.view layoutIfNeeded];
        _imageView.layer.opacity = 0;
        [_imageView.layer setValue:@36 forKeyPath:@"filters.sleepBlur.inputRadius"];

        CABasicAnimation *blur = [CABasicAnimation animationWithKeyPath:@"filters.sleepBlur.inputRadius"];
        blur.fromValue = @0; blur.toValue = @36;
        blur.duration = animationDuration;
        blur.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @1; fade.toValue = @0;
        fade.duration = animationDuration;
        fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [_imageView.layer addAnimation:blur forKey:@"BlurSleep.blur"];
        [_imageView.layer addAnimation:fade forKey:@"BlurSleep.fade"];
        } @finally { [CATransaction commit]; }

        // No block-based UIKit completions: compatible with the supplied
        // converted arm64e toolchain. A generation guards old timer callbacks.
        _cleanupTimer = [NSTimer timerWithTimeInterval:animationDuration + BS_CLEANUP_MARGIN
            target:self selector:@selector(cleanupTimerFired:) userInfo:@(token) repeats:NO];
        [NSRunLoop.mainRunLoop addTimer:_cleanupTimer forMode:NSRunLoopCommonModes];
        return YES;
    } @catch (NSException *exception) {
        BSSetStatus(@"Render setup failed",[NSString stringWithFormat:@"%@: %@",exception.name,exception.reason ?: @""]);
        BSLog(@"Animation setup failed (%@); using native lock.", exception.name);
        [self cancel];
        return NO;
    }
}
@end

static void BSCancelOnMain(void *context) {
    (void)context;
    [bsAnimator cancel];
}

static void BSCancelAnimation(NSString *reason) {
    if (!NSThread.isMainThread) {
        dispatch_async_f(dispatch_get_main_queue(),NULL,BSCancelOnMain);
        return;
    }
    if (bsAnimator.isActive) BSLog(@"Cancelled: %@", reason);
    [bsAnimator cancel];
}

static double BSPrepareTransition(id controller, double factor, double nativeDuration, long long source) {
    if (!NSThread.isMainThread) {
        if (factor <= 0.0001 && source == 3)
            BSLog(@"Manual transition arrived off the main thread; kept native transition.");
        if (factor > 0.0001) BSCancelAnimation(@"background-thread wake");
        return nativeDuration;
    }
    if (factor > 0.0001) {
        BSCancelAnimation(@"display brightening");
        return nativeDuration;
    }
    // A public entry point can call the private entry point synchronously.
    // Reuse the deadline, never restart the effect or extend it on every call.
    if (bsAnimator.isActive) {
        if (source == 3 || bsManualSleepDepth) return bsAnimator.remaining;
        BSCancelAnimation(@"different display transition");
        return nativeDuration;
    }
    BOOL screenOn = BSScreenOn(controller);
    if (bsEnabled && (source == 3 || bsManualSleepDepth))
        BSLog(@"Manual transition: target=%.4f duration=%.3f screenOn=%d source=%lld",
            factor,nativeDuration,screenOn,source);
    if (!BSCanStart(bsEnabled, YES, screenOn, NO, factor, source, bsManualSleepDepth > 0))
        return nativeDuration;
    if (!bsAnimator) bsAnimator = [[BSAnimator alloc] init];
    if ([bsAnimator startWithDuration:bsDuration]) {
        BSSetStatus(@"Animation started",@"The lock-animation hook ran. Report any visible timing or blur problem.");
        BSLog(@"Animation started: %.2fs (native %.3fs, source %lld).", bsDuration, nativeDuration, source);
        return bsDuration;
    }
    return nativeDuration;
}

// Preserve the original method's factor/source/silent flag/completion exactly.
// Native lock and authentication execute on their normal path; only the
// backlight transition's duration changes. No deferred/replayed lock request.
static void BSPrivateFloat(id self, SEL cmd, float f, double d, long long s, BOOL silent, id completion) {
    double chosen = BSPrepareTransition(self, f, d, s);
    ((void (*)(id,SEL,float,double,long long,BOOL,id))bsOriginalPrivate)(self,cmd,f,chosen,s,silent,completion);
}
static void BSPrivateDouble(id self, SEL cmd, double f, double d, long long s, BOOL silent, id completion) {
    double chosen = BSPrepareTransition(self, f, d, s);
    ((void (*)(id,SEL,double,double,long long,BOOL,id))bsOriginalPrivate)(self,cmd,f,chosen,s,silent,completion);
}
static void BSPublicFloat(id self, SEL cmd, float f, double d, long long s, id completion) {
    double chosen = BSPrepareTransition(self, f, d, s);
    ((void (*)(id,SEL,float,double,long long,id))bsOriginalPublic)(self,cmd,f,chosen,s,completion);
}
static void BSPublicDouble(id self, SEL cmd, double f, double d, long long s, id completion) {
    double chosen = BSPrepareTransition(self, f, d, s);
    ((void (*)(id,SEL,double,double,long long,id))bsOriginalPublic)(self,cmd,f,chosen,s,completion);
}
static void BSWake(id self, SEL cmd, long long source) {
    BSCancelAnimation(@"wake request");
    ((void (*)(id,SEL,long long))bsOriginalWake)(self,cmd,source);
}
static void BSSleep(id self, SEL cmd) {
    BOOL main = NSThread.isMainThread;
    BSLog(@"Hardware sleep requested (main thread=%d).",main);
    if (main) ++bsManualSleepDepth;
    @try { ((void (*)(id,SEL))bsOriginalSleep)(self,cmd); }
    @finally { if (main) --bsManualSleepDepth; }
}
static void BSPerformWake(id self, SEL cmd) {
    BSCancelAnimation(@"hardware wake");
    ((void (*)(id,SEL))bsOriginalPerformWake)(self,cmd);
}
static BOOL BSReverse(id self, SEL cmd) {
    BOOL reversed = ((BOOL (*)(id,SEL))bsOriginalReverse)(self,cmd);
    if (reversed) BSCancelAnimation(@"sleep reversed");
    return reversed;
}

static void BSInstallOptional(Class cls, const char *name, const char *signature, IMP replacement, IMP *original) {
    if (!BSMethodMatches(cls, name, signature)) return;
    MSHookMessageEx(cls, sel_registerName(name), replacement, original);
    BSLog(@"Hooked %s [%s]", name, signature);
}

static void BSReload(void *context) {
    (void)context;
    bsEnabled = BSReadEnabled(); bsDuration = BSReadDuration();
    if (!bsEnabled) BSCancelAnimation(@"disabled in Settings");
    BSLog(@"Settings: enabled=%d duration=%.2f", bsEnabled, bsDuration);
}
static void BSPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async_f(dispatch_get_main_queue(), NULL, BSReload);
}

static void BSPreviewOnMain(void *context) {
    (void)context;
    BSLog(@"Settings preview requested: renderer=%d hooks=%d",bsRendererAvailable,bsHooksInstalled);
    if (!bsRendererAvailable) {
        BSSetStatus(@"Renderer unavailable",@"Preview received, but a required rendering interface is missing. Copy diagnostics.");
        return;
    }
    if (bsAnimator.isActive) return;
    if (!bsAnimator) bsAnimator = [[BSAnimator alloc] init];
    if ([bsAnimator startWithDuration:bsDuration]) {
        BSLog(@"Preview started for %.2fs. No sleep request sent.",bsDuration);
        BSSetStatus(bsHooksInstalled ? @"Ready" : @"Lock hook unavailable",
            bsHooksInstalled ? @"Preview request received and animation submitted. Try the sleep button next."
                             : @"Preview submitted, but native lock hooks are unavailable. Copy diagnostics.");
    }
}
static void BSPreviewRequested(CFNotificationCenterRef center, void *observer, CFStringRef name,
                              const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async_f(dispatch_get_main_queue(),NULL,BSPreviewOnMain);
}

static void BSLogMethod(Class cls, const char *name) {
    Method method = cls ? class_getInstanceMethod(cls,sel_registerName(name)) : NULL;
    BSLog(@"Interface %s.%s: %s",cls ? class_getName(cls) : "<missing class>",name,
        method ? method_getTypeEncoding(method) : "<missing method>");
}

static void BSInstall(void *context) {
    (void)context;
    if (bsHooksInstalled) return;
    ++bsInstallAttempts;
    BSReload(NULL);
    BSLog(@"BlurSleep %@ startup attempt %u — %@",BS_VERSION,bsInstallAttempts,NSProcessInfo.processInfo.operatingSystemVersionString);
    Class cls = NSClassFromString(@"SBBacklightController");
    const char *privateName = "_animateBacklightToFactor:duration:source:silently:completion:";
    const char *publicName = "animateBacklightToFactor:duration:source:completion:";
    bsPrivateIsDouble = BSMethodMatches(cls, privateName, "vddqB@");
    bsPublicIsDouble = BSMethodMatches(cls, publicName, "vddq@");
    BOOL hasPrivate = bsPrivateIsDouble || BSMethodMatches(cls, privateName, "vfdqB@");
    BOOL hasPublic = bsPublicIsDouble || BSMethodMatches(cls, publicName, "vfdq@");
    BOOL hasState = BSMethodMatches(cls,"screenIsOn","B") || BSMethodMatches(cls,"screenIsOff","B");
    BOOL hasWake = BSMethodMatches(cls,"turnOnScreenFullyWithBacklightSource:","vq");
    Class filterClass = NSClassFromString(@"CAFilter");
    BOOL hasFilter = BSMethodMatches(object_getClass(filterClass),"filterWithType:","@@")
        && BSMethodMatches(filterClass,"setName:","v@");
    bsCaptureScreen = (CFTypeRef (*)(void))dlsym(RTLD_DEFAULT,"_UICreateScreenUIImage");
    bsRendererAvailable = hasFilter && bsCaptureScreen != NULL;
    BSLog(@"Interfaces: private=%d public=%d state=%d wake=%d Gaussian=%d snapshot=%d",
        hasPrivate,hasPublic,hasState,hasWake,hasFilter,bsCaptureScreen != NULL);
    if ((!hasPrivate && !hasPublic) || !hasState || !hasWake || !hasFilter || !bsCaptureScreen) {
        NSMutableArray *missing = [NSMutableArray array];
        if (!hasPrivate && !hasPublic) [missing addObject:@"backlight fade interface"];
        if (!hasState) [missing addObject:@"screen-state interface"];
        if (!hasWake) [missing addObject:@"wake interface"];
        if (!hasFilter) [missing addObject:@"Gaussian filter interface"];
        if (!bsCaptureScreen) [missing addObject:@"screen capture symbol"];
        BSSetStatus(@"Inactive",[NSString stringWithFormat:@"Missing or different: %@. Copy diagnostics.",[missing componentsJoinedByString:@", "]]);
        BSLog(@"Inactive: required private interface unavailable. Native lock retained.");
        BSLogMethod(cls,privateName);
        BSLogMethod(cls,publicName);
        BSLogMethod(cls,"screenIsOn");
        BSLogMethod(cls,"screenIsOff");
        BSLogMethod(cls,"turnOnScreenFullyWithBacklightSource:");
        BSLogMethod(object_getClass(filterClass),"filterWithType:");
        BSLogMethod(filterClass,"setName:");
        unsigned count = 0; Method *methods = cls ? class_copyMethodList(cls,&count) : NULL;
        for (unsigned i=0; i<count; i++) {
            const char *name = sel_getName(method_getName(methods[i]));
            if (strstr(name,"Backlight") || strstr(name,"Fade") || strstr(name,"creenIs"))
                BSLog(@"Available: %s %s",name,method_getTypeEncoding(methods[i]));
        }
        free(methods);
        // Some classes may be registered after the first main-queue turn.
        // Three bounded attempts; never poll indefinitely or relax ABI checks.
        if (bsInstallAttempts < 3)
            dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),NULL,BSInstall);
        return;
    }
    // No partial installation on an unknown core ABI.
    if (hasPrivate) BSInstallOptional(cls,privateName,bsPrivateIsDouble ? "vddqB@" : "vfdqB@",
        bsPrivateIsDouble ? (IMP)BSPrivateDouble : (IMP)BSPrivateFloat,&bsOriginalPrivate);
    if (hasPublic) BSInstallOptional(cls,publicName,bsPublicIsDouble ? "vddq@" : "vfdq@",
        bsPublicIsDouble ? (IMP)BSPublicDouble : (IMP)BSPublicFloat,&bsOriginalPublic);
    BSInstallOptional(cls,"turnOnScreenFullyWithBacklightSource:","vq",(IMP)BSWake,&bsOriginalWake);
    Class sleep = NSClassFromString(@"SBSleepWakeHardwareButtonInteraction");
    BSInstallOptional(sleep,"_performSleep","v",(IMP)BSSleep,&bsOriginalSleep);
    BSInstallOptional(sleep,"_performWake","v",(IMP)BSPerformWake,&bsOriginalPerformWake);
    BSInstallOptional(sleep,"reverseSleepIfNeededAndPossible","B",(IMP)BSReverse,&bsOriginalReverse);
    bsHooksInstalled = YES;
    BSSetStatus(@"Ready",@"SpringBoard loaded BlurSleep and accepted the required interfaces.");
    BSLog(@"Ready for sleep-button testing.");
}

__attribute__((constructor)) static void BSInitialize(void) {
    @autoreleasepool {
        NSInteger major = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
        BOOL springBoard = [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]
            || [NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"];
        if (!springBoard ||
            (major != 17 && major != 18)) return;
        BSSetStatus(@"Starting",@"The tweak library loaded. Checking the animation interfaces.");
        BSLog(@"Library loaded: BlurSleep %@, bundle=%@, process=%@",BS_VERSION,
            NSBundle.mainBundle.bundleIdentifier,NSProcessInfo.processInfo.processName);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,
            BSPreferencesChanged,BS_CHANGED,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,
            BSPreviewRequested,BS_PREVIEW,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
        // Classes have finished registration by the first main-queue turn.
        dispatch_async_f(dispatch_get_main_queue(),NULL,BSInstall);
    }
}
