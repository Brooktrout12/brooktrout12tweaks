#import "Compatibility.h"
// FaceIDGrace — Brooktrout12
// See README.md and REFERENCES.md for behavior, limitations, and API evidence.

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <stdatomic.h>
#import <stdbool.h>
#import <stdint.h>
#import <substrate.h>

static pthread_key_t FGMenuDepthKey;
static pthread_mutex_t FGInstallMutex = PTHREAD_MUTEX_INITIALIZER;
static atomic_bool FGInstalled = ATOMIC_VAR_INIT(false);
static atomic_bool FGInstallQueued = ATOMIC_VAR_INIT(false);
static id FGBundleObserver;

static void (*FGOriginalUpdate)(id, SEL, id);
static BOOL (*FGOriginalBiometricUnlockAllowed)(id, SEL);
static BOOL (*FGOriginalProfileUnlockAllowed)(id, SEL);

// Only the synchronous menu-building call on THIS thread sees the override.
// Reentrant menu builds and Objective-C exceptions both restore the previous
// scope. Other threads and every call outside this scope use Apple's answer.
static void FGUpdateGracePeriod(id self, SEL command, id specifier) {
    uintptr_t previousDepth = (uintptr_t)pthread_getspecific(FGMenuDepthKey);
    if (previousDepth == UINTPTR_MAX ||
        pthread_setspecific(FGMenuDepthKey, (void *)(previousDepth + 1)) != 0) {
        FGOriginalUpdate(self, command, specifier);
        return;
    }

    @try {
        FGOriginalUpdate(self, command, specifier);
    } @finally {
        // The key remains allocated for the lifetime of this injected library.
        pthread_setspecific(FGMenuDepthKey, (void *)previousDepth);
    }
}

static BOOL FGBiometricUnlockAllowed(id self, SEL command) {
    if ((uintptr_t)pthread_getspecific(FGMenuDepthKey) != 0) {
        return NO;
    }
    return FGOriginalBiometricUnlockAllowed(self, command);
}

// iOS 17 exposes this query on MCProfileConnection. Its override has the
// same tightly bounded, thread-local menu scope as the existing iOS 18 path.
static BOOL FGProfileUnlockAllowed(id self, SEL command) {
    if ((uintptr_t)pthread_getspecific(FGMenuDepthKey) != 0) return NO;
    return FGOriginalProfileUnlockAllowed(self, command);
}

// Do not hook a private selector if its ABI has changed. The relevant method
// signatures were checked against the iOS 18.2 runtime implementation.
static BOOL FGHasSignature(Method method, unsigned int argumentCount,
                           BOOL returnsBoolean) {
    if (!method || method_getNumberOfArguments(method) != argumentCount) {
        return NO;
    }
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (returnsBoolean ? (type[0] != 'B' && type[0] != 'c') : type[0] != 'v') {
        return NO;
    }
    method_getArgumentType(method, 0, type, sizeof(type));
    if (type[0] != '@') return NO;
    method_getArgumentType(method, 1, type, sizeof(type));
    if (type[0] != ':') return NO;
    if (argumentCount == 3) {
        method_getArgumentType(method, 2, type, sizeof(type));
        if (type[0] != '@') return NO;
    }
    return YES;
}

static void FGInstallHooks(void) {
    if (atomic_load_explicit(&FGInstalled, memory_order_acquire)) return;

    pthread_mutex_lock(&FGInstallMutex);
    if (!atomic_load_explicit(&FGInstalled, memory_order_relaxed)) {
        Class controller = objc_getClass("PSUIPasscodeLockController");
        Class biometrics = objc_getClass("PSUIBiometrics");
        Class profile = objc_getClass("MCProfileConnection");
        SEL update = sel_registerName("_updateGracePeriodForSpecifier:");
        SEL allowed = sel_registerName("isFingerprintUnlockAllowed");

        Method updateMethod = class_getInstanceMethod(controller, update);
        Method allowedMethod = class_getInstanceMethod(biometrics, allowed);
        Method profileMethod = class_getInstanceMethod(profile, allowed);
        BOOL biometricQuery = FGHasSignature(allowedMethod, 2, YES);
        // Keep the existing iOS 18 hook set unchanged. The legacy provider is
        // used only on iOS 17, where it is present in runtime headers.
        BOOL profileQuery = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 17 &&
                            FGHasSignature(profileMethod, 2, YES);
        if (FGHasSignature(updateMethod, 3, NO) &&
            (biometricQuery || profileQuery)) {
            // Install the query hook first. It is inert until the updater
            // enters its thread-local scope.
            if (biometricQuery)
                MSHookMessageEx(biometrics, allowed, (IMP)FGBiometricUnlockAllowed,
                               (IMP *)&FGOriginalBiometricUnlockAllowed);
            if (profileQuery)
                MSHookMessageEx(profile, allowed, (IMP)FGProfileUnlockAllowed,
                               (IMP *)&FGOriginalProfileUnlockAllowed);
            MSHookMessageEx(controller, update, (IMP)FGUpdateGracePeriod,
                           (IMP *)&FGOriginalUpdate);
            atomic_store_explicit(&FGInstalled, true, memory_order_release);
        }
    }
    pthread_mutex_unlock(&FGInstallMutex);
}

static void FGRunQueuedInstall(void *context) {
    (void)context;
    atomic_store_explicit(&FGInstallQueued, false, memory_order_release);
    @autoreleasepool {
        FGInstallHooks();
    }
}

static void FGQueueInstall(void) {
    if (atomic_load_explicit(&FGInstalled, memory_order_acquire)) return;
    if (!atomic_exchange_explicit(&FGInstallQueued, true, memory_order_acq_rel)) {
        dispatch_async_f(dispatch_get_main_queue(), NULL, FGRunQueuedInstall);
    }
}

static void FGImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)header;
    (void)slide;
    // dyld calls this under its loader lock. Defer Obj-C work until it returns.
    // Initial images are coalesced into one task; there is no polling timer.
    FGQueueInstall();
}

__attribute__((constructor)) static void FGInitialize(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier
              isEqualToString:@"com.apple.Preferences"]) return;
        if (!BTSupportsIOS17And18())
            return;
        if (pthread_key_create(&FGMenuDepthKey, NULL) != 0) return;

        FGInstallHooks();
        if (atomic_load_explicit(&FGInstalled, memory_order_acquire)) return;

        // PreferencesUI may load only when Face ID & Passcode is opened.
        // A bundle notification is synchronous, so hooks are ready before
        // the newly loaded controller starts constructing its menu.
        FGBundleObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:NSBundleDidLoadNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *notification) {
                        (void)notification;
                        FGInstallHooks();
                    }];
        _dyld_register_func_for_add_image(FGImageAdded);
        FGQueueInstall();
    }
}
