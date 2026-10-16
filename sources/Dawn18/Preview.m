// On-demand, local preview through SpringBoard's existing notification UI.
// No BBServer initializer hook, extra app, daemon, or compiler-generated block.
#import <UIKit/UIKit.h>
#import <UserNotifications/UNNotificationContent.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
#import <pthread.h>
#import <substrate.h>
#import "Runtime.h"
#import "Preview.h"

static NSString *const D18PreviewSection = @"com.brooktrout12.dawn18.preview";
// Cover Sheet is the transport destination, not a list-membership marker.
// NCNotificationRootList checks these separate identifiers before insertion.
static NSString *const D18LockScreenDestination = @"BulletinDestinationLockScreen";
static NSString *const D18NotificationCenterDestination = @"BulletinDestinationNotificationCenter";
static int D18RequestToken = -1, D18ReplyToken = -1;
static char D18PreviewObserver;
static uint32_t D18LastRequest;
static CFTimeInterval D18LastRequestTime;

static BOOL D18SetFlag(id object, NSString *selector, BOOL value) {
    SEL sel = NSSelectorFromString(selector);
    if (!D18MethodMatches(object_getClass(object), sel, 'v', "b")) return NO;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(object, sel, value);
    return YES;
}

static BOOL D18SetUnsignedInteger(id object, NSString *selector, NSUInteger value) {
    SEL sel = NSSelectorFromString(selector);
    if (!D18MethodMatches(object_getClass(object), sel, 'v', "i")) return NO;
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(object, sel, value);
    return YES;
}

@interface D18PreviewController : NSObject
@property(nonatomic, weak) id dispatcher;
@property(nonatomic, strong) id request;
@property(nonatomic, copy) NSString *coverSheetIdentifier;
- (BOOL)ownsRequest:(id)request;
- (void)withdrawPreview:(id)request;
- (void)queueWithdrawal:(id)request;
- (void)removeDestinations:(NSDictionary *)removal;
@end

@implementation D18PreviewController
- (BOOL)ownsRequest:(id)request {
    id uuid = D18GetObject(request, NSSelectorFromString(@"uuid"));
    return uuid && [uuid isEqual:D18GetObject(_request, NSSelectorFromString(@"uuid"))];
}
- (void)withdrawPreview:(id)request {
    if (!pthread_main_np() || ![self ownsRequest:request]) return;
    id current = _request;
    // Forget first, so any reentrant clear callback cannot withdraw it twice.
    _request = nil;
    D18SetObject(_dispatcher, NSSelectorFromString(@"withdrawNotificationWithRequest:"), current);
}
- (void)queueWithdrawal:(id)request {
    // Keep cleanup outside the system's clear/action callback stack. A queued
    // request is checked again by UUID, so an old callback cannot clear a new test.
    if (pthread_main_np() && [self ownsRequest:request])
        [self performSelector:@selector(withdrawPreview:) withObject:request afterDelay:0];
}
- (void)removeDestinations:(NSDictionary *)removal {
    if (!pthread_main_np() || ![self ownsRequest:removal[@"request"]]) return;
    id destinations = D18GetObject(_request, NSSelectorFromString(@"requestDestinations"));
    if (![destinations isKindOfClass:NSSet.class]) return;
    NSMutableSet *targets = [removal[@"destinations"] mutableCopy];
    // Removing the whole Cover Sheet removes both of its lists. Removing only
    // Lock Screen must retain Notification Center and its transport route.
    if (_coverSheetIdentifier && [targets containsObject:_coverSheetIdentifier]) {
        [targets addObject:D18LockScreenDestination];
        [targets addObject:D18NotificationCenterDestination];
    }
    NSMutableSet *remaining = [destinations mutableCopy];
    [remaining minusSet:targets];
    if (_coverSheetIdentifier && ![remaining containsObject:D18LockScreenDestination] &&
        ![remaining containsObject:D18NotificationCenterDestination])
        [remaining removeObject:_coverSheetIdentifier];
    if ([remaining isEqualToSet:destinations]) return;
    if (!remaining.count) {
        [self withdrawPreview:_request];
        return;
    }
    // Dismissing only the banner must not also remove the Notification Center
    // card. Update this request's destinations, retaining its UUID.
    NSMutableSet *removed = [destinations mutableCopy];
    [removed minusSet:remaining];
    // Dispatch a partial list withdrawal through Cover Sheet as well. Its
    // list model uses the logical markers to remove/migrate the correct card.
    if (_coverSheetIdentifier && ([removed containsObject:D18LockScreenDestination] ||
                                 [removed containsObject:D18NotificationCenterDestination]))
        [removed addObject:_coverSheetIdentifier];
    id withdrawal = [_request mutableCopy];
    id updated = [_request mutableCopy];
    if (!D18SetObject(withdrawal, NSSelectorFromString(@"setRequestDestinations:"), removed) ||
        !D18SetObject(updated, NSSelectorFromString(@"setRequestDestinations:"), remaining)) return;
    _request = [updated copy];
    D18SetObject(_dispatcher, NSSelectorFromString(@"withdrawNotificationWithRequest:"), [withdrawal copy]);
    D18SetObject(_dispatcher, NSSelectorFromString(@"modifyNotificationWithRequest:"), _request);
}
- (void)clearAction:(id)action {
    if (!pthread_main_np() || !_request) return;
    NSString *identifier = D18GetObject(action, NSSelectorFromString(@"identifier"));
    id ownedAction = D18GetObject(_request, NSSelectorFromString(@"clearAction"));
    if (identifier && [identifier isEqual:D18GetObject(ownedAction, NSSelectorFromString(@"identifier"))])
        [self queueWithdrawal:_request];
}
- (void)executeAction:(id)action fromOrigin:(id)origin endpoint:(id)endpoint
       withParameters:(id)parameters completion:(id)completion {
    (void)origin; (void)endpoint; (void)parameters;
    // This completion is an existing, OS-created void callback. Forward it to
    // the OS's dispatch implementation without generating, copying, or invoking
    // a compiler block in our binary.
    if (completion) dispatch_async(dispatch_get_main_queue(), (dispatch_block_t)completion);
    [self performSelectorOnMainThread:@selector(clearAction:) withObject:action waitUntilDone:NO];
}
@end

