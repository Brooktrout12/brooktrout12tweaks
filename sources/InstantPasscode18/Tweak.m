#import "Compatibility.h"
// SPDX-License-Identifier: MIT
// InstantPasscode18 — brooktrout12
// Change the lock-screen presentation, leaving authentication to iOS.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

static void (*IPOriginalSetPresentation)(id, SEL, bool);
static void (*IPOriginalSetDelegate)(id, SEL, id);
static void (*IPOriginalWillTransition)(id, SEL);
static id (*IPOriginalDefaultStatusText)(id, SEL);
static void (*IPOriginalKeypadLayoutStatus)(id, SEL);
static void (*IPOriginalKeyboardLayoutStatus)(id, SEL);
static char IPLabelSizingKey;

static NSString *const IPFaceIDTitle = @"Face ID or Enter Passcode";

// Match the actual lock-screen controller (including subclasses), rather than
// every passcode prompt inside SpringBoard. No bundle-wide UI traversal.
static bool IPIsLockScreenController(id controller) {
    for (Class cls = object_getClass(controller); cls; cls = class_getSuperclass(cls)) {
        if (strcmp(class_getName(cls), "CSPasscodeViewController") == 0) {
            return true;
        }
    }
    return false;
}

static bool IPIsLockScreenView(id view) {
    id delegate = ((id (*)(id, SEL))objc_msgSend)(view, @selector(delegate));
    return IPIsLockScreenController(delegate);
}

static void IPSetPresentation(id self, SEL cmd, bool requested) {
    // usesBiometricPresentation is distinct from biometricAuthenticationAllowed.
    // Use Apple's setter so its UI state and stored property agree. Do not spoof
    // its getter, mark a biometric attempt failed, or synthesize a button press.
    IPOriginalSetPresentation(self, cmd, IPIsLockScreenView(self) ? false : requested);
}

static void IPApplyPresentation(id view) {
    if (IPIsLockScreenView(view)) {
        bool usesPresentation = ((bool (*)(id, SEL))objc_msgSend)(
            view, @selector(usesBiometricPresentation));
        if (usesPresentation) {
            ((void (*)(id, SEL, bool))objc_msgSend)(
                view, @selector(setUsesBiometricPresentation:), false);
        }
    }
}

static void IPSetDelegate(id self, SEL cmd, id delegate) {
    IPOriginalSetDelegate(self, cmd, delegate);
    // The presentation property can be set before the delegate is assigned.
    // Correct it as soon as the view acquires its lock-screen owner.
    IPApplyPresentation(self);
}

static void IPWillTransition(id self, SEL cmd) {
    // Synchronous: configure the existing passcode view before iOS transitions
    // into it. No timer, delayed callback, private state numbers, or fake failure.
    IPApplyPresentation(self);
    IPOriginalWillTransition(self, cmd);
}

static bool IPTypeMatches(const char *encoding, char expected) {
    if (!encoding) return false;
    while (*encoding && strchr("rnNoORV", *encoding)) ++encoding;
    // Both spellings use the same 1-byte argument ABI on our target architectures.
    if (expected == 'B') return *encoding == 'B' || *encoding == 'c';
    return *encoding == expected;
}

static bool IPMethodMatches(Class cls, SEL selector, char result,
                            const char *arguments) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != strlen(arguments) + 2) {
        return false;
    }
    char *type = method_copyReturnType(method);
    bool valid = IPTypeMatches(type, result);
    free(type);
    for (unsigned int i = 0; valid && arguments[i]; ++i) {
        type = method_copyArgumentType(method, i + 2);
        valid = IPTypeMatches(type, arguments[i]);
        free(type);
    }
    return valid;
}

// These are read-only policy checks. In particular, do not treat hardware
// support alone as evidence that Face ID is enrolled or enabled for unlocking.
static bool IPBoolEquals(id object, SEL selector, bool expected) {
    if (!object || !IPMethodMatches(object_getClass(object), selector, 'B', ""))
        return false;
    return ((bool (*)(id, SEL))objc_msgSend)(object, selector) == expected;
}

static bool IPFaceIDAvailable(id view) {
    if (!IPIsLockScreenView(view) ||
        !IPBoolEquals(view, @selector(isBiometricAuthenticationAllowed), true) ||
        !IPBoolEquals(view, @selector(hasBiometricAuthenticationCapabilityEnabled), true) ||
        !IPBoolEquals(view, @selector(isBiometricLockedOut), false))
        return false;

    id resource = ((id (*)(id, SEL))objc_msgSend)(view, @selector(biometricResource));
    return IPBoolEquals(resource, @selector(hasPearlSupport), true) &&
           IPBoolEquals(resource, @selector(hasEnrolledIdentities), true) &&
           IPBoolEquals(resource, @selector(hasBiometricAuthenticationCapabilityEnabled), true);
}

static id IPDefaultStatusText(id self, SEL cmd) {
    id nativeText = IPOriginalDefaultStatusText(self, cmd);
    return [nativeText isKindOfClass:[NSString class]] && [nativeText length] > 0 && IPFaceIDAvailable(self)
        ? IPFaceIDTitle : nativeText;
}

