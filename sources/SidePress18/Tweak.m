#import "Compatibility.h"
#import <UIKit/UIKit.h>
#import <substrate.h>
#import "Runtime.h"
#import "Shared.h"
#import "ClickSpeed.h"
#import "ClickSpeedRuntime.h"
#import "PressPolicy.h"

static BOOL enabled = YES, requireUnlock = NO, haptic = YES, ready;
static NSString *action = SP_DEFAULT_ACTION, *appID = @"";
static NSHashTable *providers;
static SPPressPolicy policy;
static __weak id sequenceActions, sequenceSleep;
static NSUInteger sequenceGeneration;

static void (*originalInitial)(id, SEL), (*originalSingle)(id, SEL), (*originalDouble)(id, SEL);
static void (*originalFinal)(id, SEL), (*originalSleep)(id, SEL), (*originalSound)(id, SEL);
static BOOL (*originalWait)(id, SEL);
static id (*originalParameters)(id, SEL);
static void (*originalInitialUp)(id, SEL);
static BOOL SPMethodMatches(Class cls, const char *name, const char *signature);

static BOOL SPCustom(void) { return ready && enabled && ![action isEqualToString:@"native"]; }
static BOOL SPIntercept(id actions) {
    if (!SPCustom() || !NSThread.isMainThread) return NO;
    if (SPBool(actions, @"_isSOSActive", NO)) return NO;
    if (SPGet(actions, @"_foregroundAppRegisteredForLockButtonEvents")) return NO;
    id service = SPShared(@"SBHardwareButtonService");
    // If the native secure-intent gate is absent, leave the button with iOS.
    if (SPBool(service, @"hasConsumersForLockButtonDoublePressUp", YES)) return NO;
    return YES;
}
static void SPResetSequence(void) {
    SPReset(&policy); sequenceActions = nil; sequenceSleep = nil; ++sequenceGeneration;
}
static void SPSleep(id self, SEL cmd) {
    if (NSThread.isMainThread && self == sequenceSleep && SPDeferSleep(&policy)) return;
    SPRecordSleepRequest();
    originalSleep(self, cmd);
}
static void SPSound(id self, SEL cmd) {
    if (NSThread.isMainThread && self == sequenceSleep && SPDeferSound(&policy)) return;
    originalSound(self, cmd);
}
static void SPInitial(id self, SEL cmd) {
    if (NSThread.isMainThread) {
        SPRecordButtonDown();
        SPResetSequence();
        SPCancelPendingAction();
        if (SPIntercept(self)) {
            SPBegin(&policy);
            sequenceActions = self;
            sequenceSleep = SPGet(self, @"sleepWakeButtonInteraction");
            NSUInteger generation = sequenceGeneration;
            // A safety release only; native recognizers own all click timing.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if (generation == sequenceGeneration) SPResetSequence();
            });
        }
    }
    originalInitial(self, cmd);
}
static void SPInitialUp(id self, SEL cmd) {
    SPRecordButtonUp();
    originalInitialUp(self, cmd);
}
static void SPSingle(id self, SEL cmd) {
    if (!NSThread.isMainThread || self != sequenceActions || policy.phase != SPWaiting) {
        originalSingle(self, cmd); return;
    }
    id sleeper = sequenceSleep;
    SPResolveSingle(&policy);
    originalSingle(self, cmd);
    // Some OS versions already perform the sleep here; replay only if needed.
    if (sleeper && SPReplaySleep(&policy)) {
        SPRecordSleepRequest();
        originalSleep(sleeper, NSSelectorFromString(@"_performSleep"));
    }
    if (sleeper && SPReplaySound(&policy)) originalSound(sleeper, NSSelectorFromString(@"_playLockSound"));
    SPResetSequence();
}
static void SPDouble(id self, SEL cmd) {
    SPCancelButtonTiming();
    if (!SPIntercept(self)) { SPResetSequence(); originalDouble(self, cmd); return; }
    SPResolveDouble(&policy);
    sequenceActions = self;
    sequenceSleep = SPGet(self, @"sleepWakeButtonInteraction");
    NSString *selectedAction = [action copy], *selectedApp = [appID copy];
    BOOL auth = requireUnlock, feedback = haptic;
    // Launch after this recognizer callback, outside native gesture mutation.
    dispatch_async(dispatch_get_main_queue(), ^{ SPDispatchAction(selectedAction, selectedApp, auth, feedback); });
}
static void SPFinal(id self, SEL cmd) {
    originalFinal(self, cmd);
    if (NSThread.isMainThread && self == sequenceActions && policy.phase == SPConsumedDouble)
        SPResetSequence();
}
static BOOL SPWait(id self, SEL cmd) { return SPIntercept(self) ? YES : originalWait(self, cmd); }
static id SPParameters(id self, SEL cmd) {
    id parameters = originalParameters(self, cmd);
    if (NSThread.isMainThread) [providers addObject:self];
    BOOL customAction = SPCustom();
    if (!customAction ||
        ![parameters respondsToSelector:@selector(mutableCopy)]) return parameters;
    SEL countGetter = NSSelectorFromString(@"maximumPressCount");
    if (!SPMethodMatches([parameters class], "maximumPressCount", "q")) return parameters;
    long long maximum = ((long long (*)(id, SEL))objc_msgSend)(parameters, countGetter);
    BOOL needsDoublePress = customAction && maximum < 2;
    if (!needsDoublePress) return parameters;
    id modified = [parameters mutableCopy];
    if (needsDoublePress) {
        if (!SPMethodMatches([modified class], "setMaximumPressCount:", "vq")) return parameters;
        ((void (*)(id, SEL, long long))objc_msgSend)(modified, sel_registerName("setMaximumPressCount:"), 2);
    }
    // Timing is applied at the final side-button recognizers, after all native
    // providers have been merged. Keep this source provider's intervals native.
    return modified;
}

