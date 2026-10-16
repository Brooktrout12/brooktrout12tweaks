#import <UIKit/UIKit.h>
#import "../Shared/Runtime.h"
#import "../Shared/ForegroundState.h"

// Test 2 caches confirmed Shorts owners/players BEFORE views lose their windows.
@interface YSShortsOwnerRecord : NSObject {
@public
    YSShortsOwnerState visibility;
}
@property(nonatomic, weak) UIViewController *owner;
@property(nonatomic, strong) NSHashTable *targets;
@end
@implementation YSShortsOwnerRecord
@end

@interface YSShortsOwnerLink : NSObject
@property(nonatomic, weak) UIViewController *owner;
@end
@implementation YSShortsOwnerLink
@end

static NSMapTable *ownerRecords;
static NSHashTable *pausedTargets;
static NSMutableSet *installedHooks, *describedClasses;
static NSMutableArray *notificationObservers;
static YSForegroundState state;
static bool inactiveGate;
static BOOL dispatchingPause;
static char markedTargetKey, ownerLinkKey;
static unsigned long blockedPlayCount;

static NSArray<NSString *> *OwnerClassNames(void) {
    return @[@"YTReelPlayerViewController", @"YTReelPlayerViewControllerSub",
             @"YTShortsPlayerViewController", @"YTReelWatchRootViewController"];
}
static BOOL IsShortsOwner(id object) {
    if (![object isKindOfClass:UIViewController.class]) return NO;
    for (NSString *name in OwnerClassNames()) {
        Class cls = NSClassFromString(name);
        if (cls && [object isKindOfClass:cls]) return YES;
    }
    return NO;
}
static void OnMain(dispatch_block_t block) {
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
}
static id SafeObject(id object, SEL selector) {
    @try { return YSObject(object, selector); }
    @catch (__unused NSException *exception) { return nil; }
}
static BOOL CanPause(id object) {
    return object && (YSMatches(object_getClass(object), @selector(pause), 'v', 2, 0) ||
                      YSMatches(object_getClass(object), NSSelectorFromString(@"pauseVideo"), 'v', 2, 0));
}
static BOOL IsVisible(UIViewController *controller) {
    UIView *view = controller.viewIfLoaded;
    UIWindow *window = view.window;
    if (!view || !window || window.hidden || window.alpha < 0.01) return NO;
    for (UIView *current = view; current; current = current.superview)
        if (current.hidden || current.alpha < 0.01) return NO;
    CGRect area = CGRectIntersection([view convertRect:view.bounds toView:window], window.bounds);
    return !CGRectIsNull(area) && area.size.width > 1 && area.size.height > 1;
}
static BOOL IsSystemTransition(UIViewController *owner) {
    if (state.inactive || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return YES;
    UIWindowScene *scene = owner.viewIfLoaded.window.windowScene;
    return scene && scene.activationState != UISceneActivationStateForegroundActive;
}
static void DescribeClass(id object) {
    if (!object) return;
    NSString *name = NSStringFromClass([object class]);
    if ([describedClasses containsObject:name]) return;
    [describedClasses addObject:name];
    NSMutableArray *methods = [NSMutableArray array];
    for (Class cls = [object class]; cls && cls != UIViewController.class && cls != NSObject.class;
         cls = class_getSuperclass(cls)) {
        unsigned count = 0;
        Method *list = class_copyMethodList(cls, &count);
        for (unsigned i = 0; i < count && methods.count < 45; ++i) {
            NSString *selector = NSStringFromSelector(method_getName(list[i]));
            NSString *lower = selector.lowercaseString;
            if ([lower containsString:@"pause"] || [lower containsString:@"player"] ||
                [lower containsString:@"background"] || [selector isEqualToString:@"play"] ||
                [selector isEqualToString:@"currentVideo"] || [selector isEqualToString:@"activeVideo"])
                [methods addObject:[NSString stringWithFormat:@"%@=%s", selector, method_getTypeEncoding(list[i])]];
        }
        free(list);
    }
    YSLog(@"ForegroundOnly", @"Runtime %@ pause=%d; methods=%@", name, CanPause(object), [methods componentsJoinedByString:@", "]);
}
static YSShortsOwnerRecord *RecordFor(UIViewController *owner, BOOL create) {
    if (!owner) return nil;
    YSShortsOwnerRecord *record = [ownerRecords objectForKey:owner];
    if (!record && create) {
        record = [YSShortsOwnerRecord new];
        record.owner = owner;
        record.targets = [NSHashTable weakObjectsHashTable];
        [ownerRecords setObject:record forKey:owner];
    }
    return record;
}
static void LinkTarget(id target, YSShortsOwnerRecord *record) {
    if (!target || !record.owner) return;
    DescribeClass(target);
    if (!CanPause(target)) return;
    YSShortsOwnerLink *link = [YSShortsOwnerLink new];
    link.owner = record.owner;
    objc_setAssociatedObject(target, &ownerLinkKey, link, OBJC_ASSOCIATION_RETAIN);
    [record.targets addObject:target];
}
static void LearnPlayerGraph(id object, YSShortsOwnerRecord *record, NSMutableSet *seen, NSUInteger depth) {
    if (!object || depth > 3 || seen.count >= 24) return;
    NSValue *identity = [NSValue valueWithNonretainedObject:object];
    if ([seen containsObject:identity]) return;
    [seen addObject:identity];
    LinkTarget(object, record);
    // Only relationship getters; no guessed ivar offsets or global audio changes.
    for (NSString *name in @[@"player", @"playerViewController", @"currentVideo", @"activeVideo",
                            @"playbackController", @"localPlaybackController"])
        LearnPlayerGraph(SafeObject(object, NSSelectorFromString(name)), record, seen, depth + 1);
}
static void RefreshRecord(YSShortsOwnerRecord *record) {
    if (record.owner) LearnPlayerGraph(record.owner, record, [NSMutableSet set], 0);
}
static void MarkSessionTarget(id target) {
    if (!CanPause(target)) return;
    [pausedTargets addObject:target];
    objc_setAssociatedObject(target, &markedTargetKey, @YES, OBJC_ASSOCIATION_RETAIN);
}
static void CaptureRecord(YSShortsOwnerRecord *record) {
    if (!record || !YSShouldCaptureOwner(&record->visibility)) return;
    RefreshRecord(record);
    for (id target in record.targets.allObjects) {
        YSShortsOwnerLink *link = objc_getAssociatedObject(target, &ownerLinkKey);
        if (link.owner == record.owner) MarkSessionTarget(target);
    }
}
static void PauseCaptured(uint64_t epoch, BOOL report) {
    if (dispatchingPause || !YSShouldPause(&state, epoch, pausedTargets.count > 0)) return;
    dispatchingPause = YES;
    NSUInteger count = 0;
    for (id target in pausedTargets.allObjects) {
        @try {
            if (YSVoid(target, @selector(pause)) || YSVoid(target, NSSelectorFromString(@"pauseVideo"))) ++count;
        } @catch (NSException *exception) {
            YSLog(@"ForegroundOnly", @"Pause exception %@ on %@", exception.name, NSStringFromClass([target class]));
        }
    }
    dispatchingPause = NO;
    if (report) YSLog(@"ForegroundOnly", @"Pause dispatched to %lu captured Shorts playback objects.", (unsigned long)count);
}
static void NoteOwner(UIViewController *owner, NSString *reason) {
    if (!IsShortsOwner(owner)) return;
    YSShortsOwnerRecord *record = RecordFor(owner, YES);
    BOOL wasActive = YSShouldCaptureOwner(&record->visibility);
    YSShortsOwnerAppearedOrPlayed(&record->visibility);
    RefreshRecord(record);
    if (!wasActive) YSLog(@"ForegroundOnly", @"Tracking %@ via %@; cached players=%lu; visible=%d",
                         NSStringFromClass(owner.class), reason, (unsigned long)record.targets.count, IsVisible(owner));
    if (state.inactive) { CaptureRecord(record); PauseCaptured(state.epoch, YES); }
}
static UIViewController *OwnerInControllerChain(id object) {
    UIViewController *controller = [object isKindOfClass:UIViewController.class] ? object : nil;
    for (NSUInteger i = 0; controller && i < 20; ++i, controller = controller.parentViewController)
        if (IsShortsOwner(controller)) return controller;
    id uiDelegate = SafeObject(object, NSSelectorFromString(@"UIDelegate"));
    return IsShortsOwner(uiDelegate) ? uiDelegate : nil;
}
static UIViewController *FindOwnerForPlayback(id object) {
    if (IsShortsOwner(object)) return object;
    UIViewController *owner = OwnerInControllerChain(object);
    if (owner) return owner;
    owner = OwnerInControllerChain(SafeObject(object, @selector(delegate)));
    if (owner) return owner;
    id parent = SafeObject(object, NSSelectorFromString(@"parentResponder"));
    for (NSUInteger i = 0; parent && i < 5; ++i) {
        owner = OwnerInControllerChain(parent);
        if (owner) return owner;
        parent = SafeObject(parent, NSSelectorFromString(@"parentResponder"));
    }
    YSShortsOwnerLink *link = objc_getAssociatedObject(object, &ownerLinkKey);
    YSShortsOwnerRecord *record = RecordFor(link.owner, NO);
    if (!record || !YSShouldCaptureOwner(&record->visibility)) return nil;
    // A visible regular player is stronger evidence than a stale cached link.
    if ([object isKindOfClass:UIViewController.class] && IsVisible(object) && !OwnerInControllerChain(object)) return nil;
    return record.owner;
}
static void RetireDetachedLinksForRegularPlayer(id object) {
    if (![object isKindOfClass:UIViewController.class] || !IsVisible(object)) return;
    for (YSShortsOwnerRecord *record in ownerRecords.objectEnumerator.allObjects) {
        if ([record.targets containsObject:object] && !IsVisible(record.owner)) {
            // The same player is now visibly used outside the Shorts hierarchy.
            YSShortsOwnerDisappeared(&record->visibility, false);
            [record.targets removeObject:object];
        }
    }
    objc_setAssociatedObject(object, &ownerLinkKey, nil, OBJC_ASSOCIATION_RETAIN);
}
static void ScanControllers(UIViewController *controller, NSMutableSet *seen, NSUInteger depth) {
    if (!controller || depth > 32 || seen.count >= 256) return;
    NSValue *identity = [NSValue valueWithNonretainedObject:controller];
    if ([seen containsObject:identity]) return;
    [seen addObject:identity];
    if (IsShortsOwner(controller) && IsVisible(controller)) NoteOwner(controller, @"visible tree");
    for (UIViewController *child in controller.childViewControllers)
        if (child.isViewLoaded) ScanControllers(child, seen, depth + 1);
    ScanControllers(controller.presentedViewController, seen, depth + 1);
}
static void ScanVisibleOwners(void) {
    NSMutableSet *seen = [NSMutableSet set];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (!window.hidden) ScanControllers(window.rootViewController, seen, 0);
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in UIApplication.sharedApplication.windows)
        if (!window.hidden) ScanControllers(window.rootViewController, seen, 0);
#pragma clang diagnostic pop
}
static void LeaveForeground(NSString *reason) {
    // Cached owners stay eligible even when this last scan sees no windows.
    ScanVisibleOwners();
    __atomic_store_n(&inactiveGate, true, __ATOMIC_RELEASE);
    uint64_t epoch = YSLeaveForeground(&state);
    NSUInteger owners = 0;
    for (YSShortsOwnerRecord *record in ownerRecords.objectEnumerator.allObjects)
        if (YSShouldCaptureOwner(&record->visibility)) { ++owners; CaptureRecord(record); }
    YSLog(@"ForegroundOnly", @"Exit %@; appState=%ld; tracked Shorts=%lu; targets=%lu; epoch=%llu",
          reason, (long)UIApplication.sharedApplication.applicationState,
          (unsigned long)owners, (unsigned long)pausedTargets.count, (unsigned long long)epoch);
    PauseCaptured(epoch, YES);
    for (NSNumber *delay in @[@0.0, @0.08, @0.25, @0.65, @1.25])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            PauseCaptured(epoch, NO);
        });
}
static void EnterForeground(NSString *reason) {
    YSEnterForeground(&state);
    __atomic_store_n(&inactiveGate, false, __ATOMIC_RELEASE);
    for (id target in pausedTargets.allObjects)
        objc_setAssociatedObject(target, &markedTargetKey, nil, OBJC_ASSOCIATION_RETAIN);
    [pausedTargets removeAllObjects];
    YSLog(@"ForegroundOnly", @"Active %@; tracked records=%lu", reason, (unsigned long)ownerRecords.count);
    ScanVisibleOwners();
    // No forced resume; YouTube keeps its normal foreground playback behavior.
}
static BOOL BeginHook(Class cls, SEL selector, char result, unsigned arguments, char argType, NSString **key) {
    if (!cls) return NO;
    *key = [NSString stringWithFormat:@"%@/%@", NSStringFromClass(cls), NSStringFromSelector(selector)];
    return ![installedHooks containsObject:*key] && YSMatches(cls, selector, result, arguments, argType);
}
static void CompleteHook(Class cls, SEL selector, IMP replacement, IMP *original, NSString *key) {
    MSHookMessageEx(cls, selector, replacement, original);
    [installedHooks addObject:key];
    YSLog(@"ForegroundOnly", @"Hooked %@", key);
}
static void HookVisibility(Class cls, SEL selector, BOOL appearing) {
    NSString *key;
    if (!BeginHook(cls, selector, 'v', 3, 'B', &key)) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^(UIViewController *owner, BOOL animated) {
        if (appearing) NoteOwner(owner, NSStringFromSelector(selector));
        else {
            YSShortsOwnerRecord *record = RecordFor(owner, NO);
            BOOL transition = IsSystemTransition(owner);
            if (record) {
                YSShortsOwnerDisappeared(&record->visibility, transition);
                YSLog(@"ForegroundOnly", @"Disappear %@; systemTransition=%d; retained=%d",
                      NSStringFromClass(owner.class), transition, YSShouldCaptureOwner(&record->visibility));
            }
        }
        ((void (*)(id, SEL, BOOL))original)(owner, selector, animated);
        if (appearing) NoteOwner(owner, NSStringFromSelector(selector));
    });
    CompleteHook(cls, selector, replacement, &original, key);
}
static void HookPlay(Class cls, SEL selector) {
    NSString *key;
    if (!BeginHook(cls, selector, 'v', 2, 0, &key)) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^(id object) {
        if (NSThread.isMainThread && !dispatchingPause) {
            UIViewController *owner = FindOwnerForPlayback(object);
            if (owner) {
                NoteOwner(owner, @"play");
                LinkTarget(object, RecordFor(owner, YES));
                if (state.inactive) MarkSessionTarget(object);
            } else if (!state.inactive) RetireDetachedLinksForRegularPlayer(object);
        }
        if (__atomic_load_n(&inactiveGate, __ATOMIC_ACQUIRE) && objc_getAssociatedObject(object, &markedTargetKey)) {
            unsigned long n = __atomic_add_fetch(&blockedPlayCount, 1, __ATOMIC_RELAXED);
            if (n <= 5 || n % 50 == 0) YSLog(@"ForegroundOnly", @"Prevented Shorts background restart (%lu).", n);
            return;
        }
        ((void (*)(id, SEL))original)(object, selector);
        OnMain(^{
            if (dispatchingPause) return;
            UIViewController *owner = FindOwnerForPlayback(object);
            if (owner) {
                NoteOwner(owner, @"play completed");
                LinkTarget(object, RecordFor(owner, YES));
                if (state.inactive) { MarkSessionTarget(object); PauseCaptured(state.epoch, NO); }
            }
        });
    });
    CompleteHook(cls, selector, replacement, &original, key);
}
static void HookNativeLifecycle(Class cls, SEL selector) {
    NSString *key;
    if (!BeginHook(cls, selector, 'v', 3, '@', &key)) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^(id object, id application) {
        if (NSThread.isMainThread) {
            UIViewController *owner = FindOwnerForPlayback(object);
            YSShortsOwnerRecord *record = RecordFor(owner, NO);
            // YouTube can broadcast these callbacks to cached/offscreen owners.
            // Such a callback alone is not evidence that a Short is current.
            if (owner && ((record && YSShouldCaptureOwner(&record->visibility)) || IsVisible(owner)))
                NoteOwner(owner, @"YouTube lifecycle");
            LeaveForeground([@"YouTube/" stringByAppendingString:NSStringFromSelector(selector)]);
        }
        ((void (*)(id, SEL, id))original)(object, selector, application);
        OnMain(^{ PauseCaptured(state.epoch, NO); });
    });
    CompleteHook(cls, selector, replacement, &original, key);
}
static void InstallHooks(void) {
    for (NSString *name in OwnerClassNames()) {
        Class cls = NSClassFromString(name);
        if (!cls || ![cls isSubclassOfClass:UIViewController.class]) continue;
        HookVisibility(cls, @selector(viewWillAppear:), YES);
        HookVisibility(cls, @selector(viewDidAppear:), YES);
        HookVisibility(cls, @selector(viewDidDisappear:), NO);
        HookNativeLifecycle(cls, NSSelectorFromString(@"appWillResignActive:"));
        HookNativeLifecycle(cls, NSSelectorFromString(@"appDidEnterBackground:"));
    }
    for (NSString *name in @[@"YTPlayerViewController", @"YTLocalPlaybackController", @"YTSingleVideoController",
                            @"YTReelPlayerViewController", @"YTShortsPlayerViewController"]) {
        Class cls = NSClassFromString(name);
        if (!cls) continue;
        HookPlay(cls, @selector(play));
        HookPlay(cls, NSSelectorFromString(@"playVideo"));
    }
}
static void Observe(NSString *name, BOOL active, BOOL sceneEvent) {
    id token = [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (sceneEvent && ![note.object isKindOfClass:UIWindowScene.class]) return;
        OnMain(^{
            if (sceneEvent) {
                UIWindowScene *scene = note.object;
                if (![scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) return;
            }
            if (active) { EnterForeground(name); InstallHooks(); }
            else LeaveForeground(name);
        });
    }];
    [notificationObservers addObject:token];
}
__attribute__((constructor)) static void InitializeForegroundOnly(void) {
    @autoreleasepool {
        if (!YSIsYouTube()) return;
        ownerRecords = [NSMapTable weakToStrongObjectsMapTable];
        pausedTargets = [NSHashTable weakObjectsHashTable];
        installedHooks = [NSMutableSet set];
        describedClasses = [NSMutableSet set];
        notificationObservers = [NSMutableArray array];
        InstallHooks();
        Observe(UIApplicationWillResignActiveNotification, NO, NO);
        Observe(UIApplicationDidEnterBackgroundNotification, NO, NO);
        Observe(UIApplicationDidBecomeActiveNotification, YES, NO);
        Observe(UISceneWillDeactivateNotification, NO, YES);
        Observe(UISceneDidEnterBackgroundNotification, NO, YES);
        Observe(UISceneDidActivateNotification, YES, YES);
        YSLog(@"ForegroundOnly", @"1.0.1 Test 2 loaded; YouTube %@; iOS %@; %lu hooks; app + scene events enabled.",
              [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
              UIDevice.currentDevice.systemVersion, (unsigned long)installedHooks.count);
    }
}
