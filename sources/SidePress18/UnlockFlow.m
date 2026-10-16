#import "UnlockFlow.h"
#import "UnlockPolicy.h"
#import "Runtime.h"
#import <UIKit/UIKit.h>
#import <substrate.h>

@protocol SPSystemUnlockPresentation <NSObject>
- (void)lockScreenViewControllerRequestsUnlock;
- (void)setPasscodeVisible:(BOOL)visible animated:(BOOL)animated;
@end
@protocol SPAuthenticatedCoverDismissal <NSObject>
- (void)setCoverSheetPresented:(BOOL)presented animated:(BOOL)animated
                withCompletion:(void (^)(void))completion;
@end

static dispatch_source_t unlockObserver;
static NSUInteger unlockGeneration;
static NSString *pendingAction, *pendingBundle;
static BOOL pendingHaptic;
static SPUnlockedAction pendingPerformer;
static CFAbsoluteTime requestStarted, hiddenPasscodeSince, authenticatedSince;
static BOOL sawPasscode, sawScreenAwake, requestedPasscode, requestedDismissal;
static void (*originalInlineCancel)(id, SEL, id);
static void (*originalOverlayCancel)(id, SEL, id);

// These are read-only checks. Neither Cover Sheet visibility nor isUILocked
// alone proves authentication: Notification Center can keep that UI active.
static id SPUnlockCoverController(void) {
    return SPGet(SPShared(@"SBCoverSheetPresentationManager"), @"coverSheetViewController") ?:
           SPGet(SPShared(@"SBLockScreenManager"), @"coverSheetViewController");
}
static BOOL SPUnlockAuthenticated(void) {
    id auth = SPGet(SPShared(@"SBLockScreenManager"), @"_userAuthController");
    if ([auth respondsToSelector:@selector(isAuthenticated)]) return SPBool(auth, @"isAuthenticated", NO);
    return SPBool(SPUnlockCoverController(), @"isAuthenticated", NO);
}
static BOOL SPUnlockPasscodeVisible(void) {
    id manager = SPShared(@"SBLockScreenManager");
    id cover = SPUnlockCoverController();
    return SPBool(manager, @"_isPasscodeVisible", NO) ||
           SPBool(manager, @"isPasscodeEntryTransientOverlayVisible", NO) ||
           SPBool(cover, @"isPasscodeLockVisible", NO) ||
           SPBool(cover, @"isInlinePasscodeLockVisible", NO);
}
static BOOL SPUnlockCoverVisible(void) {
    id manager = SPShared(@"SBCoverSheetPresentationManager");
    // Include the disappearing animation. Starting the app before this has
    // finished lets the outgoing lock-screen transition cover the app launch.
    return SPBool(manager, @"isPresented", YES) || SPBool(manager, @"isVisible", YES);
}
static BOOL SPUnlockMethodMatches(id target, NSString *name, const char *arguments) {
    Method method = class_getInstanceMethod(object_getClass(target), NSSelectorFromString(name));
    if (!method || method_getNumberOfArguments(method) != strlen(arguments) + 2) return NO;
    char type[32];
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != 'v') return NO;
    for (NSUInteger i = 0; arguments[i]; ++i) {
        method_getArgumentType(method, (unsigned int)i + 2, type, sizeof(type));
        if (arguments[i] == 'B' ? (type[0] != 'B' && type[0] != 'c') : type[0] != arguments[i]) return NO;
    }
    return YES;
}

