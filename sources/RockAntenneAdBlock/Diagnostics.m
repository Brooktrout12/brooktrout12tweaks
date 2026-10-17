#import "Diagnostics.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <sys/utsname.h>
#include <math.h>

static dispatch_queue_t RABQueue;
static NSString *RABPath, *RABPreviousPath;
static NSMutableSet<NSString *> *RABSeenHosts;
static NSHashTable<AVPlayer *> *RABPlayers;
static NSMutableDictionary<NSString *, NSNumber *> *RABCounters;
static NSUInteger RABLines, RABBlocked, RABBytes;
static const NSUInteger RABLineLimit = 1800;
static const char RABGestureKey;
static const char RABCheckpointKey;

// All file writes and counters are serialized, bounded and kept inside the
// application's sandbox. Query strings, request bodies and headers are omitted.
static void RABWrite(NSString *message) {
    if (!RABPath || RABLines >= RABLineLimit) return;
    ++RABLines;
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (RABBytes + data.length > 256 * 1024) return;
    RABBytes += data.length;
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:RABPath];
    if (!file) return;
    @try { [file seekToEndOfFile]; [file writeData:data]; [file closeFile]; }
    @catch (__unused NSException *exception) { @try { [file closeFile]; } @catch (__unused NSException *ignored) {} }
}
void RABLog(NSString *message) {
    if (!RABQueue || !message) return;
    dispatch_async(RABQueue, ^{ RABWrite(message); });
}
void RABDiagnosticCounter(NSString *name) {
    if (!RABQueue) return;
    dispatch_async(RABQueue, ^{ RABCounters[name] = @([RABCounters[name] unsignedIntegerValue] + 1); });
}
void RABObserveHost(NSString *host, BOOL blocked) {
    if (!RABQueue || !host.length) return;
    dispatch_async(RABQueue, ^{
        NSString *key = [NSString stringWithFormat:@"%@ %@", blocked ? @"AD-HOST" : @"HOST", host];
        if (RABSeenHosts.count >= 120 || [RABSeenHosts containsObject:key]) return;
        [RABSeenHosts addObject:key]; RABWrite(key);
    });
}
void RABBlockedRequest(NSURLRequest *request, BOOL vast) {
    NSString *host = request.URL.host ?: @"unknown";
    dispatch_async(RABQueue, ^{
        ++RABBlocked;
        if (RABBlocked <= 120 || RABBlocked % 100 == 0)
            RABWrite([NSString stringWithFormat:@"BLOCK #%lu host=%@ response=%@", (unsigned long)RABBlocked, host, vast ? @"empty-VAST" : @"204"]);
    });
}

static NSString *RABSafeMediaURL(NSURL *url) {
    if (!url) return @"none";
    NSString *host = url.host.lowercaseString ?: @"";
    NSString *path = @"/<path-omitted>";
    if ([host isEqualToString:@"stream.rockantenne.de"] || [host isEqualToString:@"stream.antenne.de"]) {
        NSRegularExpression *safe = [NSRegularExpression regularExpressionWithPattern:@"^/[A-Za-z0-9_-]+/stream(?:/(?:mp3|aacp))?$" options:0 error:nil];
        if ([safe numberOfMatchesInString:url.path options:0 range:NSMakeRange(0, url.path.length)]) path = url.path;
    }
    return [NSString stringWithFormat:@"%@://%@%@", url.scheme ?: @"unknown", host, path];
}
void RABMediaEvent(NSURL *url, NSString *event) {
    if (!url) return;
    NSArray<NSURLQueryItem *> *items = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems;
    NSUInteger adsWizz = 0;
    for (NSURLQueryItem *item in items)
        if ([item.name hasPrefix:@"aw_"] || [@[@"companionAds", @"sdkiad"] containsObject:item.name]) ++adsWizz;
    RABLog([NSString stringWithFormat:@"MEDIA %@ url=%@ queryCount=%lu adsWizzParameterCount=%lu (values omitted)",
        event, RABSafeMediaURL(url), (unsigned long)items.count, (unsigned long)adsWizz]);
}

