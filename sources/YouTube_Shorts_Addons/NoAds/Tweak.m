#import "../Shared/Runtime.h"

// Shorts-specific model identification follows PoomSmart's MIT-licensed
// YouTube-X (48b901532f9e12152684f3326d4250efcdea61e5, 2026-09-20).
// See Licenses/YouTube-X-MIT.txt. All other feeds are left to YouTubePatcher.
static NSMutableSet *installedHooks;
static unsigned long removedCount;

static BOOL IsAdModel(id model) {
    if (!model) return NO;
    @try {
        long long videoType = 0;
        if (YSInteger(model, @selector(videoType), &videoType) && videoType == 3) return YES;
        Class nonVideo = NSClassFromString(@"YTReelNonVideoContentModel");
        if (!nonVideo || ![model isKindOfClass:nonVideo]) return NO;
        id renderer = YSObject(model, @selector(renderer));
        id data = YSObject(renderer, @selector(customData));
        return [[data description] containsString:@"YTIReelNonVideoAdsCustomData_reelNonVideoAdsCustomData"];
    } @catch (__unused NSException *exception) {
        // An unrecognized model is preserved, never guessed to be an ad.
        return NO;
    }
}

static void CountRemoval(void) {
    unsigned long count = __atomic_add_fetch(&removedCount, 1, __ATOMIC_RELAXED);
    if (count <= 5 || count % 50 == 0)
        YSLog(@"NoAds", @"Filtered Shorts ad models this launch: %lu", count);
}

static id FilterModel(id model) {
    if (!IsAdModel(model)) return model;
    CountRemoval();
    return nil;
}

static id FilterCollection(id reels) {
    if (![reels isKindOfClass:NSOrderedSet.class] && ![reels isKindOfClass:NSArray.class]) return reels;
    NSIndexSet *indexes = [reels indexesOfObjectsPassingTest:^BOOL(id model, NSUInteger index, BOOL *stop) {
        return IsAdModel(model);
    }];
    if (indexes.count == 0) return reels;
    // Do not mutate a shared feed collection owned by another hook or caller.
    id filtered = [reels mutableCopy];
    [filtered removeObjectsAtIndexes:indexes];
    for (NSUInteger i = 0; i < indexes.count; ++i) CountRemoval();
    return filtered;
}

static void HookFactory(Class cls, BOOL classMethod) {
    if (!cls) return;
    Class target = classMethod ? object_getClass(cls) : cls;
    SEL selector = NSSelectorFromString(@"makeContentModelForEntry:");
    NSString *key = [NSString stringWithFormat:@"%c[%@ %@]", classMethod ? '+' : '-', NSStringFromClass(cls), NSStringFromSelector(selector)];
    if ([installedHooks containsObject:key]) return;
    if (!YSMatches(target, selector, '@', 3, '@')) {
        YSLog(@"NoAds", @"Unavailable or changed ABI: %@", key);
        return;
    }
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^id(id object, id entry) {
        id model = ((id (*)(id, SEL, id))original)(object, selector, entry);
        return FilterModel(model);
    });
    MSHookMessageEx(target, selector, replacement, &original);
    [installedHooks addObject:key];
    YSLog(@"NoAds", @"Hooked %@", key);
}

static void HookCollection(Class cls) {
    if (!cls) return;
    SEL selector = NSSelectorFromString(@"setReels:");
    NSString *key = [NSString stringWithFormat:@"-[%@ setReels:]", NSStringFromClass(cls)];
    if ([installedHooks containsObject:key] || !YSMatches(cls, selector, 'v', 3, '@')) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^(id object, id reels) {
        ((void (*)(id, SEL, id))original)(object, selector, FilterCollection(reels));
    });
    MSHookMessageEx(cls, selector, replacement, &original);
    [installedHooks addObject:key];
    YSLog(@"NoAds", @"Hooked %@", key);
}

static void InstallHooks(void) {
    HookFactory(NSClassFromString(@"YTReelDataSource"), NO);
    HookFactory(NSClassFromString(@"YTReelContentModel"), YES);
    HookFactory(NSClassFromString(@"YTReelInfinitePlaybackDataSource"), NO);
    HookCollection(NSClassFromString(@"YTReelInfinitePlaybackDataSource"));
}

__attribute__((constructor)) static void InitializeNoAds(void) {
    @autoreleasepool {
        if (!YSIsYouTube()) return;
        installedHooks = [NSMutableSet set];
        InstallHooks();
        YSLog(@"NoAds", @"1.0.0 Test 1 loaded; YouTube %@; %lu hooks.",
              [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"], (unsigned long)installedHooks.count);
        [NSNotificationCenter.defaultCenter addObserverForName:@"UIApplicationDidBecomeActiveNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { InstallHooks(); }];
    }
}