void SPCancelNativeUnlock(void) {
    NSCAssert(NSThread.isMainThread, @"Unlock cancellation must run on the main thread");
    ++unlockGeneration;
    if (unlockObserver) dispatch_source_cancel(unlockObserver);
    unlockObserver = nil;
    pendingAction = nil;
    pendingBundle = nil;
    pendingPerformer = NULL;
}
static void SPUnlockStopped(NSString *message, BOOL failed) {
    SPCancelNativeUnlock();
    SPSetStatus(message);
    if (failed) [[[UINotificationFeedbackGenerator alloc] init]
        notificationOccurred:UINotificationFeedbackTypeError];
}
static void SPInlinePasscodeCanceled(id self, SEL command, id controller) {
    if (NSThread.isMainThread && pendingPerformer)
        SPUnlockStopped(@"Unlock canceled; no action performed.", NO);
    originalInlineCancel(self, command, controller);
}
static void SPOverlayPasscodeCanceled(id self, SEL command, id controller) {
    if (NSThread.isMainThread && pendingPerformer)
        SPUnlockStopped(@"Unlock canceled; no action performed.", NO);
    originalOverlayCancel(self, command, controller);
}
static BOOL SPInstallNativeUnlockCancellation(void) {
    static BOOL installed;
    if (installed) return YES;
    id cover = SPUnlockCoverController();
    id manager = SPShared(@"SBLockScreenManager");
    NSString *inlineCancel = @"passcodeViewControllerDidCancelPasscodeEntry:";
    NSString *overlayCancel = @"passcodeEntryTransientOverlayViewControllerRequestsDismissal:";
    // Both presentations must invalidate their action before the native Cancel
    // callback can hide UI or allow a later biometric match to be delivered.
    if (!SPUnlockMethodMatches(cover, inlineCancel, "@") ||
        !SPUnlockMethodMatches(manager, overlayCancel, "@")) return NO;
    MSHookMessageEx(object_getClass(cover), NSSelectorFromString(inlineCancel),
        (IMP)SPInlinePasscodeCanceled, (IMP *)&originalInlineCancel);
    MSHookMessageEx(object_getClass(manager), NSSelectorFromString(overlayCancel),
        (IMP)SPOverlayPasscodeCanceled, (IMP *)&originalOverlayCancel);
    installed = YES;
    return YES;
}
static void SPObserveNativeUnlock(NSUInteger generation) {
    if (generation != unlockGeneration || !pendingPerformer) return;
    id manager = SPShared(@"SBLockScreenManager");
    id coverManager = SPShared(@"SBCoverSheetPresentationManager");
    id cover = SPUnlockCoverController();
    BOOL authenticated = SPUnlockAuthenticated();
    BOOL uiLocked = SPBool(manager, @"isUILocked", YES);
    BOOL transitioning = SPBool(manager, @"isUIUnlocking", NO);
    BOOL passcode = SPUnlockPasscodeVisible();
    BOOL screenOff = SPBool(cover, @"isInScreenOffMode", NO);
    if (!screenOff) sawScreenAwake = YES;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    SPUnlockDecision decision = SPDecideUnlock(generation == unlockGeneration,
        pendingPerformer != NULL, authenticated, uiLocked, SPUnlockCoverVisible(),
        screenOff, sawScreenAwake);
    if (decision == SPUnlockDiscard) return;
    if (decision == SPUnlockCancelForScreenOff) {
        SPUnlockStopped(@"Unlock canceled because the screen turned off.", NO);
        return;
    }
    if (decision == SPUnlockPerform) {
        // Clear ownership before calling out; the action can itself dispatch a
        // new request. Authentication is checked again on this same main turn.
        NSString *action = pendingAction, *bundle = pendingBundle;
        BOOL haptic = pendingHaptic;
        SPUnlockedAction performer = pendingPerformer;
        SPCancelNativeUnlock();
        if (SPUnlockAuthenticated() && !SPBool(manager, @"isUILocked", YES))
            performer(action, bundle, haptic);
        return;
    }

    if (authenticated) {
        hiddenPasscodeSince = 0;
        if (authenticatedSince == 0) {
            authenticatedSince = now;
            SPSetStatus(@"Authenticated; finishing the lock-screen transition…");
        }
        // Face ID may already have authenticated an otherwise-visible lock
        // screen. Ask the native manager to finish its normal dismissal only
        // after that authentication; do not set any authentication state.
        if (!requestedDismissal && !transitioning && SPUnlockCoverVisible() &&
            SPUnlockMethodMatches(coverManager, @"setCoverSheetPresented:animated:withCompletion:", "BB@")) {
            requestedDismissal = YES;
            [(id<SPAuthenticatedCoverDismissal>)coverManager setCoverSheetPresented:NO animated:YES withCompletion:nil];
        }
        if (now - authenticatedSince >= 4.0)
            SPUnlockStopped(@"Authenticated, but iOS did not finish dismissing the lock-screen interface. No action was performed.", YES);
        return;
    }
    authenticatedSince = 0;
    if (passcode) {
        sawPasscode = YES;
        hiddenPasscodeSince = 0;
        return; // No deadline while someone is entering a passcode.
    }
    if (sawPasscode && !transitioning) {
        // Allow the authentication result to commit if UIKit hides the field
        // first. A Cancel dismissal must never leave an action waiting for a
        // later, unrelated successful unlock.
        if (hiddenPasscodeSince == 0) hiddenPasscodeSince = now;
        if (now - hiddenPasscodeSince >= 0.25)
            SPUnlockStopped(@"Unlock canceled; no action performed.", NO);
        return;
    }
    if (!requestedPasscode && !transitioning && now - requestStarted >= 0.25) {
        requestedPasscode = YES;
        if (SPUnlockMethodMatches(manager, @"setPasscodeVisible:animated:", "BB"))
            [(id<SPSystemUnlockPresentation>)manager setPasscodeVisible:YES animated:YES];
    }
    // This bounds only a failed presentation, not authentication. Once iOS
    // shows its passcode/Face ID interface, the user can take as long as needed.
    if (!transitioning && !sawPasscode && now - requestStarted >= 4.0)
        SPUnlockStopped(@"iOS did not present its unlock interface. No action was performed.", YES);
}