static D18PreviewController *D18Preview;
static void (*D18OriginalClearRequests)(id, SEL, id, id);
static void (*D18OriginalClearDestinations)(id, SEL, id, id, id);
static void (*D18OriginalClearSections)(id, SEL, id, id);
static void (*D18OriginalClearRange)(id, SEL, id, id, id, id);
static id (*D18OriginalRequestForUUID)(id, SEL, id, id);
static Class D18RoutingClass;

static id D18PreviewForDispatcher(id dispatcher) {
    return pthread_main_np() && dispatcher == D18Preview.dispatcher ? D18Preview.request : nil;
}

static id D18PreviewInRequests(id dispatcher, id requests) {
    id preview = D18PreviewForDispatcher(dispatcher);
    if (!preview || ![requests conformsToProtocol:@protocol(NSFastEnumeration)]) return nil;
    for (id request in requests)
        if ([D18Preview ownsRequest:request]) return preview;
    return nil;
}

static void D18ClearRequests(id self, SEL cmd, id destination, id requests) {
    id preview = D18PreviewInRequests(self, requests);
    D18OriginalClearRequests(self, cmd, destination, requests);
    if (preview) [D18Preview queueWithdrawal:preview];
}

static void D18ClearDestinations(id self, SEL cmd, id destination, id requests, id destinations) {
    id preview = D18PreviewInRequests(self, requests);
    NSSet *targets = nil;
    if (preview) {
        if ([destinations isKindOfClass:NSSet.class]) targets = [destinations copy];
        else if ([destinations isKindOfClass:NSArray.class]) targets = [NSSet setWithArray:destinations];
    }
    NSDictionary *removal = targets ? @{@"request": preview, @"destinations": targets} : nil;
    D18OriginalClearDestinations(self, cmd, destination, requests, destinations);
    if (removal) [D18Preview performSelector:@selector(removeDestinations:) withObject:removal afterDelay:0];
}

static void D18ClearSections(id self, SEL cmd, id destination, id sections) {
    id preview = D18PreviewForDispatcher(self);
    if (preview && sections && ![sections containsObject:D18PreviewSection]) preview = nil;
    D18OriginalClearSections(self, cmd, destination, sections);
    if (preview) [D18Preview queueWithdrawal:preview];
}

static void D18ClearRange(id self, SEL cmd, id destination, NSDate *fromDate, NSDate *toDate, id sections) {
    id preview = D18PreviewForDispatcher(self);
    if (preview && sections && ![sections containsObject:D18PreviewSection]) preview = nil;
    NSDate *date = D18GetObject(preview, NSSelectorFromString(@"timestamp"));
    if (!date || (fromDate && [date compare:fromDate] == NSOrderedAscending) ||
                 (toDate && [date compare:toDate] == NSOrderedDescending)) preview = nil;
    D18OriginalClearRange(self, cmd, destination, fromDate, toDate, sections);
    if (preview) [D18Preview queueWithdrawal:preview];
}

static id D18RequestForUUID(id self, SEL cmd, id destination, id uuid) {
    id preview = D18PreviewForDispatcher(self);
    if (preview && uuid && [uuid isEqual:D18GetObject(preview, NSSelectorFromString(@"uuid"))]) return preview;
    return D18OriginalRequestForUUID(self, cmd, destination, uuid);
}