// Match runtime signatures before installing. All-or-nothing core installation.
static BOOL SPTypeIs(const char *actual, char expected) {
    while (*actual && strchr("rnNoORV", *actual)) ++actual;
    return expected == 'B' ? (*actual == 'B' || *actual == 'c') : *actual == expected;
}
static BOOL SPMethodMatches(Class cls, const char *name, const char *signature) {
    Method method = class_getInstanceMethod(cls, sel_registerName(name));
    if (!method || method_getNumberOfArguments(method) != strlen(signature) + 1) return NO;
    char type[128]; method_getReturnType(method, type, sizeof(type));
    if (!SPTypeIs(type, signature[0])) return NO;
    for (size_t i = 1; signature[i]; ++i) {
        method_getArgumentType(method, (unsigned int)i + 1, type, sizeof(type));
        if (!SPTypeIs(type, signature[i])) return NO;
    }
    return YES;
}
typedef struct { Class cls; const char *name, *signature; IMP replacement, original; } SPCancelHook;
static SPCancelHook cancelHooks[16];
static NSUInteger cancelHookCount;
static IMP SPCancelOriginal(id self, SEL cmd) {
    for (NSUInteger i = 0; i < cancelHookCount; ++i)
        if (cmd == sel_registerName(cancelHooks[i].name) && [self isKindOfClass:cancelHooks[i].cls])
            return cancelHooks[i].original;
    return NULL;
}
static void SPCancel0(id self, SEL cmd) {
    if (NSThread.isMainThread) {
        SPCancelButtonTiming();
        SPResetSequence();
        // Presentation changes can reset a recognizer without another user
        // gesture. Do not cancel authentication merely because its UI opened.
        if (cmd != sel_registerName("cancelHardwareButtonPress") &&
            cmd != sel_registerName("performLongPressCancelledActions")) SPCancelPendingAction();
    }
    IMP original = SPCancelOriginal(self, cmd);
    if (original) ((void (*)(id, SEL))original)(self, cmd);
}
static void SPCancel1(id self, SEL cmd, id argument) {
    if (NSThread.isMainThread) { SPCancelButtonTiming(); SPResetSequence(); SPCancelPendingAction(); }
    IMP original = SPCancelOriginal(self, cmd);
    if (original) ((void (*)(id, SEL, id))original)(self, cmd, argument);
}
static void SPInstallCancel(Class cls, const char *name, BOOL argument) {
    const char *signature = argument ? "v@" : "v";
    if (!SPMethodMatches(cls, name, signature) || cancelHookCount == 16) return;
    SPCancelHook *hook = &cancelHooks[cancelHookCount++];
    *hook = (SPCancelHook){cls, name, signature, argument ? (IMP)SPCancel1 : (IMP)SPCancel0, NULL};
    MSHookMessageEx(cls, sel_registerName(name), hook->replacement, &hook->original);
}
static void SPReload(void) {
    CFPreferencesAppSynchronize(SP_DOMAIN);
    id value = SPRead(@"Enabled", @YES);
    enabled = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : YES;
    value = SPRead(@"RequireUnlock", @NO);
    requireUnlock = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
    value = SPRead(@"Haptic", @YES);
    haptic = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : YES;
    action = [SPSelectedAction() copy];
    value = SPRead(@"AppID", @"");
    appID = [value isKindOfClass:NSString.class] ? [value copy] : @"";
    SPResetSequence();
    SPCancelPendingAction();
    for (id provider in providers.allObjects) {
        SEL selector = NSSelectorFromString(@"publishUpdatedParameters:");
        id parameters = SPGet(provider, @"hardwareButtonGestureParameters");
        if (parameters && [provider respondsToSelector:selector])
            ((void (*)(id, SEL, id))objc_msgSend)(provider, selector, parameters);
    }
    SPReloadClickSpeedRuntime();
}
static void SPChanged(__unused CFNotificationCenterRef center, __unused void *observer,
                      __unused CFStringRef name, __unused const void *object, __unused CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ SPReload(); });
}

