#import "SecureAppLaunch.h"
#import "Runtime.h"
#import "Shared.h"
#import <Block.h>
#include <stdlib.h>
#include <string.h>

@protocol SPSecureSceneCreating <NSObject>
- (instancetype)initWithApplicationForMainSecureDisplay:(id)application;
@end

// The completion is a notification only. Visibility is independently checked
// by Actions.m; no success/error argument is assumed or used.
typedef void (^SPSecurePresentationCompletion)(void);
@protocol SPSecureScenePresenting <NSObject>
- (void)_reallyActivateAppSceneWithEntity:(id)entity interactive:(BOOL)interactive
                         withCompletion:(SPSecurePresentationCompletion)completion;
@end

static NSUInteger currentToken;
static SPSecureAppLaunchState launchState = SPSecureAppLaunchCancelled;
static id pendingEntity;
static __weak id pendingLauncher;
static Class launcherClass;
static NSMutableDictionary<NSString *, NSString *> *launchDiagnostic;

static void SPPersistLaunchDiagnostic(void) {
    if (!launchDiagnostic) return;
    NSMutableString *report = [NSMutableString string];
    for (NSString *key in [launchDiagnostic.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [report appendFormat:@"%@: %@\n", key, launchDiagnostic[key]];
    SPWrite(@"LastSecureLaunchDiagnostic", report);
}
static void SPDiagnosticStage(NSString *stage) { launchDiagnostic[@"Stage"] = stage; }
static NSString *SPDiagnosticClass(id object) {
    return object ? NSStringFromClass(object_getClass(object)) : @"(nil)";
}
static void SPDiagnosticMethod(NSString *key, Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    const char *types = method ? method_getTypeEncoding(method) : NULL;
    launchDiagnostic[key] = [NSString stringWithFormat:@"%@ %@: %@ (arguments: %u)",
        cls ? NSStringFromClass(cls) : @"(class missing)", NSStringFromSelector(selector),
        types ? [NSString stringWithUTF8String:types] : @"(method missing)",
        method ? method_getNumberOfArguments(method) : 0];
}
static BOOL SPTypeIs(Method method, unsigned int index, const char *expected) {
    char *type = method_copyArgumentType(method, index);
    BOOL matches = type && strcmp(type, expected) == 0;
    free(type); return matches;
}
static BOOL SPReturns(Method method, const char *expected) {
    char *type = method_copyReturnType(method);
    BOOL matches = type && strcmp(type, expected) == 0;
    free(type); return matches;
}
static BOOL SPObjectGetter(id receiver, SEL selector) {
    Method method = class_getInstanceMethod(object_getClass(receiver), selector);
    return method && method_getNumberOfArguments(method) == 2 && SPReturns(method, "@");
}
static BOOL SPObjectArgument(id receiver, SEL selector) {
    Method method = class_getInstanceMethod(object_getClass(receiver), selector);
    return method && method_getNumberOfArguments(method) == 3 &&
           SPReturns(method, "@") && SPTypeIs(method, 2, "@");
}
static void SPRecordLauncherInterfaces(void) {
    NSMutableArray *lines = [NSMutableArray array];
    for (Class c = launcherClass; c && c != NSObject.class; c = class_getSuperclass(c)) {
        unsigned count = 0; Method *methods = class_copyMethodList(c, &count);
        for (unsigned i = 0; i < count; ++i) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            NSString *lower = name.lowercaseString;
            if (![lower containsString:@"activat"] && ![lower containsString:@"present"] &&
                ![lower containsString:@"scene"] && ![lower containsString:@"camera"]) continue;
            [lines addObject:[NSString stringWithFormat:@"%@ %@ — %s", NSStringFromClass(c),
                name, method_getTypeEncoding(methods[i]) ?: "?"]];
        }
        free(methods);
    }
    launchDiagnostic[@"Available launcher interfaces"] = [[lines sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"\n"];
}
static NSUInteger SPLaunchError(NSString **error, NSString *message) {
    launchState = SPSecureAppLaunchFailed;
    pendingEntity = nil; pendingLauncher = nil;
    launchDiagnostic[@"Error"] = message;
    SPRecordLauncherInterfaces(); SPPersistLaunchDiagnostic();
    NSString *stage = launchDiagnostic[@"Stage"];
    if (error) *error = stage.length ? [NSString stringWithFormat:@"[%@] %@", stage, message] : message;
    return 0;
}

NSUInteger SPStartSecureAppLaunch(id launcher, NSString *bundleIdentifier, NSString **error) {
    if (error) *error = nil;
    if (!NSThread.isMainThread) {
        if (error) *error = @"Secure app presentation must start on the main thread.";
        return 0;
    }
    SPCancelSecureAppLaunch();
    launcherClass = object_getClass(launcher);
    launchDiagnostic = [@{
        @"Build": @"SidePress18 1.0 — direct secure-scene submission",
        @"System": NSProcessInfo.processInfo.operatingSystemVersionString,
        @"Attempt": NSDate.date.description,
        @"Selected bundle": [bundleIdentifier isKindOfClass:NSString.class] ? bundleIdentifier : @"(invalid)",
        @"Cover launcher class": SPDiagnosticClass(launcher),
    } mutableCopy];
    SPDiagnosticStage(@"native-launcher-interface");
    SEL activate = NSSelectorFromString(@"_reallyActivateAppSceneWithEntity:interactive:withCompletion:");
    SPDiagnosticMethod(@"Direct launcher method", launcherClass, activate);
    Method method = class_getInstanceMethod(launcherClass, activate);
    if (!launcher || !method || method_getNumberOfArguments(method) != 5 ||
        !SPReturns(method, "v") || !SPTypeIs(method, 2, "@") ||
        !(SPTypeIs(method, 3, "B") || SPTypeIs(method, 3, "c")) || !SPTypeIs(method, 4, "@?"))
        return SPLaunchError(error, @"The native secure-scene presentation interface is unavailable.");
    SPDiagnosticStage(@"selected-application");
    if (![bundleIdentifier isKindOfClass:NSString.class] || bundleIdentifier.length == 0 ||
        [bundleIdentifier isEqualToString:@"com.apple.camera"])
        return SPLaunchError(error, @"No separate application was selected for secure presentation.");
    id entity;
    @try {
        SPDiagnosticStage(@"application-registry");
        id controller = SPShared(@"SBApplicationController");
        SEL lookup = NSSelectorFromString(@"applicationWithBundleIdentifier:");
        launchDiagnostic[@"Application registry class"] = SPDiagnosticClass(controller);
        SPDiagnosticMethod(@"Application lookup method", object_getClass(controller), lookup);
        if (!SPObjectArgument(controller, lookup))
            return SPLaunchError(error, @"The SpringBoard application registry is unavailable.");
        SPDiagnosticStage(@"application-lookup");
        id application = ((id (*)(id, SEL, id))objc_msgSend)(controller, lookup, bundleIdentifier);
        launchDiagnostic[@"Selected application class"] = SPDiagnosticClass(application);
        if (!application)
            return SPLaunchError(error, @"The selected application is no longer installed.");

        Class entityClass = NSClassFromString(@"SBDeviceApplicationSceneEntity");
        SEL initializer = NSSelectorFromString(@"initWithApplicationForMainSecureDisplay:");
        Method initMethod = class_getInstanceMethod(entityClass, initializer);
        SPDiagnosticMethod(@"Secure scene initializer", entityClass, initializer);
        SPDiagnosticStage(@"secure-scene-initializer");
        if (!initMethod || method_getNumberOfArguments(initMethod) != 3 ||
            !SPReturns(initMethod, "@") || !SPTypeIs(initMethod, 2, "@"))
            return SPLaunchError(error, @"This iOS build cannot prepare a native secure-display application scene.");
        SPDiagnosticStage(@"secure-scene-creation");
        entity = [(id<SPSecureSceneCreating>)[entityClass alloc]
                  initWithApplicationForMainSecureDisplay:application];
        launchDiagnostic[@"Selected scene class"] = SPDiagnosticClass(entity);
        SPDiagnosticMethod(@"Scene handle getter", object_getClass(entity), NSSelectorFromString(@"sceneHandle"));
        SPDiagnosticMethod(@"Scene application getter", object_getClass(entity), NSSelectorFromString(@"application"));
        SPDiagnosticStage(@"secure-scene-accessors");
        if (!entity || !SPObjectGetter(entity, NSSelectorFromString(@"sceneHandle")) ||
            !SPObjectGetter(entity, NSSelectorFromString(@"application")))
            return SPLaunchError(error, @"iOS did not create a secure application scene.");
        id handle = SPGet(entity, @"sceneHandle");
        SEL secure = NSSelectorFromString(@"isSecure");
        Method secureMethod = class_getInstanceMethod(object_getClass(handle), secure);
        launchDiagnostic[@"Scene handle class"] = SPDiagnosticClass(handle);
        SPDiagnosticMethod(@"Scene secure getter", object_getClass(handle), secure);
        SPDiagnosticStage(@"secure-handle-interface");
        if (!secureMethod || method_getNumberOfArguments(secureMethod) != 2 ||
            !(SPReturns(secureMethod, "B") || SPReturns(secureMethod, "c")))
            return SPLaunchError(error, @"iOS did not assign the selected application to the secure display.");
        SPDiagnosticStage(@"secure-handle-state");
        BOOL secureState = SPBool(handle, @"isSecure", NO);
        launchDiagnostic[@"Scene isSecure"] = secureState ? @"YES" : @"NO";
        if (!secureState)
            return SPLaunchError(error, @"iOS did not assign the selected application to the secure display.");
        SPDiagnosticStage(@"scene-application-identity");
        id actualApplication = SPGet(entity, @"application");
        launchDiagnostic[@"Scene application class"] = SPDiagnosticClass(actualApplication);
        SPDiagnosticMethod(@"Scene bundle getter", object_getClass(actualApplication), NSSelectorFromString(@"bundleIdentifier"));
        if (!SPObjectGetter(actualApplication, NSSelectorFromString(@"bundleIdentifier")) ||
            ![SPGet(actualApplication, @"bundleIdentifier") isEqual:bundleIdentifier])
            return SPLaunchError(error, @"The secure scene does not belong to the selected application.");
    } @catch (NSException *exception) {
        // This is still preflight: the native animation has not started and no
        // system transition needs to be unwound. Do not retry failed activation.
        return SPLaunchError(error, [NSString stringWithFormat:@"iOS rejected secure scene preparation: %@",
                                 exception.reason ?: exception.name]);
    }

    if (++currentToken == 0) ++currentToken;
    const NSUInteger token = currentToken;
    pendingEntity = entity; pendingLauncher = launcher;
    launchState = SPSecureAppLaunchSubmitted;
    SPDiagnosticStage(@"direct-scene-submission");
    SPPersistLaunchDiagnostic();

    // Heap-copy with the C runtime before passing through Objective-C. This
    // avoids the legacy arm64e stack-block ISA failure seen in earlier builds.
    SPSecurePresentationCompletion completion = (__bridge_transfer SPSecurePresentationCompletion)
        _Block_copy((__bridge const void *)^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (currentToken != token || launchState != SPSecureAppLaunchSubmitted) return;
                launchDiagnostic[@"Native completion received"] = @"YES";
                SPDiagnosticStage(@"native-completion-awaiting-host");
                SPPersistLaunchDiagnostic();
            });
        });
    if (!completion) return SPLaunchError(error, @"Unable to prepare the native presentation callback.");
    @try {
        // Call the exact interface confirmed present by the device diagnostic.
        // The argument is the verified selected-app secure entity, never a
        // Camera scene. Do not start a Camera transition or wait for a hook.
        [(id<SPSecureScenePresenting>)launcher _reallyActivateAppSceneWithEntity:entity
            interactive:NO withCompletion:completion];
    } @catch (NSException *exception) {
        SPDiagnosticStage(@"native-submission-exception");
        return SPLaunchError(error, [NSString stringWithFormat:@"iOS rejected secure app presentation: %@",
                                    exception.reason ?: exception.name]);
    }
    return token;
}

void SPRecordSecureAppHostResult(NSUInteger token, BOOL visible, NSString *detail) {
    if (!NSThread.isMainThread || !token || token != currentToken ||
        launchState != SPSecureAppLaunchSubmitted) return;
    launchDiagnostic[@"Observed host result"] = detail ?: @"(no detail)";
    launchState = visible ? SPSecureAppLaunchVisible : SPSecureAppLaunchFailed;
    SPDiagnosticStage(visible ? @"selected-secure-host-visible" : @"selected-secure-host-not-visible");
    if (!visible) SPRecordLauncherInterfaces();
    SPPersistLaunchDiagnostic();
    pendingEntity = nil; pendingLauncher = nil;
}
void SPCancelSecureAppLaunch(void) {
    if (!NSThread.isMainThread) return;
    if (launchState == SPSecureAppLaunchSubmitted) {
        SPDiagnosticStage(@"submitted-request-cancelled");
        SPPersistLaunchDiagnostic();
    }
    launchState = SPSecureAppLaunchCancelled;
    pendingEntity = nil; pendingLauncher = nil;
}
SPSecureAppLaunchState SPGetSecureAppLaunchState(NSUInteger token) {
    return token && token == currentToken ? launchState : SPSecureAppLaunchCancelled;
}