static unsigned int D18InstallPreviewRouting(id dispatcher) {
    if (D18RoutingClass) return [dispatcher isKindOfClass:D18RoutingClass] ? 0 : D18PreviewRoutingUnavailable;
    Class cls = object_getClass(dispatcher);
    const struct { const char *name; const char *args; char result; IMP hook; IMP *original; unsigned int error; } hooks[] = {
        {"destination:requestsClearingNotificationRequests:", "@@", 'v', (IMP)D18ClearRequests,
         (IMP *)&D18OriginalClearRequests, D18PreviewClearRequestsUnavailable},
        {"destination:requestsClearingNotificationRequests:fromDestinations:", "@@@", 'v', (IMP)D18ClearDestinations,
         (IMP *)&D18OriginalClearDestinations, D18PreviewClearDestinationsUnavailable},
        {"destination:requestsClearingNotificationRequestsInSections:", "@@", 'v', (IMP)D18ClearSections,
         (IMP *)&D18OriginalClearSections, D18PreviewClearSectionsUnavailable},
        {"destination:requestsClearingNotificationRequestsFromDate:toDate:inSections:", "@@@@", 'v', (IMP)D18ClearRange,
         (IMP *)&D18OriginalClearRange, D18PreviewClearRangeUnavailable},
        {"destination:notificationRequestForUUID:", "@@", '@', (IMP)D18RequestForUUID,
         (IMP *)&D18OriginalRequestForUUID, D18PreviewLookupUnavailable}
    };
    // Validate every ABI before installing any hook. Each clear call continues
    // through its original handler with the original arguments exactly once.
    // The additional work can affect only this controller's stored preview UUID.
    for (size_t i = 0; i < sizeof(hooks) / sizeof(hooks[0]); i++)
        if (!D18MethodMatches(cls, sel_registerName(hooks[i].name), hooks[i].result, hooks[i].args))
            return hooks[i].error;
    for (size_t i = 0; i < sizeof(hooks) / sizeof(hooks[0]); i++)
        MSHookMessageEx(cls, sel_registerName(hooks[i].name), hooks[i].hook, hooks[i].original);
    D18RoutingClass = cls;
    return 0;
}

static BOOL D18ConfigureObject(id object, NSDictionary<NSString *, id> *values) {
    if (!object) return NO;
    for (NSString *setter in values)
        if (!D18SetObject(object, NSSelectorFromString(setter), values[setter])) return NO;
    return YES;
}