void RABPlayerEvent(AVPlayer *player, NSString *event) {
    if (!player) return;
    @synchronized (RABPlayers) { [RABPlayers addObject:player]; }
    AVPlayerItem *item = player.currentItem;
    AVAsset *asset = item.asset;
    NSString *url = [asset isKindOfClass:[AVURLAsset class]] ? RABSafeMediaURL(((AVURLAsset *)asset).URL) : @"non-URL-asset";
    if ([asset isKindOfClass:[AVURLAsset class]] &&
        ([event hasPrefix:@"play"] || [event isEqualToString:@"replaceItem"]))
        RABMediaEvent(((AVURLAsset *)asset).URL, event);
    NSString *control = player.timeControlStatus == AVPlayerTimeControlStatusPlaying ? @"playing" :
        player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate ? @"waiting" : @"paused";
    double position = CMTimeGetSeconds(player.currentTime);
    RABLog([NSString stringWithFormat:@"PLAYER %@ class=%@ rate=%.2f playerStatus=%ld itemStatus=%ld timeControl=%@ position=%.2f error=%@:%ld media=%@",
        event, NSStringFromClass(player.class), player.rate, (long)player.status, (long)item.status,
        control, isfinite(position) ? position : -1, item.error.domain ?: @"none", (long)item.error.code, url]);
}
void RABPlayerCheckpoints(AVPlayer *player) {
    if (!player) return;
    NSObject *generation = [NSObject new];
    objc_setAssociatedObject(player, &RABCheckpointKey, generation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak AVPlayer *weakPlayer = player;
    __weak AVPlayerItem *weakItem = player.currentItem;
    for (NSNumber *delay in @[@0.5, @2, @8, @20]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            AVPlayer *current = weakPlayer;
            if (!current || current.currentItem != weakItem || objc_getAssociatedObject(current, &RABCheckpointKey) != generation) return;
            RABPlayerEvent(current, [NSString stringWithFormat:@"checkpoint+%@s", delay]);
        });
    }
}

static UIWindow *RABKeyWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) return window;
    }
    return nil;
}
static UIViewController *RABTopController(void) {
    UIViewController *top = RABKeyWindow().rootViewController;
    for (NSUInteger i = 0; top && i < 20; ++i) {
        if (top.presentedViewController && !top.presentedViewController.isBeingDismissed) { top = top.presentedViewController; continue; }
        if ([top isKindOfClass:[UINavigationController class]]) { top = ((UINavigationController *)top).visibleViewController; continue; }
        if ([top isKindOfClass:[UITabBarController class]]) { top = ((UITabBarController *)top).selectedViewController; continue; }
        break;
    }
    return top;
}

