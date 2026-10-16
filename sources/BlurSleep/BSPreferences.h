#pragma once
#import <Foundation/Foundation.h>
#include "BSAnimationState.h"

#define BS_DOMAIN CFSTR("com.brooktrout12.blursleep")
#define BS_CHANGED CFSTR("com.brooktrout12.blursleep/preferences-changed")
#define BS_PREVIEW CFSTR("com.brooktrout12.blursleep/preview")
#define BS_STATUS_PATH @"/var/mobile/Library/Logs/BlurSleep-status.plist"
#define BS_LOG_PATH @"/var/mobile/Library/Logs/BlurSleep.log"
#define BS_VERSION @"1.0.2"

static inline id BSRead(NSString *key) {
    CFPreferencesAppSynchronize(BS_DOMAIN);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, BS_DOMAIN));
}

static inline BOOL BSReadEnabled(void) {
    id value = BSRead(@"Enabled");
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : YES;
}

static inline double BSReadDuration(void) {
    id value = BSRead(@"Duration");
    return BSClampDuration([value isKindOfClass:NSNumber.class] ? [value doubleValue] : BS_DEFAULT_DURATION);
}

static inline void BSWrite(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, BS_DOMAIN);
    CFPreferencesAppSynchronize(BS_DOMAIN);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), BS_CHANGED, NULL, NULL, true);
}
