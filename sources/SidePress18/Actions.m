#import "Runtime.h"
#import "Shared.h"
#import "LaunchPolicy.h"
#import "UnlockFlow.h"
#import "SecureAppLaunch.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <Block.h>

// Copy callbacks with the C Blocks runtime before crossing a hooked ObjC API.
// A legacy arm64e stack block has an unsigned ISA: an interposed hook treating
// the callback as id can crash on objc_retain before the real service sees it.
// The runtime heap copy has a valid ISA. Transfer its +1 reference to ARC, and
// never put the original stack literal in an ARC-owned local variable.
typedef void (^SPApplicationCompletion)(id, NSError *);
typedef void (^SPPresentationCompletion)(void);
@protocol SPApplicationOpening <NSObject>
- (void)openApplication:(NSString *)bundle withOptions:(id)options completion:(SPApplicationCompletion)completion;
@end
@protocol SPCameraPresentation <NSObject>
- (void)activateCameraViewAnimated:(BOOL)animated sendingActions:(id)actions completion:(SPPresentationCompletion)completion;
@end

static NSUInteger requestGeneration, hostPresentedGeneration;

void SPSetStatus(NSString *status) { SPWrite(@"LastResult", status); }
static BOOL SPLocked(void) { return SPBool(SPShared(@"SBLockScreenManager"), @"isUILocked", YES); }
static id SPCoverController(void) {
    return SPGet(SPShared(@"SBCoverSheetPresentationManager"), @"coverSheetViewController") ?:
           SPGet(SPShared(@"SBLockScreenManager"), @"coverSheetViewController");
}
static BOOL SPCoverVisible(void) {
    id manager = SPShared(@"SBCoverSheetPresentationManager");
    return SPBool(manager, @"isPresented", NO) || SPBool(manager, @"isVisibleAndNotDisappearing", NO);
}
static BOOL SPHostContainsApp(id host, NSString *bundle) {
    if (!SPBool(host, @"isHostingAnApp", NO)) return NO;
    id handle = SPGet(host, @"hostedAppSceneHandle");
    return [SPGet(SPGet(handle, @"application"), @"bundleIdentifier") isEqual:bundle];
}
static BOOL SPCoverContainsApp(NSString *bundle) {
    id manager = SPShared(@"SBCoverSheetPresentationManager");
    if (SPBool(manager, @"isInSecureApp", NO) &&
        SPHostContainsApp(SPGet(manager, @"secureAppViewController"), bundle)) return YES;
    return (SPLocked() || SPCoverVisible()) && SPHostContainsApp(SPCoverController(), bundle);
}
static void SPFeedback(BOOL enabled) {
    if (enabled) [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}
static void SPFailure(NSString *message) {
    SPSetStatus(message);
    [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeError];
}
static void SPLoadFramework(const char *name) {
    NSString *path = [NSString stringWithFormat:@"/System/Library/PrivateFrameworks/%s.framework/%s", name, name];
    dlopen(path.UTF8String, RTLD_LAZY | RTLD_GLOBAL);
}
static NSString *SPConstant(const char *name) {
    // These exports are NSString * variables, not C strings.
    NSString * __unsafe_unretained *slot = (NSString * __unsafe_unretained *)dlsym(RTLD_DEFAULT, name);
    return slot && [*slot isKindOfClass:NSString.class] ? *slot : nil;
}
void SPCancelPendingAction(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SPCancelPendingAction(); });
        return;
    }
    ++requestGeneration;
    SPCancelNativeUnlock();
    SPCancelSecureAppLaunch();
}

