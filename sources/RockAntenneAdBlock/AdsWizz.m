#import "AdsWizz.h"
#import "Diagnostics.h"
#import "SkipGate.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>

// Public AdsWizz 7.x Objective-C protocols, checked against the loaded SDK.
// No SDK binary or private Swift ABI is linked into this tweak.
static NSObject *RABSDKLock;
static NSMutableSet<NSString *> *RABSDKHooks;
static NSUInteger RABSDKManagerHooks, RABSDKBreakHooks, RABSDKNextID;
static const char RABManagerStateKey;
static BOOL RABSDKReady;

@interface RABAdState : NSObject {
@public
    RABSkipGate gate;
}
@property(nonatomic) NSUInteger number;
@property(nonatomic, strong) NSHashTable *seenAds;
@end
@implementation RABAdState
@end

static RABAdState *RABState(id manager) {
    @synchronized (RABSDKLock) {
        RABAdState *state = objc_getAssociatedObject(manager, &RABManagerStateKey);
        if (!state) {
            state = [RABAdState new];
            state.number = ++RABSDKNextID;
            state.seenAds = [NSHashTable hashTableWithOptions:
                NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
            objc_setAssociatedObject(manager, &RABManagerStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return state;
    }
}

static BOOL RABSignature(Method method, char result, const char *arguments) {
    if (!method) return NO;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (sig.numberOfArguments != strlen(arguments) + 2 || sig.methodReturnType[0] != result) return NO;
    for (NSUInteger i = 0; i < strlen(arguments); ++i)
        if ([sig getArgumentTypeAtIndex:i + 2][0] != arguments[i]) return NO;
    return YES;
}
static BOOL RABCanSend(id object, SEL selector, char result, const char *arguments) {
    return object && RABSignature(class_getInstanceMethod(object_getClass(object), selector), result, arguments);
}
static BOOL RABIsAdManager(id manager) {
    Protocol *protocol = NSProtocolFromString(@"AASDKAdManager");
    return protocol && manager && class_conformsToProtocol(object_getClass(manager), protocol) &&
        RABCanSend(manager, NSSelectorFromString(@"skipAd"), 'v', "");
}
static id RABObjectProperty(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!RABCanSend(object, selector, '@', "")) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL RABScheduleSkip(id manager, NSString *source) {
    if (!RABIsAdManager(manager)) {
        RABLog(@"AD skip unavailable: manager protocol or skipAd signature mismatch");
        return NO;
    }
    RABAdState *state = RABState(manager);
    uint64_t ticket = 0;
    RABSkipDecision decision;
    @synchronized (state) { decision = RABSkipRequest(&state->gate, &ticket); }
    if (decision == RABSkipAlreadyPending) return YES;
    if (decision == RABSkipRejected) {
        RABLog([NSString stringWithFormat:@"AD manager=%lu skip not queued (closed or bounded limit)", (unsigned long)state.number]);
        return NO;
    }
    RABLog([NSString stringWithFormat:@"AD manager=%lu SKIP_REQUEST source=%@", (unsigned long)state.number, source]);
    __weak id weakManager = manager;
    // Avoid re-entering an SDK transition from inside its delegate callback.
    dispatch_async(dispatch_get_main_queue(), ^{
        id current = weakManager;
        if (!current) return;
        BOOL take;
        @synchronized (state) { take = RABSkipTake(&state->gate, ticket); }
        if (!take) return;
        RABLog([NSString stringWithFormat:@"AD manager=%lu SKIP_CALL attempt=%u", (unsigned long)state.number, state->gate.attempts]);
        RABDiagnosticCounter(@"sdkSkipCalls");
        @try { ((void (*)(id, SEL))objc_msgSend)(current, NSSelectorFromString(@"skipAd")); }
        @catch (__unused NSException *exception) {
            @synchronized (state) { RABSkipClose(&state->gate); }
            RABLog(@"AD skipAd raised an Objective-C exception; no automatic retry");
        }
    });
    return YES;
}

// Hook the declaring class once. A separate block captures each original IMP;
// inherited methods and super calls therefore cannot recurse into themselves.
static Method RABOwnMethod(Class cls, SEL selector) {
    unsigned int count = 0;
    Method found = NULL, *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; ++i)
        if (method_getName(methods[i]) == selector) { found = methods[i]; break; }
    free(methods);
    return found;
}
typedef IMP (^RABImplementationFactory)(IMP original, SEL selector);
static BOOL RABInstall(Class cls, NSString *name, char result, const char *arguments, RABImplementationFactory factory) {
    SEL selector = NSSelectorFromString(name);
    while (cls && !RABOwnMethod(cls, selector)) cls = class_getSuperclass(cls);
    if (!cls) return NO;
    NSString *key = [NSString stringWithFormat:@"%@/%@", NSStringFromClass(cls), name];
    @synchronized (RABSDKLock) {
        if ([RABSDKHooks containsObject:key]) return NO;
        Method method = RABOwnMethod(cls, selector);
        if (!RABSignature(method, result, arguments)) return NO;
        IMP original = method_getImplementation(method);
        IMP replacement = factory(original, selector);
        if (!replacement) return NO;
        class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
        [RABSDKHooks addObject:key];
        RABLog([@"SDK HOOK " stringByAppendingString:key]);
        return YES;
    }
}

static void RABHookDelegate(Class cls);
static void RABHookManager(Class cls) {
    Protocol *protocol = NSProtocolFromString(@"AASDKAdManager");
    if (!protocol || !class_conformsToProtocol(cls, protocol) ||
        !RABSignature(class_getInstanceMethod(cls, NSSelectorFromString(@"skipAd")), 'v', "")) return;
    BOOL installedPlay = RABInstall(cls, @"play", 'v', "", ^IMP(IMP original, SEL selector) {
        return imp_implementationWithBlock(^(id manager) {
            if (!RABScheduleSkip(manager, @"AdManager.play")) ((void (*)(id, SEL))original)(manager, selector);
        });
    });
    if (installedPlay) @synchronized (RABSDKLock) { ++RABSDKManagerHooks; }
    RABInstall(cls, @"prepare", 'v', "", ^IMP(IMP original, SEL selector) {
        return imp_implementationWithBlock(^(id manager) {
            RABAdState *state = RABState(manager);
            @synchronized (state) {
                if (state->gate.closed) { RABSkipReopen(&state->gate); [state.seenAds removeAllObjects]; }
            }
            ((void (*)(id, SEL))original)(manager, selector);
            id ads = RABObjectProperty(manager, @"ads");
            if ([ads isKindOfClass:[NSArray class]] && [ads count]) RABScheduleSkip(manager, @"AdManager.prepare");
        });
    });
    RABInstall(cls, @"setDelegate:", 'v', "@", ^IMP(IMP original, SEL selector) {
        return imp_implementationWithBlock(^(id manager, id delegate) {
            if (delegate) RABHookDelegate(object_getClass(delegate));
            ((void (*)(id, SEL, id))original)(manager, selector, delegate);
        });
    });
}

static void RABHookDelegate(Class cls) {
    BOOL installedBreak = RABInstall(cls, @"adStreamManager:adBreakStarted:", 'v', "@@", ^IMP(IMP original, SEL selector) {
        return imp_implementationWithBlock(^(id delegate, id streamManager, id manager) {
            BOOL valid = RABIsAdManager(manager);
            if (valid) {
                RABHookManager(object_getClass(manager));
                RABAdState *state = RABState(manager);
                @synchronized (state) { RABSkipReopen(&state->gate); }
                RABDiagnosticCounter(@"sdkAdBreakStarts");
                RABLog([NSString stringWithFormat:@"AD manager=%lu BREAK_STARTED class=%@", (unsigned long)state.number, NSStringFromClass(object_getClass(manager))]);
            }
            ((void (*)(id, SEL, id, id))original)(delegate, selector, streamManager, manager);
            if (valid) RABScheduleSkip(manager, @"AdStreamManager.adBreakStarted");
        });
    });
    if (installedBreak) @synchronized (RABSDKLock) { ++RABSDKBreakHooks; }
    RABInstall(cls, @"adStreamManager:adBreakEnded:", 'v', "@@", ^IMP(IMP original, SEL selector) {
        return imp_implementationWithBlock(^(id delegate, id streamManager, id manager) {
            if (RABIsAdManager(manager)) {
                RABAdState *state = RABState(manager);
                @synchronized (state) { RABSkipClose(&state->gate); }
                RABDiagnosticCounter(@"sdkAdBreakEnds");
                RABLog([NSString stringWithFormat:@"AD manager=%lu BREAK_ENDED (SDK callback, not listening confirmation)", (unsigned long)state.number]);
            }
            ((void (*)(id, SEL, id, id))original)(delegate, selector, streamManager, manager);
        });
    });
    RABInstall(cls, @"adStreamManagerWillReconnect:", 'v', "@", ^IMP(IMP original, SEL selector) {
        return imp_implementationWithBlock(^(id delegate, id manager) {
            RABDiagnosticCounter(@"sdkReconnects");
            RABLog(@"STREAM SDK_WILL_RECONNECT");
            ((void (*)(id, SEL, id))original)(delegate, selector, manager);
        });
    });
    RABInstall(cls, @"adStreamManager:willStartPlaying:", 'v', "@@", ^IMP(IMP original, SEL selector) {
        return imp_implementationWithBlock(^(id delegate, id manager, id url) {
            if ([url isKindOfClass:[NSURL class]]) RABMediaEvent(url, @"SDK willStartPlaying");
            ((void (*)(id, SEL, id, id))original)(delegate, selector, manager, url);
        });
    });
    RABInstall(cls, @"adStreamManager:stateChanged:", 'v', "@q", ^IMP(IMP original, SEL selector) {
        return imp_implementationWithBlock(^(id delegate, id manager, NSInteger state) {
            RABLog([NSString stringWithFormat:@"STREAM SDK_STATE raw=%ld", (long)state]);
            ((void (*)(id, SEL, id, NSInteger))original)(delegate, selector, manager, state);
        });
    });
    RABInstall(cls, @"adManager:didReceiveAdEvent:", 'v', "@@", ^IMP(IMP original, SEL selector) {
        return imp_implementationWithBlock(^(id delegate, id manager, id event) {
            BOOL first = NO;
            if (RABIsAdManager(manager)) {
                RABHookManager(object_getClass(manager));
                RABAdState *state = RABState(manager);
                id ad = RABObjectProperty(event, @"ad");
                NSInteger raw = -1;
                SEL eventSelector = NSSelectorFromString(@"event");
                if (RABCanSend(event, eventSelector, 'q', "")) raw = ((NSInteger (*)(id, SEL))objc_msgSend)(event, eventSelector);
                RABLog([NSString stringWithFormat:@"AD manager=%lu SDK_EVENT raw=%ld hasAd=%d", (unsigned long)state.number, (long)raw, ad != nil]);
                @synchronized (state) {
                    if (ad && state.seenAds.count < 24 && ![state.seenAds containsObject:ad]) {
                        [state.seenAds addObject:ad]; first = YES;
                    }
                }
                // One request per ad object; completion events cannot form an
                // unbounded skip loop. No guessed enum values drive behavior.
            }
            ((void (*)(id, SEL, id, id))original)(delegate, selector, manager, event);
            if (first) RABScheduleSkip(manager, @"AdManager.firstAdEvent");
        });
    });
}

void RABAdsWizzRefresh(void) {
    if (!RABSDKLock) return;
    @synchronized (RABSDKLock) {
        Protocol *managerProtocol = NSProtocolFromString(@"AASDKAdManager");
        Protocol *streamProtocol = NSProtocolFromString(@"AASDKAdStreamManagerDelegate");
        Protocol *delegateProtocol = NSProtocolFromString(@"AASDKAdManagerDelegate");
        if (!managerProtocol) return;
        unsigned int count = 0;
        Class *classes = objc_copyClassList(&count);
        NSString *appPath = [NSBundle mainBundle].bundlePath;
        for (unsigned int i = 0; classes && i < count; ++i) {
            const char *image = class_getImageName(classes[i]);
            NSString *imagePath = image ? [NSString stringWithUTF8String:image] : @"";
            if (![imagePath hasPrefix:appPath] && ![imagePath containsString:[NSString stringWithFormat:@"/%@/", appPath.lastPathComponent]]) continue;
            if (class_conformsToProtocol(classes[i], managerProtocol)) RABHookManager(classes[i]);
            if ((streamProtocol && class_conformsToProtocol(classes[i], streamProtocol)) ||
                (delegateProtocol && class_conformsToProtocol(classes[i], delegateProtocol))) RABHookDelegate(classes[i]);
        }
        free(classes);
        Class stream = NSClassFromString(@"AASDKAdStreamManager");
        RABInstall(stream, @"setDelegate:", 'v', "@", ^IMP(IMP original, SEL selector) {
            return imp_implementationWithBlock(^(id manager, id delegate) {
                if (delegate) RABHookDelegate(object_getClass(delegate));
                ((void (*)(id, SEL, id))original)(manager, selector, delegate);
            });
        });
        BOOL ready = RABSDKManagerHooks > 0 || RABSDKBreakHooks > 0;
        if (ready != RABSDKReady) {
            RABSDKReady = ready;
            RABLog([NSString stringWithFormat:@"SDK skip hooks installed: managers=%lu breakDelegates=%lu. Runtime callbacks still need verification.", (unsigned long)RABSDKManagerHooks, (unsigned long)RABSDKBreakHooks]);
        }
    }
}
BOOL RABAdsWizzHandlesDelivery(void) {
    @synchronized (RABSDKLock) {
        if (!RABSDKReady) RABAdsWizzRefresh();
        return RABSDKReady;
    }
}
void RABAdsWizzInstall(void) {
    RABSDKLock = [NSObject new];
    RABSDKHooks = [NSMutableSet set];
    for (NSBundle *bundle in [NSBundle allFrameworks])
        if ([bundle.bundlePath.lastPathComponent.lowercaseString containsString:@"adswizz"])
            RABLog([NSString stringWithFormat:@"SDK framework=%@ version=%@", bundle.bundlePath.lastPathComponent,
                [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown"]);
    for (NSString *name in @[@"AASDKAdManager", @"AASDKAdManagerDelegate", @"AASDKAdStreamManagerDelegate"]) {
        Protocol *protocol = NSProtocolFromString(name);
        if (!protocol) { RABLog([@"SDK MISSING PROTOCOL " stringByAppendingString:name]); continue; }
        for (NSUInteger required = 0; required < 2; ++required) {
            unsigned int count = 0;
            struct objc_method_description *methods = protocol_copyMethodDescriptionList(protocol, required != 0, YES, &count);
            for (unsigned int i = 0; methods && i < count; ++i)
                RABLog([NSString stringWithFormat:@"SDK API %@ %@ %s", name,
                    NSStringFromSelector(methods[i].name), methods[i].types ?: "unknown"]);
            free(methods);
        }
    }
    RABAdsWizzRefresh();
    RABLog([NSString stringWithFormat:@"SDK protocol AdManager=%d streamDelegate=%d skipHooksReady=%d",
        NSProtocolFromString(@"AASDKAdManager") != nil,
        NSProtocolFromString(@"AASDKAdStreamManagerDelegate") != nil, RABSDKReady]);
    [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidBecomeActiveNotification" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) { RABAdsWizzRefresh(); }];
}