static BOOL RABInterestingClass(NSString *name) {
    NSString *lower = name.lowercaseString;
    for (NSString *term in @[@"aasdk", @"adswizz", @"advert", @"preroll", @"interstitial", @"gadbanner", @"imaads", @"sasbanner", @"audioplayer", @"streamplayer", @"admanager", @"adloader", @"adview", @"avplayer"]) {
        if ([lower containsString:term]) return YES;
    }
    return NO;
}
static void RABSnapshotViews(UIView *view, NSUInteger depth, NSUInteger *remaining) {
    if (!view || !*remaining || depth > 9) return;
    --*remaining;
    RABLog([NSString stringWithFormat:@"VIEW depth=%lu class=%@ hidden=%d alpha=%.2f size=%.0fx%.0f",
        (unsigned long)depth, NSStringFromClass(view.class), view.hidden, view.alpha,
        view.bounds.size.width, view.bounds.size.height]);
    for (UIView *child in view.subviews) RABSnapshotViews(child, depth + 1, remaining);
}
static void RABSnapshot(void) {
    RABLog(@"--- DIAGNOSTIC SNAPSHOT ---");
    NSArray<AVPlayer *> *players;
    @synchronized (RABPlayers) { players = RABPlayers.allObjects; }
    RABLog([NSString stringWithFormat:@"Observed AVPlayers=%lu", (unsigned long)players.count]);
    for (AVPlayer *player in players) RABPlayerEvent(player, @"snapshot");
    NSUInteger remaining = 90;
    RABSnapshotViews(RABKeyWindow(), 0, &remaining);
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSUInteger emitted = 0, systemClasses = 0;
    NSString *mainBundlePath = [NSBundle mainBundle].bundlePath;
    // Protocol implementers first, public aliases second, other matching classes
    // last. The Test 1 runtime-order cap could omit the useful classes entirely.
    NSMutableArray<Class> *ordered = [NSMutableArray array];
    NSMutableArray<Class> *aliases = [NSMutableArray array], *others = [NSMutableArray array];
    Protocol *adManager = NSProtocolFromString(@"AASDKAdManager");
    Protocol *streamDelegate = NSProtocolFromString(@"AASDKAdStreamManagerDelegate");
    Protocol *adDelegate = NSProtocolFromString(@"AASDKAdManagerDelegate");
    for (unsigned int i = 0; classes && i < count; ++i) {
        NSString *name = NSStringFromClass(classes[i]);
        BOOL protocolClass = (adManager && class_conformsToProtocol(classes[i], adManager)) ||
            (streamDelegate && class_conformsToProtocol(classes[i], streamDelegate)) ||
            (adDelegate && class_conformsToProtocol(classes[i], adDelegate));
        if (protocolClass) [ordered addObject:classes[i]];
        else if ([name hasPrefix:@"AASDK"]) [aliases addObject:classes[i]];
        else if (RABInterestingClass(name)) [others addObject:classes[i]];
    }
    free(classes);
    [ordered addObjectsFromArray:aliases];
    [ordered addObjectsFromArray:others];
    for (Class cls in ordered) {
        if (emitted >= 80) break;
        NSString *name = NSStringFromClass(cls);
        const char *image = class_getImageName(cls);
        NSString *imagePath = image ? [NSString stringWithUTF8String:image] : @"";
        BOOL inApp = [imagePath hasPrefix:mainBundlePath] ||
            [imagePath containsString:[NSString stringWithFormat:@"/%@/", mainBundlePath.lastPathComponent]];
        if (!inApp && systemClasses >= 12) continue;
        // App/SDK methods only; system player class names are sufficient.
        RABLog([NSString stringWithFormat:@"CLASS %@ image=%@", name, imagePath.lastPathComponent]);
        if (!inApp) { ++systemClasses; continue; }
        ++emitted;
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        for (unsigned int j = 0; methods && j < methodCount && j < 24; ++j) {
            RABLog([NSString stringWithFormat:@"  METHOD %@ %s", NSStringFromSelector(method_getName(methods[j])), method_getTypeEncoding(methods[j])]);
        }
        free(methods);
    }
    RABLog(@"--- END SNAPSHOT ---");
}

static void RABShareReport(NSString *reason) {
    RABLog([@"USER REPORT: " stringByAppendingString:reason]);
    // This is queued behind earlier diagnostic writes, so the report includes
    // the incident marker and pre-dialog UI snapshot without blocking the UI.
    dispatch_async(RABQueue, ^{
        NSMutableString *report = [NSMutableString stringWithString:@"ROCK ANTENNE AdBlock – Test 2\nThis report is only shared when the user chooses a destination.\nNo query strings, cookies, headers, account data or recordings are collected.\nA blocked request, skip call, or playing state does NOT prove that the listener heard no advertisement.\n\n"];
        [report appendFormat:@"Report reason: %@\nBlocked native requests this launch: %lu\n\n", reason, (unsigned long)RABBlocked];
        for (NSString *key in [[RABCounters allKeys] sortedArrayUsingSelector:@selector(compare:)])
            [report appendFormat:@"%@: %@\n", key, RABCounters[key]];
        [report appendString:@"\n"];
        NSString *previous = [NSString stringWithContentsOfFile:RABPreviousPath encoding:NSUTF8StringEncoding error:nil];
        if (previous.length) [report appendFormat:@"=== PREVIOUS LAUNCH ===\n%@\n", previous];
        NSString *current = [NSString stringWithContentsOfFile:RABPath encoding:NSUTF8StringEncoding error:nil];
        [report appendFormat:@"=== CURRENT LAUNCH ===\n%@\n", current ?: @"Log unavailable"];
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"RockAntenneAdBlock"];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *path = [directory stringByAppendingPathComponent:@"RockAntenneAdBlock-Diagnose.txt"];
        NSError *error = nil;
        BOOL saved = [report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *top = RABTopController();
            if (!top) return;
            if (!saved) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Diagnose konnte nicht gespeichert werden" message:@"Das Protokoll bleibt im Documents-Ordner der ROCK ANTENNE-App." preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [top presentViewController:alert animated:YES completion:nil];
                return;
            }
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
            UIPopoverPresentationController *popover = share.popoverPresentationController;
            popover.sourceView = top.view;
            popover.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
            popover.permittedArrowDirections = 0;
            [top presentViewController:share animated:YES completion:nil];
        });
    });
}