static void SPOpenApp(NSString *bundle, BOOL haptic) {
    if (![bundle isKindOfClass:NSString.class] || bundle.length == 0) {
        SPFailure(@"Choose an app in SidePress18 settings first."); return;
    }
    if (SPLocked()) { SPFailure(@"App launch canceled because the device locked."); return; }
    SPLoadFramework("SpringBoardServices");
    SPLoadFramework("FrontBoardServices");
    id service = SPGet(NSClassFromString(@"FBSOpenApplicationService"), @"serviceWithDefaultShellEndpoint");
    Class optionsClass = NSClassFromString(@"FBSOpenApplicationOptions");
    SEL open = NSSelectorFromString(@"openApplication:withOptions:completion:");
    SEL makeOptions = NSSelectorFromString(@"optionsWithDictionary:");
    if (![service respondsToSelector:open] || ![optionsClass respondsToSelector:makeOptions]) {
        SPFailure(@"This iOS build does not expose the app-launch service."); return;
    }
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    NSString *unlock = SPConstant("FBSOpenApplicationOptionKeyUnlockDevice");
    NSString *prompt = SPConstant("FBSOpenApplicationOptionKeyPromptUnlockDevice");
    if (unlock) dictionary[unlock] = @NO;
    if (prompt) dictionary[prompt] = @NO;
    NSString *pocket = SPConstant("SBSOpenApplicationOptionKeyConfirmedNotInPocket");
    if (pocket) dictionary[pocket] = @YES;
    // Keep SpringBoard's normal opening transition and launch-screen snapshot.
    // LaunchWithoutAnimation left the old foreground visible during cold starts.
    NSUInteger generation = requestGeneration;
    id options = ((id (*)(id, SEL, id))objc_msgSend)(optionsClass, makeOptions, dictionary);
    SPSetStatus(@"Opening app…");
    SPApplicationCompletion completion = (__bridge_transfer SPApplicationCompletion)_Block_copy((__bridge const void *)^(__unused id handle, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != requestGeneration) return;
            if (error) {
                NSString *detail = error.localizedFailureReason ?: error.localizedDescription ?: @"No explanation returned.";
                NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
                NSString *cause = [underlying isKindOfClass:NSError.class] ?
                    [NSString stringWithFormat:@" Underlying: %@ %ld — %@", underlying.domain,
                        (long)underlying.code, underlying.localizedDescription] : @"";
                SPFailure([NSString stringWithFormat:@"Launch of %@ declined (%@ %ld): %@%@",
                    bundle, error.domain, (long)error.code, detail, cause]);
            } else {
                SPSetStatus(@"App launch accepted.");
                SPFeedback(haptic);
            }
        });
    });
    if (!completion) {
        SPFailure(@"Unable to prepare the app-launch callback."); return;
    }
    [(id<SPApplicationOpening>)service openApplication:bundle withOptions:options completion:completion];
}

static NSString *SPVisibleSecureBundle(void) {
    id manager = SPShared(@"SBCoverSheetPresentationManager");
    NSArray *hosts = @[SPGet(manager, @"secureAppViewController") ?: NSNull.null,
                       SPCoverController() ?: NSNull.null];
    for (id host in hosts) {
        if (!SPBool(host, @"isHostingAnApp", NO)) continue;
        id handle = SPGet(host, @"hostedAppSceneHandle");
        id bundle = SPGet(SPGet(handle, @"application"), @"bundleIdentifier");
        if ([bundle isKindOfClass:NSString.class] && [bundle length]) return bundle;
    }
    return @"(none reported)";
}

static void SPObserveSecurePresentation(NSString *bundle, NSUInteger token,
                                        NSUInteger generation, BOOL haptic, double deadline) {
    if (generation != requestGeneration ||
        SPGetSecureAppLaunchState(token) != SPSecureAppLaunchSubmitted) return;
    if (SPCoverContainsApp(bundle)) {
        NSString *detail = [NSString stringWithFormat:@"%@ visible; UI locked: %@",
            bundle, SPLocked() ? @"YES" : @"NO"];
        SPRecordSecureAppHostResult(token, YES, detail);
        SPSetStatus(@"Selected app is visible in the native Lock Screen host.");
        SPFeedback(haptic);
        return;
    }
    if (NSProcessInfo.processInfo.systemUptime >= deadline) {
        NSString *detail = [NSString stringWithFormat:@"Requested %@; visible secure bundle: %@; UI locked: %@; Cover Sheet visible: %@.",
            bundle, SPVisibleSecureBundle(), SPLocked() ? @"YES" : @"NO", SPCoverVisible() ? @"YES" : @"NO"];
        SPRecordSecureAppHostResult(token, NO, detail);
        SPFailure(@"The selected scene was submitted directly, but iOS did not report it visible in the Lock Screen host. Copy Last Result includes the host details.");
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        SPObserveSecurePresentation(bundle, token, generation, haptic, deadline);
    });
}

static void SPOpenSecureSelectedApp(NSString *bundle, BOOL haptic) {
    NSString *error = nil;
    NSUInteger generation = requestGeneration;
    NSUInteger token = SPStartSecureAppLaunch(SPGet(SPCoverController(), @"applicationLauncher"), bundle, &error);
    if (!token) { SPFailure(error ?: @"Unable to present the selected secure app scene."); return; }
    if (generation != requestGeneration) return;
    SPSetStatus(@"Selected secure app scene submitted; waiting for its host…");
    // A native completion alone is not evidence that the requested app is
    // visible, and must neither cause success nor cancel a still-pending scene.
    SPObserveSecurePresentation(bundle, token, generation, haptic, NSProcessInfo.processInfo.systemUptime + 5.0);
}