static unsigned int D18PublishPreview(void) {
    id host = D18GetObject(UIApplication.sharedApplication, NSSelectorFromString(@"notificationDispatcher"));
    id dispatcher = D18GetObject(host, NSSelectorFromString(@"dispatcher"));
    for (NSString *name in @[@"postNotificationWithRequest:", @"withdrawNotificationWithRequest:",
                             @"modifyNotificationWithRequest:"])
        if (!D18MethodMatches(object_getClass(dispatcher), NSSelectorFromString(name), 'v', "@"))
            return D18PreviewDispatcherUnavailable;

    id banner = D18GetObject(host, NSSelectorFromString(@"bannerDestination"));
    id center = D18GetObject(host, NSSelectorFromString(@"dashBoardDestination"));
    id bannerID = D18GetObject(banner, NSSelectorFromString(@"identifier"));
    id centerID = D18GetObject(center, NSSelectorFromString(@"identifier"));
    if (![bannerID isKindOfClass:NSString.class] || ![centerID isKindOfClass:NSString.class])
        return D18PreviewDestinationsUnavailable;

    id request = [NSClassFromString(@"NCMutableNotificationRequest") new];
    id content = [NSClassFromString(@"NCMutableNotificationContent") new];
    id options = [NSClassFromString(@"NCMutableNotificationOptions") new];
    id alerts = [NSClassFromString(@"NCNotificationAlertOptions") new];
    id clearAction = [NSClassFromString(@"NCMutableNotificationAction") new];
    if (!request || !content || !options || !alerts || !clearAction) return D18PreviewClassesUnavailable;
    if (!D18Preview) D18Preview = [D18PreviewController new];
    NSDate *date = [NSDate date];
    NSUUID *uuid = [NSUUID UUID];
    if (!D18ConfigureObject(content, @{
        // header is a computed getter; the mutable class uses customHeader.
        @"setCustomHeader:": @"Dawn 18", @"setDefaultHeader:": @"Dawn 18",
        @"setTitle:": @"Appearance Preview", @"setDate:": date,
        @"setMessage:": @"This is a local test notification. Open Notification Center or long-press to preview its clear controls."
    })) return D18PreviewContentUnavailable;
    UIImage *icon = [UIImage imageWithContentsOfFile:@"/var/jb/Library/PreferenceBundles/Dawn18Prefs.bundle/icon@3x.png"];
    if (icon) D18SetObject(content, NSSelectorFromString(@"setIcon:"), icon);
    // This controls the banner's normal on-screen timeout, not the lifetime of
    // the saved card. Dawn 18 never schedules an expiry/automatic withdrawal.
    if (!D18SetFlag(options, @"setDismissAutomatically:", YES) ||
        !D18SetFlag(options, @"setAddToLockScreenWhenUnlocked:", YES) ||
        !D18SetFlag(options, @"setHideClearActionInList:", NO) ||
        !D18SetFlag(options, @"setCanPlaySound:", NO) ||
        !D18SetFlag(options, @"setCanTurnOnDisplay:", NO) ||
        !D18SetFlag(options, @"setRevealsAdditionalContentIfNoDefaultAction:", YES))
        return D18PreviewOptionsUnavailable;
    if (!D18ConfigureObject(clearAction, @{
        @"setIdentifier:": [@"com.brooktrout12.dawn18.preview.clear." stringByAppendingString:uuid.UUIDString],
        @"setTitle:": @"Clear", @"setActionRunner:": D18Preview
    }) || !D18SetFlag(clearAction, @"setShouldDismissNotification:", YES) ||
          !D18SetFlag(clearAction, @"setRequiresAuthentication:", NO)) return D18PreviewActionUnavailable;
    if (!D18ConfigureObject(request, @{
        @"setSectionIdentifier:": D18PreviewSection, @"setNotificationIdentifier:": uuid.UUIDString,
        @"setThreadIdentifier:": D18PreviewSection, @"setUuid:": uuid, @"setTimestamp:": date,
        @"setContent:": content, @"setOptions:": options, @"setAlertOptions:": alerts,
        @"setRequestDestinations:": [NSSet setWithObjects:bannerID, centerID,
                                     D18LockScreenDestination, D18NotificationCenterDestination, nil],
        @"setSubSectionIdentifiers:": [NSSet set], @"setSettingsSections:": [NSSet set],
        @"setClearAction:": clearAction, @"setCloseAction:": clearAction
    }) || !D18SetUnsignedInteger(request, @"setInterruptionLevel:", UNNotificationInterruptionLevelActive))
        return D18PreviewRequestUnavailable;

    unsigned int routingError = D18InstallPreviewRouting(dispatcher);
    if (routingError) return routingError;
    [D18Preview withdrawPreview:D18Preview.request];
    D18Preview.dispatcher = dispatcher;
    D18Preview.coverSheetIdentifier = centerID;
    D18Preview.request = [request copy];
    // Native SBUserAlertNotificationSource also posts/withdraws requests without
    // registering as a dispatcher source. No native-source getter or inventory
    // of its unrelated callback methods is needed for this preview.
    D18SetObject(dispatcher, NSSelectorFromString(@"postNotificationWithRequest:"), D18Preview.request);
    return D18PreviewSubmitted;
}

static void D18HandlePreviewRequest(void *context) {
    (void)context;
    @autoreleasepool {
        uint64_t state = 0;
        if (D18RequestToken < 0 || notify_get_state(D18RequestToken, &state) != NOTIFY_STATUS_OK) return;
        uint32_t requestID = (uint32_t)state;
        CFTimeInterval now = CFAbsoluteTimeGetCurrent();
        if (!requestID || requestID == D18LastRequest || now - D18LastRequestTime < 2.0) return;
        D18LastRequest = requestID;
        D18LastRequestTime = now;
        unsigned int result = D18PreviewFailed;
        @try { result = D18PublishPreview(); }
        @catch (NSException *exception) {
            (void)exception;
            // Roll back only our own preview if a private API rejected it.
            @try { [D18Preview withdrawPreview:D18Preview.request]; }
            @catch (NSException *cleanupException) { (void)cleanupException; }
        }
        if (D18ReplyToken >= 0) {
            notify_set_state(D18ReplyToken, D18PreviewReply(requestID, result));
            notify_post(D18_PREVIEW_REPLY);
        }
    }
}

static void D18PreviewRequested(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                const void *object, CFDictionaryRef info) {
    (void)center; (void)observer; (void)name; (void)object; (void)info;
    dispatch_async_f(dispatch_get_main_queue(), NULL, D18HandlePreviewRequest);
}

void D18StartNotificationPreview(void) {
    if (D18RequestToken >= 0) return;
    if (notify_register_check(D18_PREVIEW_REQUEST, &D18RequestToken) != NOTIFY_STATUS_OK) {
        D18RequestToken = -1;
        return;
    }
    if (notify_register_check(D18_PREVIEW_REPLY, &D18ReplyToken) != NOTIFY_STATUS_OK) {
        notify_cancel(D18RequestToken);
        D18RequestToken = D18ReplyToken = -1;
        return;
    }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), &D18PreviewObserver,
        D18PreviewRequested, CFSTR(D18_PREVIEW_REQUEST), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