static void IPPrepareTitleLabel(id view) {
    id candidate = ((id (*)(id, SEL))objc_msgSend)(view, @selector(_statusTitleView));
    if (![candidate isKindOfClass:[UILabel class]]) return;
    UILabel *label = candidate;
    NSDictionary *saved = objc_getAssociatedObject(label, &IPLabelSizingKey);
    if (!IPIsLockScreenView(view) && !saved) return;

    // Refresh the neutral prompt at layout time as well: iOS can create it
    // before assigning the view's delegate. Never replace an error/status title
    // that differs from the native neutral prompt.
    bool eligible = IPFaceIDAvailable(view);
    NSString *nativeText = IPOriginalDefaultStatusText(view, @selector(_defaultStatusText));
    if ([nativeText isKindOfClass:[NSString class]]) {
        if (eligible && [label.text isEqualToString:nativeText])
            label.text = IPFaceIDTitle;
        else if (!eligible && [label.text isEqualToString:IPFaceIDTitle])
            label.text = nativeText;
    }

    if (eligible && [label.text isEqualToString:IPFaceIDTitle]) {
        if (!saved) {
            saved = @{@"fit": @(label.adjustsFontSizeToFitWidth),
                      @"minimum": @(label.minimumScaleFactor),
                      @"lines": @(label.numberOfLines),
                      @"baseline": @(label.baselineAdjustment)};
            objc_setAssociatedObject(label, &IPLabelSizingKey, saved,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        // Keep Apple's font and available label width. UILabel only reduces
        // the rendered text size when the complete string would not fit.
        label.numberOfLines = 1;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.70;
        label.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    } else if (saved) {
        label.adjustsFontSizeToFitWidth = [saved[@"fit"] boolValue];
        label.minimumScaleFactor = [saved[@"minimum"] doubleValue];
        label.numberOfLines = [saved[@"lines"] integerValue];
        label.baselineAdjustment = [saved[@"baseline"] integerValue];
        objc_setAssociatedObject(label, &IPLabelSizingKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void IPKeypadLayoutStatus(id self, SEL cmd) {
    // Set the text before native layout calculates its width and positions.
    IPPrepareTitleLabel(self);
    IPOriginalKeypadLayoutStatus(self, cmd);
}

static void IPKeyboardLayoutStatus(id self, SEL cmd) {
    IPPrepareTitleLabel(self);
    IPOriginalKeyboardLayoutStatus(self, cmd);
}

static void IPInstallTitleHooks(Class base) {
    // The cosmetic extension has its own interface guard. Missing title APIs
    // must not disable the original, device-tested instant-keypad behavior.
    if (!IPMethodMatches(base, @selector(_defaultStatusText), '@', "") ||
        !IPMethodMatches(base, @selector(biometricResource), '@', "") ||
        !IPMethodMatches(base, @selector(isBiometricAuthenticationAllowed), 'B', "") ||
        !IPMethodMatches(base, @selector(hasBiometricAuthenticationCapabilityEnabled), 'B', "") ||
        !IPMethodMatches(base, @selector(isBiometricLockedOut), 'B', "")) {
        NSLog(@"[InstantPasscode18] Title interface unavailable; keeping native title.");
        return;
    }
    MSHookMessageEx(base, @selector(_defaultStatusText),
                   (IMP)IPDefaultStatusText, (IMP *)&IPOriginalDefaultStatusText);

    Class keypad = NSClassFromString(@"SBUIPasscodeLockViewWithKeypad");
    if (IPMethodMatches(keypad, @selector(_layoutStatusView), 'v', "") &&
        IPMethodMatches(keypad, @selector(_statusTitleView), '@', "")) {
        MSHookMessageEx(keypad, @selector(_layoutStatusView),
                       (IMP)IPKeypadLayoutStatus, (IMP *)&IPOriginalKeypadLayoutStatus);
    }
    Class keyboard = NSClassFromString(@"SBUIPasscodeLockViewWithKeyboard");
    if (IPMethodMatches(keyboard, @selector(_layoutStatusView), 'v', "") &&
        IPMethodMatches(keyboard, @selector(_statusTitleView), '@', "")) {
        MSHookMessageEx(keyboard, @selector(_layoutStatusView),
                       (IMP)IPKeyboardLayoutStatus, (IMP *)&IPOriginalKeyboardLayoutStatus);
    }
}

__attribute__((constructor)) static void IPInitialize(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"])
            return;
        // Support the reviewed iOS 17 and iOS 18 families.
        if (!BTSupportsIOS17And18())
            return;

        Class cls = NSClassFromString(@"SBUIPasscodeLockViewBase");
        if (!cls ||
            !IPMethodMatches(cls, @selector(delegate), '@', "") ||
            !IPMethodMatches(cls, @selector(usesBiometricPresentation), 'B', "") ||
            !IPMethodMatches(cls, @selector(setUsesBiometricPresentation:), 'v', "B") ||
            !IPMethodMatches(cls, @selector(setDelegate:), 'v', "@") ||
            !IPMethodMatches(cls, @selector(willTransitionToPasscodeView), 'v', "")) {
            NSLog(@"[InstantPasscode18] Required presentation interface unavailable; inactive.");
            return;
        }

        MSHookMessageEx(cls, @selector(setUsesBiometricPresentation:),
                       (IMP)IPSetPresentation, (IMP *)&IPOriginalSetPresentation);
        MSHookMessageEx(cls, @selector(setDelegate:),
                       (IMP)IPSetDelegate, (IMP *)&IPOriginalSetDelegate);
        MSHookMessageEx(cls, @selector(willTransitionToPasscodeView),
                       (IMP)IPWillTransition, (IMP *)&IPOriginalWillTransition);
        IPInstallTitleHooks(cls);
        NSLog(@"[InstantPasscode18] 1.1.1 loaded; lock-screen presentation hooks installed.");
    }
}
