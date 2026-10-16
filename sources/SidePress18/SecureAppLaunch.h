#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, SPSecureAppLaunchState) {
    SPSecureAppLaunchCancelled,
    SPSecureAppLaunchSubmitted,
    SPSecureAppLaunchVisible,
    SPSecureAppLaunchFailed,
};

// Main-thread APIs. Submit the selected application's verified secure-display
// scene directly to CoverSheet's launcher; Camera has its own separate route.
NSUInteger SPStartSecureAppLaunch(id launcher, NSString *bundleIdentifier, NSString **error);
void SPRecordSecureAppHostResult(NSUInteger token, BOOL visible, NSString *detail);
void SPCancelSecureAppLaunch(void);
SPSecureAppLaunchState SPGetSecureAppLaunchState(NSUInteger token);