static void SPOpenLockScreenCamera(BOOL haptic) {
    id cover = SPCoverController();
    SEL activate = NSSelectorFromString(@"activateCameraViewAnimated:sendingActions:completion:");
    if (![cover respondsToSelector:activate]) {
        SPFailure(@"This iOS build does not expose native Lock Screen Camera presentation."); return;
    }
    NSUInteger generation = requestGeneration;
    SPSetStatus(@"Opening Lock Screen Camera…");
    SPPresentationCompletion completion = (__bridge_transfer SPPresentationCompletion)_Block_copy((__bridge const void *)^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != requestGeneration) return;
            if (SPCoverContainsApp(@"com.apple.camera")) {
                hostPresentedGeneration = generation;
                SPSetStatus(@"Lock Screen Camera is visible.");
                SPFeedback(haptic);
            }
        });
    });
    if (!completion) { SPFailure(@"Unable to prepare the Lock Screen Camera callback."); return; }
    [(id<SPCameraPresentation>)cover activateCameraViewAnimated:YES sendingActions:nil completion:completion];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (generation != requestGeneration || hostPresentedGeneration == generation) return;
        if (SPCoverContainsApp(@"com.apple.camera")) {
            hostPresentedGeneration = generation;
            SPSetStatus(@"Lock Screen Camera is visible.");
        } else {
            SPSetStatus(@"Camera presentation requested; iOS did not report a visible Camera host.");
        }
    });
}

static void SPOpenSelectedApp(NSString *bundle, BOOL haptic) {
    if (![bundle isKindOfClass:NSString.class] || bundle.length == 0) {
        SPFailure(@"Choose an app in SidePress18 settings first."); return;
    }
    // Ordinary foreground launches still use FBS, which preserves an already
    // active target. A visible secure target also remains in place.
    if (SPCoverContainsApp(bundle)) { SPSetStatus(@"The selected app is already visible."); return; }
    SPLaunchRoute route = SPRouteForApp([bundle isEqualToString:@"com.apple.camera"], SPLocked(), SPCoverVisible());
    switch (route) {
        case SPLaunchOrdinary: SPOpenApp(bundle, haptic); break;
        case SPLaunchLockScreenCamera: SPOpenLockScreenCamera(haptic); break;
        case SPLaunchSecureApp: SPOpenSecureSelectedApp(bundle, haptic); break;
    }
}

static void SPRunAction(NSString *action, NSString *bundle, BOOL haptic) {
    if ([action isEqualToString:@"camera"] || [action isEqualToString:@"app"]) {
        SPOpenSelectedApp([action isEqualToString:@"camera"] ? @"com.apple.camera" : bundle, haptic);
        return;
    }
    if ([action isEqualToString:@"flashlight"]) {
        SPLoadFramework("SpringBoardUI");
        // Share the controller used by Control Center and the Lock Screen.
        // An independent AVFlashlight instance can report a stale/off level.
        id flashlight = SPShared(@"SBUIFlashlightController");
        SEL level = NSSelectorFromString(@"level");
        SEL setLevel = NSSelectorFromString(@"setLevel:");
        if (![flashlight respondsToSelector:level] || ![flashlight respondsToSelector:setLevel]) {
            SPFailure(@"Flashlight control is unavailable."); return;
        }
        unsigned long long current = ((unsigned long long (*)(id, SEL))objc_msgSend)(flashlight, level);
        if (current == 0 && (!SPBool(flashlight, @"isAvailable", NO) || SPBool(flashlight, @"isOverheated", YES))) {
            SPFailure(@"Flashlight is busy or temporarily unavailable."); return;
        }
        ((void (*)(id, SEL, unsigned long long))objc_msgSend)(flashlight, setLevel, current > 0 ? 0 : 4);
        SPSetStatus(current > 0 ? @"Flashlight off requested." : @"Flashlight on requested.");
        SPFeedback(haptic);
        return;
    } else if ([@[@"playpause", @"next", @"previous"] containsObject:action]) {
        SPLoadFramework("MediaRemote");
        Boolean (*send)(int, id) = (Boolean (*)(int, id))dlsym(RTLD_DEFAULT, "MRMediaRemoteSendCommand");
        int command = [action isEqualToString:@"playpause"] ? 2 : ([action isEqualToString:@"next"] ? 4 : 5);
        if (!send || !send(command, nil)) { SPFailure(@"No player accepted the media command."); return; }
    } else { return; }
    SPSetStatus([NSString stringWithFormat:@"%@ requested.", SPActionName(action)]);
    SPFeedback(haptic);
}

void SPDispatchAction(NSString *action, NSString *bundleID, BOOL requireUnlock, BOOL haptic) {
    NSCAssert(NSThread.isMainThread, @"Actions must run on the main thread");
    SPCancelPendingAction();
    if (!requireUnlock || !SPLocked()) { SPRunAction(action, bundleID, haptic); return; }
    SPRequestNativeUnlock(action, bundleID, haptic, SPRunAction);
}