@interface RABDiagnosticMenu : NSObject <UIGestureRecognizerDelegate>
- (void)longPress:(UILongPressGestureRecognizer *)recognizer;
@end
@implementation RABDiagnosticMenu
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)gesture; (void)other; return YES;
}
- (void)longPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    UIViewController *top = RABTopController();
    if (!top || [top isKindOfClass:[UIAlertController class]] || [top isKindOfClass:[UIActivityViewController class]]) return;
    RABSnapshot();
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"ROCK ANTENNE AdBlock · Test 2" message:@"Die Diagnose läuft automatisch. Wähle, was du beim Start tatsächlich gehört oder gesehen hast." preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Audio-Werbung melden & teilen" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { RABShareReport(@"audio advertisement"); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Banner/Popup melden & teilen" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { RABShareReport(@"banner or popup"); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Wiedergabefehler melden & teilen" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { RABShareReport(@"playback failure"); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Direkter Livestream ohne Werbung & teilen" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { RABShareReport(@"listener reports direct live content without ad; ad availability unknown"); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Diagnose teilen" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { RABShareReport(@"general diagnostics"); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = top.view;
    menu.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
    menu.popoverPresentationController.permittedArrowDirections = 0;
    [top presentViewController:menu animated:YES completion:nil];
}
@end
static RABDiagnosticMenu *RABMenu;
static void RABAttachWindow(UIWindow *window) {
    if (!window || ![NSThread isMainThread] || objc_getAssociatedObject(window, &RABGestureKey)) return;
    if (!window.rootViewController) return;
    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:RABMenu action:@selector(longPress:)];
    gesture.numberOfTouchesRequired = 2;
    gesture.minimumPressDuration = 1.2;
    gesture.cancelsTouchesInView = NO;
    gesture.delaysTouchesBegan = NO;
    gesture.delaysTouchesEnded = NO;
    gesture.delegate = RABMenu;
    [window addGestureRecognizer:gesture];
    objc_setAssociatedObject(window, &RABGestureKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    RABLog(@"Diagnostic gesture attached (two fingers, 1.2 seconds)");
}
void RABDiagnosticsInstallMenu(void) {
    RABMenu = [RABDiagnosticMenu new];
    for (NSString *name in @[UIWindowDidBecomeVisibleNotification, UIWindowDidBecomeKeyNotification]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            if ([note.object isKindOfClass:[UIWindow class]]) RABAttachWindow(note.object);
        }];
    }
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes)
        if ([scene isKindOfClass:[UIWindowScene class]])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) RABAttachWindow(window);
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { RABLog(@"APP background"); }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { RABLog(@"APP active"); }];
}

void RABDiagnosticsInitialize(NSString *version) {
    RABQueue = dispatch_queue_create("de.brooktrout12.rockantenneadblock.log", DISPATCH_QUEUE_SERIAL);
    RABSeenHosts = [NSMutableSet set];
    RABCounters = [@{@"sdkSkipCalls": @0, @"sdkAdBreakStarts": @0, @"sdkAdBreakEnds": @0, @"sdkReconnects": @0} mutableCopy];
    RABPlayers = [NSHashTable weakObjectsHashTable];
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (documents) {
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:nil];
        RABPath = [documents stringByAppendingPathComponent:@"RockAntenneAdBlock.log"];
        RABPreviousPath = [documents stringByAppendingPathComponent:@"RockAntenneAdBlock-Previous.log"];
        if ([fm fileExistsAtPath:RABPath]) {
            [fm removeItemAtPath:RABPreviousPath error:nil];
            [fm moveItemAtPath:RABPath toPath:RABPreviousPath error:nil];
        }
        struct utsname info; uname(&info);
        NSString *header = [NSString stringWithFormat:@"Tweak loaded: %@\nApp %@ (%@); iOS %@; model %s\n",
            version, [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
            [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown",
            [NSProcessInfo processInfo].operatingSystemVersionString, info.machine];
        [header writeToFile:RABPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}
