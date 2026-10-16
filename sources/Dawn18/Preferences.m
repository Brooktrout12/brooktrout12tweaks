#import "Preferences.h"
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>

static NSArray<NSString *> *D18Keys;

static void D18InitializeKeys(void *context) {
    (void)context;
    D18Keys = @[@"Applications", @"Folders", @"Notifications", @"NotificationButtons",
                @"Widgets", @"Dock", @"Banners", @"AppLibrary", @"QuickActions",
                @"RingerVolume"];
}

NSArray<NSString *> *D18PreferenceKeys(void) {
    static dispatch_once_t once;
    dispatch_once_f(&once, NULL, D18InitializeKeys);
    return D18Keys;
}

D18Configuration D18ReadConfiguration(void) {
    D18Configuration result = {{0}};
    CFPreferencesSynchronize(D18_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *values = CFBridgingRelease(CFPreferencesCopyMultiple(
        (__bridge CFArrayRef)D18PreferenceKeys(), D18_DOMAIN,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    // Some application sandboxes cannot query another preferences domain.
    // A fixed local path is a fallback; no container or File Provider discovery.
    if (!values.count) {
        values = [NSDictionary dictionaryWithContentsOfFile:
                  @"/var/mobile/Library/Preferences/com.brooktrout12.dawn18.plist"];
    }
    for (NSUInteger i = 0; i < D18ElementCount; i++) {
        id value = values[D18PreferenceKeys()[i]];
        if ([value isKindOfClass:NSNumber.class] &&
            CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) {
            result.values[i] = D18ValidatedPreference((D18Element)i, [value doubleValue]);
        }
    }
    return result;
}

BOOL D18WriteConfiguration(D18Configuration configuration) {
    NSMutableDictionary *values = [NSMutableDictionary dictionaryWithCapacity:D18ElementCount];
    for (NSUInteger i = 0; i < D18ElementCount; i++)
        values[D18PreferenceKeys()[i]] = @(D18ValidatedPreference((D18Element)i, configuration.values[i]));
    CFPreferencesSetMultiple((__bridge CFDictionaryRef)values, NULL, D18_DOMAIN,
                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL saved = CFPreferencesSynchronize(D18_DOMAIN, kCFPreferencesCurrentUser,
                                          kCFPreferencesAnyHost);
    if (saved) notify_post(D18_NOTIFY);
    return saved;
}

static dispatch_queue_t D18ReadQueue;
static D18ConfigurationCallback D18Callback;
static void *D18CallbackContext;
static char D18NotificationObserver;

static void D18DeliverConfiguration(void *rawSnapshot) {
    @autoreleasepool {
        D18Configuration configuration = *(D18Configuration *)rawSnapshot;
        free(rawSnapshot);
        if (D18Callback) D18Callback(configuration, D18CallbackContext);
    }
}

static void D18ReloadConfiguration(void *context) {
    (void)context;
    @autoreleasepool {
        D18Configuration configuration = D18ReadConfiguration();
        D18Configuration *snapshot = malloc(sizeof(*snapshot));
        if (!snapshot) return;
        *snapshot = configuration;
        dispatch_async_f(dispatch_get_main_queue(), snapshot, D18DeliverConfiguration);
    }
}

static void D18PreferencesChanged(CFNotificationCenterRef center, void *observer,
                                  CFStringRef name, const void *object, CFDictionaryRef info) {
    (void)center; (void)observer; (void)name; (void)object; (void)info;
    if (D18ReadQueue) dispatch_async_f(D18ReadQueue, NULL, D18ReloadConfiguration);
}

void D18ObserveConfiguration(D18ConfigurationCallback callback, void *context) {
    // Called once on the main thread. Use C function callbacks throughout:
    // no global/stack block ISA metadata from the old arm64e compiler.
    if (D18ReadQueue || !callback) return;
    D18Callback = callback;
    D18CallbackContext = context;
    D18ReadQueue = dispatch_queue_create("com.brooktrout12.dawn18.preferences", DISPATCH_QUEUE_SERIAL);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        &D18NotificationObserver, D18PreferencesChanged, CFSTR(D18_NOTIFY), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
    dispatch_async_f(D18ReadQueue, NULL, D18ReloadConfiguration);
    // All reads remain serial and off the main thread. Registration lasts for
    // the process lifetime; no timer, logging, helper daemon, or network access.
}