__attribute__((constructor)) static void SPInitialize(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
            !BTSupportsIOS17And18()) return;
        providers = [NSHashTable weakObjectsHashTable];
        SPReload();
        Class actions = NSClassFromString(@"SBLockHardwareButtonActions");
        Class sleep = NSClassFromString(@"SBSleepWakeHardwareButtonInteraction");
        struct { Class cls; const char *name, *signature; IMP implementation; IMP *original; } hooks[] = {
            {actions, "performInitialButtonDownActions", "v", (IMP)SPInitial, (IMP *)&originalInitial},
            {actions, "performSinglePressAction", "v", (IMP)SPSingle, (IMP *)&originalSingle},
            {actions, "performDoublePressActions", "v", (IMP)SPDouble, (IMP *)&originalDouble},
            {actions, "performFinalButtonUpActions", "v", (IMP)SPFinal, (IMP *)&originalFinal},
            {actions, "_shouldWaitForDoublePress", "B", (IMP)SPWait, (IMP *)&originalWait},
            {actions, "hardwareButtonGestureParameters", "@", (IMP)SPParameters, (IMP *)&originalParameters},
            {sleep, "_performSleep", "v", (IMP)SPSleep, (IMP *)&originalSleep},
            {sleep, "_playLockSound", "v", (IMP)SPSound, (IMP *)&originalSound}
        };
        for (NSUInteger i = 0; i < sizeof(hooks) / sizeof(hooks[0]); ++i) {
            if (!SPMethodMatches(hooks[i].cls, hooks[i].name, hooks[i].signature)) {
                SPSetStatus(@"Inactive: this iOS build has a different button interface.");
                NSLog(@"[SidePress18] Unsupported interface: %s", hooks[i].name);
                return;
            }
        }
        for (NSUInteger i = 0; i < sizeof(hooks) / sizeof(hooks[0]); ++i)
            MSHookMessageEx(hooks[i].cls, sel_registerName(hooks[i].name), hooks[i].implementation, hooks[i].original);
        for (NSString *name in @[@"performLongPressActions", @"performLongPressCancelledActions",
                                  @"performTriplePressActions", @"performTerminalLockLongPressActions",
                                  @"performSOSGestureBeganActions", @"performForceResetSequenceBeganActions"])
            SPInstallCancel(actions, name.UTF8String, NO);
        Class button = NSClassFromString(@"SBLockHardwareButton");
        SPInstallClickSpeedRuntime();
        if (SPMethodMatches(actions, "performInitialButtonUpActions", "v"))
            MSHookMessageEx(actions, sel_registerName("performInitialButtonUpActions"), (IMP)SPInitialUp, (IMP *)&originalInitialUp);
        SPInstallCancel(button, "cancelHardwareButtonPress", NO);
        SPInstallCancel(button, "forceResetSequenceDidBegin", NO);
        SPInstallCancel(button, "screenshotRecognizerDidRecognize:", YES);
        SPInstallCancel(button, "quadruplePress:", YES);
        ready = YES;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, SPChanged,
                                        SP_CHANGED, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        SPSetStatus(@"Ready. Double-press the side button to try your action.");
    }
}
