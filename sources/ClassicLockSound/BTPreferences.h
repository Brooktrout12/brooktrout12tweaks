#pragma once
#import <Foundation/Foundation.h>
#include "BTVolume.h"

#define BTPreferenceDomain CFSTR("com.brooktrout12.classiclocksound")
#define BTVolumeChanged CFSTR("com.brooktrout12.classiclocksound/volume-changed")

static inline int BTReadVolume(void) {
    CFPreferencesAppSynchronize(BTPreferenceDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("VolumePercent"), BTPreferenceDomain);
    double number = 100;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &number);
    if (value) CFRelease(value);
    return BTVolumePercent(number);
}

static inline void BTWriteVolume(int percent) {
    int clamped = BTVolumePercent(percent);
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &clamped);
    CFPreferencesSetAppValue(CFSTR("VolumePercent"), number, BTPreferenceDomain);
    CFRelease(number);
    CFPreferencesAppSynchronize(BTPreferenceDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        BTVolumeChanged, NULL, NULL, true);
}
