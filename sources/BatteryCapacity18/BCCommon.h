#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString *const BCPrefsDomain = @"com.brooktrout12.batterycapacity18";
static const char *const BCChangedNotification = "com.brooktrout12.batterycapacity18/preferences.changed";
static NSString *const BCReadingChangedNotification = @"com.brooktrout12.batterycapacity18/reading.changed";

static inline BOOL BCPreference(NSString *key, BOOL defaultValue) {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
        (__bridge CFStringRef)BCPrefsDomain));
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : defaultValue;
}

static inline NSString *BCLocal(NSString *english, NSString *german) {
    NSString *language = NSLocale.preferredLanguages.firstObject ?: @"en";
    return [language hasPrefix:@"de"] ? german : english;
}
