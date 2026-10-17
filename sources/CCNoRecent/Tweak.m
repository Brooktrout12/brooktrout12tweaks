#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <string.h>
#include <stdarg.h>

#define CCN_VERSION @"1.0.0"
#define CCN_LOG @"/var/mobile/Library/Logs/CCNoRecent.log"

// Scope: the two Control Center attribution controls, plus their header owner.
// Never replace UIView/UIControl methods globally or alter sensor data sources.
typedef struct {
    const char *name;
    __unsafe_unretained Class cls;
    IMP layout;
    IMP moved;
    IMP hidden;
    IMP alpha;
    bool installed;
    bool missingReported;
    bool failedReported;
    bool instanceReported;
} CCNTarget;

static CCNTarget ccnCompact = { .name = "CCUISensorAttributionCompactControl" };
static CCNTarget ccnPrivacy = { .name = "CCUIPrivacyAttributionButton" };
static CCNTarget ccnHeader = { .name = "CCUIHeaderPocketView" };
static IMP ccnOriginalDisplaying;
static bool ccnStarted;
static bool ccnHasCompactGetter, ccnHasPrivacyGetter;
static atomic_bool ccnInstallQueued;
static atomic_bool ccnAllInstalled;

static void CCNLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void CCNLog(NSString *format, ...) {
    va_list args;
    va_start(args,format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[CCNoRecent] %@",message);
    @try {
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm createDirectoryAtPath:CCN_LOG.stringByDeletingLastPathComponent
            withIntermediateDirectories:YES attributes:nil error:NULL];
        NSDictionary *attributes = [fm attributesOfItemAtPath:CCN_LOG error:NULL];
        if ([attributes[NSFileSize] unsignedLongLongValue] > 32768)
            [fm removeItemAtPath:CCN_LOG error:NULL];
        if (![fm fileExistsAtPath:CCN_LOG]) [fm createFileAtPath:CCN_LOG contents:nil attributes:nil];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:CCN_LOG];
        [handle seekToEndOfFile];
        [handle writeData:[[NSString stringWithFormat:@"%@ %@\n",NSDate.date,message]
            dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    } @catch (__unused NSException *exception) {}
}

static bool CCNTypeMatches(const char *actual, char expected) {
    while (*actual && strchr("rnNoORV",*actual)) ++actual;
    return expected == 'B' ? (*actual == 'B' || *actual == 'c') : *actual == expected;
}

// Signature is return type followed by explicit arguments, e.g. "vB".
// Both devices use the 64-bit CGFloat (double) ABI.
static bool CCNMethodMatches(Class cls, const char *name, const char *signature) {
    Method method = cls ? class_getInstanceMethod(cls,sel_registerName(name)) : NULL;
    if (!method || method_getNumberOfArguments(method) != strlen(signature)+1) return false;
    char type[128];
    method_getReturnType(method,type,sizeof(type));
    if (!CCNTypeMatches(type,signature[0])) return false;
    for (unsigned i = 1; signature[i]; ++i) {
        method_getArgumentType(method,i+1,type,sizeof(type));
        if (!CCNTypeMatches(type,signature[i])) return false;
    }
    return true;
}

static void CCNHide(UIView *view, CCNTarget *target) {
    if (!view.hidden) view.hidden = YES;
    if (view.alpha != 0) view.alpha = 0;
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    if (!view.accessibilityElementsHidden) view.accessibilityElementsHidden = YES;
    view.isAccessibilityElement = NO;
    if (view.window && !target->instanceReported) {
        target->instanceReported = true;
        CCNLog(@"Hidden visible instance: %s",target->name);
    }
}

// Per-class wrappers retain their own original IMPs. MSHookMessageEx installs
// inherited UIView setters on the concrete CC class, not on UIView itself.
#define CCN_CONTROL_WRAPPERS(prefix, target) \
static void prefix##Layout(id self, SEL cmd) { \
    ((void (*)(id,SEL))target.layout)(self,cmd); CCNHide(self,&target); \
} \
static void prefix##Moved(id self, SEL cmd) { \
    ((void (*)(id,SEL))target.moved)(self,cmd); CCNHide(self,&target); \
} \
static void prefix##Hidden(id self, SEL cmd, BOOL hidden) { \
    (void)hidden; ((void (*)(id,SEL,BOOL))target.hidden)(self,cmd,YES); \
} \
static void prefix##Alpha(id self, SEL cmd, CGFloat alpha) { \
    (void)alpha; ((void (*)(id,SEL,CGFloat))target.alpha)(self,cmd,0); \
}

CCN_CONTROL_WRAPPERS(CCNCompact,ccnCompact)
CCN_CONTROL_WRAPPERS(CCNPrivacy,ccnPrivacy)

static void CCNHideHeaderChildren(id header) {
    // These accessors are present in the inspected 18.2 header. Each is checked
    // at runtime; no private ivar offsets or unchecked KVC are used.
    if (ccnHasCompactGetter) {
        id control = ((id (*)(id,SEL))objc_msgSend)(header,sel_registerName("compactSensorAttributionControl"));
        if (ccnCompact.installed && [control isKindOfClass:ccnCompact.cls]) CCNHide(control,&ccnCompact);
    }
    if (ccnHasPrivacyGetter) {
        id control = ((id (*)(id,SEL))objc_msgSend)(header,sel_registerName("privacyAttributionButton"));
        if (ccnPrivacy.installed && [control isKindOfClass:ccnPrivacy.cls]) CCNHide(control,&ccnPrivacy);
    }
    if (!ccnHeader.instanceReported) {
        ccnHeader.instanceReported = true;
        CCNLog(@"Control Center header observed; compact hooks=%d privacy hooks=%d",
            ccnCompact.installed,ccnPrivacy.installed);
    }
}

