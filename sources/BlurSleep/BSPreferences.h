#pragma once
#import <Foundation/Foundation.h>
#include "BSAnimationState.h"
#include "BSAnimationStyle.h"

#define BS_DOMAIN CFSTR("com.brooktrout12.blursleep")
#define BS_CHANGED CFSTR("com.brooktrout12.blursleep/preferences-changed")
#define BS_PREVIEW CFSTR("com.brooktrout12.blursleep/preview")
#define BS_STATUS_PATH @"/var/mobile/Library/Logs/BlurSleep-status.plist"
#define BS_LOG_PATH @"/var/mobile/Library/Logs/BlurSleep.log"
#define BS_VERSION @"1.2.0"

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

static inline BSAnimationStyle BSReadStyle(void) {
    id value = BSRead(@"AnimationStyle");
    return BSNormalizeStyle([value isKindOfClass:NSNumber.class] ? [value longLongValue] : 0);
}

static inline NSArray<NSString *> *BSStyleTitles(void) {
    return @[@"Gaussian Blur", @"CRT TV", @"Iris Close", @"Shrink to Center", @"Slide Down", @"Card Flip", @"Liquid Glass"];
}

static inline NSString *BSStyleTitle(BSAnimationStyle style) {
    return BSStyleTitles()[BSNormalizeStyle(style)];
}

static inline NSString *BSStyleDescription(BSAnimationStyle style) {
    switch (BSNormalizeStyle(style)) {
        case BSStyleCRTTelevision: return @"The top and bottom squeeze into a glowing center line, which shrinks to a point and disappears.";
        case BSStyleIrisClose: return @"A circular opening closes inward from the edges to the center.";
        case BSStyleShrink: return @"The screen shrinks into the center, with softly rounded corners, and fades away.";
        case BSStyleSlideDown: return @"The picture slides off the bottom of the screen, revealing black behind it.";
        case BSStyleCardFlip: return @"The screen turns sideways like a card, fading to black as it becomes edge-on.";
        case BSStyleLiquidGlass: return @"An iOS 26-inspired glass lens bends the screen around its curved edges, catches a moving highlight, and flows into a droplet before fading to black.";
        default: return @"The screen gradually blurs and fades to black.";
    }
}

static inline void BSWrite(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, BS_DOMAIN);
    CFPreferencesAppSynchronize(BS_DOMAIN);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), BS_CHANGED, NULL, NULL, true);
}