void SPRequestNativeUnlock(NSString *action, NSString *bundle, BOOL haptic,
                           SPUnlockedAction performAction) {
    NSCAssert(NSThread.isMainThread, @"Unlock requests must run on the main thread");
    SPCancelNativeUnlock();
    id manager = SPShared(@"SBLockScreenManager");
    if (!performAction || !SPUnlockMethodMatches(manager, @"lockScreenViewControllerRequestsUnlock", "")) {
        SPUnlockStopped(@"This iOS build does not expose the native unlock presentation.", YES);
        return;
    }
    if (!SPInstallNativeUnlockCancellation()) {
        SPUnlockStopped(@"This iOS build does not expose both native unlock-cancellation callbacks.", YES);
        return;
    }
    pendingAction = [action copy];
    pendingBundle = [bundle copy];
    pendingHaptic = haptic;
    pendingPerformer = performAction;
    requestStarted = CFAbsoluteTimeGetCurrent();
    hiddenPasscodeSince = 0;
    authenticatedSince = 0;
    sawPasscode = SPUnlockPasscodeVisible();
    sawScreenAwake = !SPBool(SPUnlockCoverController(), @"isInScreenOffMode", NO);
    requestedPasscode = NO;
    requestedDismissal = NO;
    NSUInteger generation = unlockGeneration;
    SPSetStatus(@"Waiting for Touch ID, Face ID, or passcode…");

    // Unlike constructing an empty SBLockScreenUnlockRequest, this lets iOS
    // choose its own correct source, intent, biometric UI, and unlock options.
    [(id<SPSystemUnlockPresentation>)manager lockScreenViewControllerRequestsUnlock];
    if (generation != unlockGeneration) return;
    unlockObserver = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (!unlockObserver) { SPUnlockStopped(@"Unable to observe the native unlock result.", YES); return; }
    dispatch_source_set_timer(unlockObserver, dispatch_time(DISPATCH_TIME_NOW, 0), 80 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
    // libdispatch copies this block through the C Blocks runtime. No block is
    // retained through Objective-C, which avoids the legacy arm64e ISA issue.
    dispatch_source_set_event_handler(unlockObserver, ^{ SPObserveNativeUnlock(generation); });
    dispatch_resume(unlockObserver);
}