static void CCNHeaderLayout(id self, SEL cmd) {
    ((void (*)(id,SEL))ccnHeader.layout)(self,cmd);
    CCNHideHeaderChildren(self);
}

static void CCNHeaderMoved(id self, SEL cmd) {
    ((void (*)(id,SEL))ccnHeader.moved)(self,cmd);
    CCNHideHeaderChildren(self);
}

static BOOL CCNHeaderDisplaying(id self, SEL cmd) {
    if (!ccnCompact.installed && !ccnPrivacy.installed)
        return ((BOOL (*)(id,SEL))ccnOriginalDisplaying)(self,cmd);
    // UI visibility bookkeeping only. Native privacy tracking stays intact.
    return NO;
}

static bool CCNPrepareTarget(CCNTarget *target, bool control) {
    if (target->installed) return false;
    Class cls = objc_getClass(target->name);
    if (!cls) {
        if (!target->missingReported) {
            target->missingReported = true;
            CCNLog(@"Waiting for class: %s",target->name);
        }
        return false;
    }
    target->cls = cls;
    bool valid = [cls isSubclassOfClass:UIView.class]
        && CCNMethodMatches(cls,"layoutSubviews","v")
        && CCNMethodMatches(cls,"didMoveToWindow","v")
        && (!control || (CCNMethodMatches(cls,"setHidden:","vB")
                     && CCNMethodMatches(cls,"setAlpha:","vd")));
    if (!valid && !target->failedReported) {
        target->failedReported = true;
        CCNLog(@"Skipped unexpected class/method ABI: %s",target->name);
    }
    return valid;
}

static void CCNInstallControl(CCNTarget *target, IMP layout, IMP moved, IMP hidden, IMP alpha) {
    if (!CCNPrepareTarget(target,true)) return;
    MSHookMessageEx(target->cls,sel_registerName("layoutSubviews"),layout,&target->layout);
    MSHookMessageEx(target->cls,sel_registerName("didMoveToWindow"),moved,&target->moved);
    MSHookMessageEx(target->cls,sel_registerName("setHidden:"),hidden,&target->hidden);
    MSHookMessageEx(target->cls,sel_registerName("setAlpha:"),alpha,&target->alpha);
    target->installed = true;
    CCNLog(@"Installed visibility hooks: %s",target->name);
}

static void CCNInstall(void *context) {
    (void)context;
    atomic_store_explicit(&ccnInstallQueued,false,memory_order_release);
    @autoreleasepool {
        if (!ccnStarted) {
            ccnStarted = true;
            CCNLog(@"CCNoRecent %@ loaded in SpringBoard; %@",CCN_VERSION,
                NSProcessInfo.processInfo.operatingSystemVersionString);
        }
        CCNInstallControl(&ccnCompact,(IMP)CCNCompactLayout,(IMP)CCNCompactMoved,
            (IMP)CCNCompactHidden,(IMP)CCNCompactAlpha);
        CCNInstallControl(&ccnPrivacy,(IMP)CCNPrivacyLayout,(IMP)CCNPrivacyMoved,
            (IMP)CCNPrivacyHidden,(IMP)CCNPrivacyAlpha);
        if (CCNPrepareTarget(&ccnHeader,false)) {
            ccnHasCompactGetter = CCNMethodMatches(ccnHeader.cls,"compactSensorAttributionControl","@");
            ccnHasPrivacyGetter = CCNMethodMatches(ccnHeader.cls,"privacyAttributionButton","@");
            MSHookMessageEx(ccnHeader.cls,sel_registerName("layoutSubviews"),(IMP)CCNHeaderLayout,&ccnHeader.layout);
            MSHookMessageEx(ccnHeader.cls,sel_registerName("didMoveToWindow"),(IMP)CCNHeaderMoved,&ccnHeader.moved);
            if (CCNMethodMatches(ccnHeader.cls,"isDisplayingSensorStatus","B"))
                MSHookMessageEx(ccnHeader.cls,sel_registerName("isDisplayingSensorStatus"),
                    (IMP)CCNHeaderDisplaying,&ccnOriginalDisplaying);
            ccnHeader.installed = true;
            CCNLog(@"Installed header hooks; compact getter=%d privacy getter=%d visibility getter=%d",
                ccnHasCompactGetter,ccnHasPrivacyGetter,ccnOriginalDisplaying != NULL);
        }
        if (ccnCompact.installed && ccnPrivacy.installed && ccnHeader.installed)
            atomic_store_explicit(&ccnAllInstalled,true,memory_order_release);
    }
}

static void CCNScheduleInstall(void) {
    if (atomic_load_explicit(&ccnAllInstalled,memory_order_acquire)) return;
    if (!atomic_exchange_explicit(&ccnInstallQueued,true,memory_order_acq_rel))
        dispatch_async_f(dispatch_get_main_queue(),NULL,CCNInstall);
}

static void CCNImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    // dyld callbacks may run under its loader lock. Only enqueue; do Objective-C
    // discovery and hooking later on the main thread. This also handles CC
    // frameworks first loaded well after SpringBoard's initial startup.
    CCNScheduleInstall();
}

__attribute__((constructor)) static void CCNInitialize(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]
            || ![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
        NSInteger major = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
        if (major < 17 || major > 18) return;
        _dyld_register_func_for_add_image(CCNImageAdded);
        CCNScheduleInstall();
    }
}
