#pragma once
#import <Foundation/Foundation.h>

#define SP_DOMAIN CFSTR("com.brooktrout12.sidepress18")
#define SP_CHANGED CFSTR("com.brooktrout12.sidepress18/preferences-changed")
#define SP_DEFAULT_ACTION @"native"

static inline id SPRead(NSString *key, id fallback) {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, SP_DOMAIN));
    return value ?: fallback;
}
static inline void SPWrite(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, SP_DOMAIN);
    CFPreferencesAppSynchronize(SP_DOMAIN);
}
static inline NSArray<NSString *> *SPActionIDs(void) {
    return @[@"native", @"camera", @"flashlight", @"app", @"playpause", @"next", @"previous"];
}
static inline NSArray<NSString *> *SPActionNames(void) {
    return @[@"iOS Default", @"Camera", @"Flashlight", @"Open App", @"Play / Pause", @"Next Track", @"Previous Track"];
}
static inline NSString *SPSelectedAction(void) {
    id action = SPRead(@"Action", SP_DEFAULT_ACTION);
    return [action isKindOfClass:NSString.class] && [SPActionIDs() containsObject:action] ? action : SP_DEFAULT_ACTION;
}
static inline NSString *SPActionName(NSString *action) {
    NSUInteger index = [SPActionIDs() indexOfObject:action];
    return index == NSNotFound ? @"iOS Default" : SPActionNames()[index];
}
