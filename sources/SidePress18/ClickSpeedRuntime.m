#import "ClickSpeedRuntime.h"
#import "ClickSpeed.h"
#import "ClickSpeedPolicy.h"
#import "Runtime.h"
#import <substrate.h>
#include <math.h>

static void (*originalReconfigure)(id, SEL);
static NSHashTable *buttons;
static NSMapTable *originalTimings;
static NSString *recognizerDiagnostic;
static double pressDownTime, pressUpTime;

static BOOL SPMatches(Class cls, const char *name, const char *result, const char *argument) {
    Method method = class_getInstanceMethod(cls, sel_registerName(name));
    if (!method || method_getNumberOfArguments(method) != (argument ? 3u : 2u)) return NO;
    char type[64]; method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, result)) return NO;
    if (argument) {
        method_getArgumentType(method, 2, type, sizeof(type));
        if (strcmp(type, argument)) return NO;
    }
    return YES;
}

static NSArray *SPButtonRecognizers(id button) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *name in @[@"singlePressGestureRecognizer", @"doublePressGestureRecognizer", @"triplePressGestureRecognizer"]) {
        if (!SPMatches(object_getClass(button), name.UTF8String, "@", NULL)) continue;
        id recognizer = SPGet(button, name);
        if (recognizer) [result addObject:@[name, recognizer]];
    }
    return result;
}

static void SPRestoreTimings(id button) {
    for (NSArray *pair in SPButtonRecognizers(button)) {
        id recognizer = pair[1];
        NSDictionary *values = [originalTimings objectForKey:recognizer];
        for (NSString *setter in values) {
            if (SPMatches(object_getClass(recognizer), setter.UTF8String, "v", "d"))
                ((void (*)(id, SEL, double))objc_msgSend)(recognizer, NSSelectorFromString(setter), [values[setter] doubleValue]);
        }
        [originalTimings removeObjectForKey:recognizer];
    }
}

static void SPApplyTimings(id button) {
    double interval = SPClickSpeedInterval();
    double nativeWindow = 0;
    if (SPMatches(object_getClass(button), "buttonGestureParameters", "@", NULL)) {
        id parameters = SPGet(button, @"buttonGestureParameters");
        if (SPMatches(object_getClass(parameters), "multiplePressTimeInterval", "d", NULL))
            nativeWindow = ((double (*)(id, SEL))objc_msgSend)(parameters, sel_registerName("multiplePressTimeInterval"));
    }
    NSMutableString *report = [NSMutableString stringWithFormat:@"Selected speed: %@\n",
        interval > 0 ? [NSString stringWithFormat:@"%@ (%.0f ms)", SPClickSpeedChoice() == 1 ? @"Faster" : @"Fastest", interval * 1000] : @"iOS native"];
    [report appendFormat:@"Native multi-click parameter: %.0f ms\n", nativeWindow * 1000];
    // Apply after SpringBoard has merged all parameter providers and configured
    // its actual recognizers. A source-provider override alone can be lost.
    // No new timer, synthetic presses or early replay of the sleep action.
    for (NSArray *pair in SPButtonRecognizers(button)) {
        NSString *name = pair[0]; id recognizer = pair[1];
        NSMutableDictionary *saved = [NSMutableDictionary dictionary];
        for (NSArray *field in @[@[@"maximumBetweenClicksDelay", @"setMaximumBetweenClicksDelay:"],
                                  @[@"waitForPreemptionTimeInterval", @"setWaitForPreemptionTimeInterval:"]]) {
            NSString *getter = field[0], *setter = field[1];
            if (!SPMatches(object_getClass(recognizer), getter.UTF8String, "d", NULL) ||
                !SPMatches(object_getClass(recognizer), setter.UTF8String, "v", "d")) {
                [report appendFormat:@"%@.%@: unavailable\n", name, getter]; continue;
            }
            double native = ((double (*)(id, SEL))objc_msgSend)(recognizer, NSSelectorFromString(getter));
            if (!isfinite(native) || native < 0) continue;
            // A zero preemption window means no wait; do not introduce one.
            double desired = SPScaledClickWait(native, nativeWindow, interval);
            if (desired != native) {
                saved[setter] = @(native);
                ((void (*)(id, SEL, double))objc_msgSend)(recognizer, NSSelectorFromString(setter), desired);
            }
            double actual = ((double (*)(id, SEL))objc_msgSend)(recognizer, NSSelectorFromString(getter));
            [report appendFormat:@"%@.%@: %.0f ms (native %.0f ms)\n", name, getter, actual * 1000, native * 1000];
        }
        if (saved.count) [originalTimings setObject:saved forKey:recognizer];
    }
    recognizerDiagnostic = report;
    SPWrite(@"LastClickSpeedConfiguration", report);
}

static void SPReconfigure(id self, SEL cmd) {
    if (!NSThread.isMainThread) { originalReconfigure(self, cmd); return; }
    [buttons addObject:self];
    // Restore first so disabling an override or choosing another native speed
    // cannot preserve a prior shortened field if iOS skips an unchanged field.
    SPRestoreTimings(self);
    originalReconfigure(self, cmd);
    SPApplyTimings(self);
}

void SPReloadClickSpeedRuntime(void) {
    if (!NSThread.isMainThread || !originalReconfigure) return;
    for (id button in buttons.allObjects) {
        if (SPBool(button, @"isButtonDown", YES)) continue;
        SPReconfigure(button, sel_registerName("_reconfigureButtonGestureRecognizers"));
    }
}

void SPInstallClickSpeedRuntime(void) {
    buttons = [NSHashTable weakObjectsHashTable];
    originalTimings = [NSMapTable weakToStrongObjectsMapTable];
    Class cls = NSClassFromString(@"SBLockHardwareButton");
    if (!SPMatches(cls, "_reconfigureButtonGestureRecognizers", "v", NULL)) {
        SPWrite(@"LastClickSpeedConfiguration", @"Inactive: iOS does not expose the expected side-button recognizer configuration method.");
        return;
    }
    MSHookMessageEx(cls, sel_registerName("_reconfigureButtonGestureRecognizers"), (IMP)SPReconfigure, (IMP *)&originalReconfigure);
}

void SPRecordButtonDown(void) {
    if (!NSThread.isMainThread) return;
    pressDownTime = NSProcessInfo.processInfo.systemUptime; pressUpTime = 0;
}
void SPRecordButtonUp(void) {
    if (NSThread.isMainThread && pressDownTime > 0) pressUpTime = NSProcessInfo.processInfo.systemUptime;
}
void SPCancelButtonTiming(void) {
    if (NSThread.isMainThread) { pressDownTime = 0; pressUpTime = 0; }
}
void SPRecordSleepRequest(void) {
    if (!NSThread.isMainThread || pressDownTime <= 0) return;
    double now = NSProcessInfo.processInfo.systemUptime;
    if (now - pressDownTime > 5) return;
    NSString *released = pressUpTime >= pressDownTime ?
        [NSString stringWithFormat:@"Release to sleep request: %.0f ms", (now - pressUpTime) * 1000] : @"Release timestamp unavailable";
    NSString *report = [NSString stringWithFormat:@"Measured at %@\nButton down to sleep request: %.0f ms\n%@\n%@",
        NSDate.date, (now - pressDownTime) * 1000, released, recognizerDiagnostic ?: @"Recognizer configuration not observed yet."];
    pressDownTime = 0; pressUpTime = 0;
    // Save after the native sleep request, so preference I/O adds no wait to it.
    dispatch_async(dispatch_get_main_queue(), ^{ SPWrite(@"LastTimingDiagnostic", report); });
}
