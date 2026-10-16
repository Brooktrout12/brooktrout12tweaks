#import "Preferences.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#include <stdlib.h>

static dispatch_queue_t CQAReadQueue;
static CQAPreferenceCallback CQACallback;
static char CQAObserver;

static void CQADeliverPreference(void *context) {
    @autoreleasepool {
        BOOL enabled = *(BOOL *)context;
        free(context);
        if (CQACallback) CQACallback(enabled);
    }
}

static void CQAReloadPreference(void *context) {
    (void)context;
    @autoreleasepool {
        CFPreferencesSynchronize(CQA_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPropertyListRef value = CFPreferencesCopyValue(CFSTR("Enabled"), CQA_DOMAIN,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        BOOL enabled = YES; // Matches the native Settings switch's default.
        if (value) {
            if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
                enabled = CFBooleanGetValue((CFBooleanRef)value);
            } else if (CFGetTypeID(value) == CFNumberGetTypeID()) {
                double number;
                if (CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &number) &&
                    (number == 0 || number == 1)) enabled = number == 1;
            }
            CFRelease(value);
        }
        BOOL *snapshot = malloc(sizeof(*snapshot));
        if (!snapshot) return;
        *snapshot = enabled;
        dispatch_async_f(dispatch_get_main_queue(), snapshot, CQADeliverPreference);
    }
}

static void CQAPreferenceChanged(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object, CFDictionaryRef info) {
    (void)center; (void)observer; (void)name; (void)object; (void)info;
    if (CQAReadQueue) dispatch_async_f(CQAReadQueue, NULL, CQAReloadPreference);
}

void CQAObservePreference(CQAPreferenceCallback callback) {
    if (CQAReadQueue || !callback) return;
    CQACallback = callback;
    CQAReadQueue = dispatch_queue_create("com.brooktrout12.cleanquickactions.preferences", DISPATCH_QUEUE_SERIAL);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), &CQAObserver,
        CQAPreferenceChanged, CQA_NOTIFY, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    dispatch_async_f(CQAReadQueue, NULL, CQAReloadPreference);
    // Settings performs all writes. No preference I/O on SpringBoard's main
    // thread, polling, helper process or compiler-generated Objective-C blocks.
}
