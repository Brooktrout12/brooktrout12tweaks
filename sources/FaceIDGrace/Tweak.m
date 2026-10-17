#import "Compatibility.h"
// FaceIDGrace — Brooktrout12
// See README.md and REFERENCES.md for behavior, limitations, and API evidence.

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <stdatomic.h>
#import <stdbool.h>
#import <stdint.h>
#import <substrate.h>
#include "FGMenuScope.h"

static pthread_mutex_t FGInstallMutex = PTHREAD_MUTEX_INITIALIZER;
static atomic_bool FGInstallQueued = ATOMIC_VAR_INIT(false);
static const char FGBundleObserverToken;
static bool FGUpdateInstalled, FGIdentitiesInstalled, FGCountInstalled;
static bool FGBiometricInstalled, FGProfileInstalled;

static void (*FGOriginalUpdate)(id, SEL, id);
static BOOL (*FGOriginalBiometricUnlockAllowed)(id, SEL);
static BOOL (*FGOriginalProfileUnlockAllowed)(id, SEL);
static id (*FGOriginalIdentities)(id, SEL);
static long long (*FGOriginalFingerprintCount)(id, SEL);

// Only the synchronous menu-building call on THIS thread sees the override.
// Reentrant menu builds and Objective-C exceptions both restore the previous
// scope. Other threads and every call outside this scope use Apple's answer.
static void FGUpdateGracePeriod(id self, SEL command, id specifier) {
    uintptr_t previousDepth;
    if (!FGEnterMenu(&previousDepth)) {
        FGOriginalUpdate(self, command, specifier);
        return;
    }

    @try {
        FGOriginalUpdate(self, command, specifier);
    } @finally {
        // The key remains allocated for the lifetime of this injected library.
        FGLeaveMenu(previousDepth);
    }
}

static BOOL FGBiometricUnlockAllowed(id self, SEL command) {
    if (FGMenuActive()) {
        return NO;
    }
    return FGOriginalBiometricUnlockAllowed(self, command);
}

// Retain both query providers when available, without assuming which OS
// version routes its menu through which provider.
static BOOL FGProfileUnlockAllowed(id self, SEL command) {
    if (FGMenuActive()) return NO;
    return FGOriginalProfileUnlockAllowed(self, command);
}

// +identities is shared by Touch ID and Face ID. The native menu tests its
// count before applying the biometric-only immediate-passcode clamp. This
// works without guessing where a particular OS implements its allow query.
static id FGIdentities(id self, SEL command) {
    if (FGMenuActive()) return @[];
    return FGOriginalIdentities(self, command);
}

static long long FGFingerprintCount(id self, SEL command) {
    if (FGMenuActive()) return 0;
    return FGOriginalFingerprintCount(self, command);
}

// Do not hook a private selector if its ABI has changed. The relevant method
// signatures were checked against the iOS 18.2 runtime implementation.
static BOOL FGHasSignature(Method method, unsigned int argumentCount,
                           char resultType) {
    if (!method || method_getNumberOfArguments(method) != argumentCount) {
        return NO;
    }
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (resultType == 'B' ? (type[0] != 'B' && type[0] != 'c') : type[0] != resultType) {
        return NO;
    }
    if (resultType == '@' && type[1] == '?') return NO;
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
    // A bundle may become available after the first working provider. Keep
    // installing missing routes on image loads; never hook a route twice.
    // If a loader callback reenters during installation, defer to its queued
    // main-thread attempt rather than deadlocking the recursive load.
    if (pthread_mutex_trylock(&FGInstallMutex) != 0) return;
    {
        Class controller = objc_getClass("PSUIPasscodeLockController");
        Class biometrics = objc_getClass("PSUIBiometrics");
        Class profile = objc_getClass("MCProfileConnection");
        SEL update = sel_registerName("_updateGracePeriodForSpecifier:");
        SEL allowed = sel_registerName("isFingerprintUnlockAllowed");
        SEL identities = sel_registerName("identities");
        SEL count = sel_registerName("fingerprintCount");

        Method updateMethod = class_getInstanceMethod(controller, update);
        Method allowedMethod = class_getInstanceMethod(biometrics, allowed);
        Method profileMethod = class_getInstanceMethod(profile, allowed);
        if (FGHasSignature(updateMethod, 3, 'v')) {
            // Install the query hook first. It is inert until the updater
            // enters its thread-local scope.
            if (!FGIdentitiesInstalled &&
                FGHasSignature(class_getClassMethod(biometrics, identities), 2, '@')) {
                MSHookMessageEx(object_getClass(biometrics), identities, (IMP)FGIdentities,
                               (IMP *)&FGOriginalIdentities);
                FGIdentitiesInstalled = true;
            }
            if (!FGCountInstalled &&
                FGHasSignature(class_getInstanceMethod(controller, count), 2, 'q')) {
                MSHookMessageEx(controller, count, (IMP)FGFingerprintCount,
                               (IMP *)&FGOriginalFingerprintCount);
                FGCountInstalled = true;
            }
            if (!FGBiometricInstalled && FGHasSignature(allowedMethod, 2, 'B')) {
                MSHookMessageEx(biometrics, allowed, (IMP)FGBiometricUnlockAllowed,
                               (IMP *)&FGOriginalBiometricUnlockAllowed);
                FGBiometricInstalled = true;
            }
            if (!FGProfileInstalled && FGHasSignature(profileMethod, 2, 'B')) {
                MSHookMessageEx(profile, allowed, (IMP)FGProfileUnlockAllowed,
                               (IMP *)&FGOriginalProfileUnlockAllowed);
                FGProfileInstalled = true;
            }
            if (!FGUpdateInstalled && (FGIdentitiesInstalled || FGCountInstalled ||
                                      FGBiometricInstalled || FGProfileInstalled)) {
                MSHookMessageEx(controller, update, (IMP)FGUpdateGracePeriod,
                               (IMP *)&FGOriginalUpdate);
                FGUpdateInstalled = true;
            }
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

static void FGBundleLoaded(CFNotificationCenterRef center, void *observer,
                           CFNotificationName name, const void *object,
                           CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    @autoreleasepool {
        FGInstallHooks();
    }
}

__attribute__((constructor)) static void FGInitialize(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier
              isEqualToString:@"com.apple.Preferences"]) return;
        if (!BTSupportsIOS17And18())
            return;
        if (pthread_key_create(&FGMenuDepthKey, NULL) != 0) return;

        FGInstallHooks();

        // PreferencesUI may load only when the biometric passcode pane opens.
        // A bundle notification is synchronous, so hooks are ready before
        // the newly loaded controller starts constructing its menu.
        // Use a C callback: the legacy Linux arm64e toolchain emits block ISA
        // metadata that our ABI converter does not repair. Retaining/releasing
        // that global block caused the 1.0.2 Settings pointer-authentication
        // trap. No Objective-C block object is created by this registration.
        CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(),
            &FGBundleObserverToken, FGBundleLoaded,
            (__bridge CFStringRef)NSBundleDidLoadNotification, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        _dyld_register_func_for_add_image(FGImageAdded);
        FGQueueInstall();
    }
}
