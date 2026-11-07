// CCFavorites -- Copyright (c) 2026 brooktrout12. MIT license.
// iOS 18, rootless, SpringBoard only. No preferences or layout-file changes.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#include <math.h>
#include <stdarg.h>
#include <string.h>
#include "BTRuntimeClassMatch.h"

static const char *const BTFolderClass = "_TtC15ControlCenterUI18IconListFolderView";
static const char *const BTRootFolderClass = "_TtC15ControlCenterUI22IconListRootFolderView";
static const char *const BTControllerClass = "_TtC15ControlCenterUI24IconListFolderController";
static const char *const BTRootControllerClass = "_TtC15ControlCenterUI28IconListRootFolderController";
static char BTApplyingKey, BTConfiguredKey, BTAutoScrollAssertionKey;

// Only hook methods with the expected complete ABI. Swift-internal methods
// are never called as guessed C functions. @? is a native block argument;
// replacements forward that pointer unchanged and never create/invoke blocks.
static void BTCanonicalType(const char *input, char *output, size_t capacity) {
    size_t n = 0;
    bool quoted = false;
    while (*input && strchr("rnNoORV", *input)) ++input;
    for (; *input && n + 1 < capacity; ++input) {
        if (*input == '"') { quoted = !quoted; continue; }
        if (!quoted) output[n++] = *input;
    }
    output[n] = 0;
}

static bool BTTypeIs(const char *actual, const char *expected) {
    char a[256], b[256];
    BTCanonicalType(actual, a, sizeof(a));
    BTCanonicalType(expected, b, sizeof(b));
    return strcmp(a, b) == 0;
}

static bool BTMethodMatches(Class cls, SEL selector, const char *result,
                            unsigned count, va_list arguments) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != count + 2) return false;
    char encoding[512];
    method_getReturnType(method, encoding, sizeof(encoding));
    if (!BTTypeIs(encoding, result)) return false;
    for (unsigned i = 0; i < count; ++i) {
        const char *expected = va_arg(arguments, const char *);
        method_getArgumentType(method, i + 2, encoding, sizeof(encoding));
        if (!BTTypeIs(encoding, expected)) return false;
    }
    return true;
}

static bool BTMethodIs(id object, SEL selector, const char *result, unsigned count, ...) {
    if (!object) return false;
    va_list arguments;
    va_start(arguments, count);
    bool match = BTMethodMatches(object_getClass(object), selector, result, count, arguments);
    va_end(arguments);
    return match;
}

static id BTObjectProperty(id object, const char *name) {
    SEL selector = sel_registerName(name);
    if (!BTMethodIs(object, selector, @encode(id), 0)) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static id BTObjectIvar(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(object, ivar) : nil;
}

static bool BTIsFolder(id object) {
    return BTNamedKind(object, BTFolderClass, BTRootFolderClass);
}

static id BTLoadedFolder(id controller) {
    if (BTIsFolder(controller)) return controller;
    if (!BTNamedKind(controller, BTControllerClass, BTRootControllerClass)) return nil;
    id folder = BTObjectProperty(controller, "folderViewIfLoaded");
    if (BTIsFolder(folder)) return folder;
    if ([controller isKindOfClass:[UIViewController class]]) {
        folder = ((UIViewController *)controller).viewIfLoaded;
        if (BTIsFolder(folder)) return folder;
    }
    return nil;
}

static UIScrollView *BTScrollView(id folder) {
    id scroll = BTObjectProperty(folder, "scrollView");
    if (![scroll isKindOfClass:[UIScrollView class]]) scroll = BTObjectIvar(folder, "_scrollView");
    return [scroll isKindOfClass:[UIScrollView class]] ? scroll : nil;
}

static id BTFolderForScroll(UIScrollView *scroll) {
    // Resolve ownership live. Gallery lists and expanded module scroll views
    // are not ControlCenterUI folder pagers and must retain normal scrolling.
    id delegate = scroll.delegate;
    if (BTIsFolder(delegate) && BTScrollView(delegate) == scroll) return delegate;
    UIView *parent = scroll.superview;
    for (unsigned depth = 0; parent && depth < 24; ++depth, parent = parent.superview) {
        if (BTIsFolder(parent) && BTScrollView(parent) == scroll) return parent;
    }
    return nil;
}

static long long BTFirstPage(id object) {
    // The first icon page is Favorites in the user's layout. Use the native
    // logical index, which can differ from zero when custom pages precede it.
    SEL selector = sel_registerName("firstIconPageIndex");
    if (BTMethodIs(object, selector, @encode(long long), 0)) {
        long long first = ((long long (*)(id, SEL))objc_msgSend)(object, selector);
        if (first >= 0 && first < 1000000) return first;
    }
    return 0;
}

static bool BTFolderReady(id folder) {
    if (!BTIsFolder(folder)) return false;
    SEL selector = sel_registerName("iconListViewCount");
    if (!BTMethodIs(folder, selector, @encode(unsigned long long), 0)) return false;
    return ((unsigned long long (*)(id, SEL))objc_msgSend)(folder, selector) > 0;
}

static long long BTTargetPage(id object, long long requested) {
    // Preserve native initialization/teardown sentinels. A restored non-first
    // page is brought home as soon as the populated folder completes layout.
    if (requested < 0 || !BTFolderReady(BTLoadedFolder(object))) return requested;
    return BTFirstPage(object);
}

static bool BTFirstOffset(id folder, CGPoint *point) {
    if (!BTFolderReady(folder)) return false;
    UIScrollView *scroll = BTScrollView(folder);
    if (!scroll || scroll.bounds.size.width <= 0 || scroll.bounds.size.height <= 0) return false;
    SEL selector = sel_registerName("_scrollOffsetForPageAtIndex:");
    if (!BTMethodIs(folder, selector, @encode(CGPoint), 1, @encode(long long))) return false;
    CGPoint target = ((CGPoint (*)(id, SEL, long long))objc_msgSend)(folder, selector, BTFirstPage(folder));
    if (!isfinite(target.x) || !isfinite(target.y)) return false;
    *point = target;
    return true;
}

static CGPoint BTConstrainedOffset(id folder, CGPoint proposed) {
    CGPoint target;
    // Native geometry accounts for orientation, spacing and content insets.
    // An unlaid-out view is left alone; never invent a zero offset for it.
    return BTFirstOffset(folder, &target) ? target : proposed;
}

static bool BTIsOurPageControl(UIView *view) {
    for (UIView *parent = view.superview; parent; parent = parent.superview) {
        if (BTIsFolder(parent)) return BTObjectProperty(parent, "pageControl") == view;
    }
    return false;
}

static void BTHidePageControl(id candidate) {
    if (![candidate isKindOfClass:[UIView class]]) return;
    UIView *view = candidate;
    if (!view.hidden) view.hidden = YES;
    if (view.alpha != 0) view.alpha = 0;
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    if (!view.accessibilityElementsHidden) view.accessibilityElementsHidden = YES;
    if (view.isAccessibilityElement) view.isAccessibilityElement = NO;
}

static void BTDisableScrolling(UIScrollView *scroll) {
    if (!scroll) return;
    if (scroll.scrollEnabled) scroll.scrollEnabled = NO;
    if (scroll.bounces) scroll.bounces = NO;
    if (scroll.alwaysBounceVertical) scroll.alwaysBounceVertical = NO;
    if (scroll.alwaysBounceHorizontal) scroll.alwaysBounceHorizontal = NO;
    if (scroll.scrollsToTop) scroll.scrollsToTop = NO;
    if (scroll.panGestureRecognizer.enabled) scroll.panGestureRecognizer.enabled = NO;
}

static void BTApplyFolder(id folder) {
    if (!BTIsFolder(folder) || objc_getAssociatedObject(folder, &BTApplyingKey)) return;
    objc_setAssociatedObject(folder, &BTApplyingKey, [NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        // These are UI properties/assertions, not the folder's saved model.
        if (!objc_getAssociatedObject(folder, &BTConfiguredKey)) {
            SEL hide = sel_registerName("setPageControlHidden:");
            if (BTMethodIs(folder, hide, @encode(void), 1, @encode(bool)))
                ((void (*)(id, SEL, bool))objc_msgSend)(folder, hide, true);
            SEL disable = sel_registerName("_setScrollingDisabled:forReason:");
            if (BTMethodIs(folder, disable, @encode(void), 2, @encode(bool), @encode(id)))
                ((void (*)(id, SEL, bool, id))objc_msgSend)(folder, disable, true, @"com.brooktrout12.ccfavorites");
            objc_setAssociatedObject(folder, &BTConfiguredKey, [NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        BTHidePageControl(BTObjectProperty(folder, "pageControl"));

        // Keep the native assertion alive to stop edit-mode edge autoscroll.
        // It is released along with its associated folder view.
        SEL autoScroll = sel_registerName("disableAutoScrollForReason:");
        if (!objc_getAssociatedObject(folder, &BTAutoScrollAssertionKey) &&
            BTMethodIs(folder, autoScroll, @encode(id), 1, @encode(id))) {
            id assertion = ((id (*)(id, SEL, id))objc_msgSend)(folder, autoScroll, @"com.brooktrout12.ccfavorites");
            if (assertion) objc_setAssociatedObject(folder, &BTAutoScrollAssertionKey, assertion,
                                                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        UIScrollView *scroll = BTScrollView(folder);
        BTDisableScrolling(scroll);
        if (BTFolderReady(folder)) {
            SEL current = sel_registerName("currentPageIndex");
            SEL move = sel_registerName("setCurrentPageIndex:animated:");
            long long first = BTFirstPage(folder);
            if (BTMethodIs(folder, current, @encode(long long), 0) &&
                BTMethodIs(folder, move, @encode(bool), 2, @encode(long long), @encode(bool)) &&
                ((long long (*)(id, SEL))objc_msgSend)(folder, current) != first)
                ((bool (*)(id, SEL, long long, bool))objc_msgSend)(folder, move, first, false);
            CGPoint target;
            if (BTFirstOffset(folder, &target) && !CGPointEqualToPoint(scroll.contentOffset, target))
                [scroll setContentOffset:target animated:NO];
        }
    } @finally {
        objc_setAssociatedObject(folder, &BTApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void BTApplyController(UIViewController *controller, unsigned depth) {
    if (!controller || depth > 8) return;
    BTApplyFolder(BTLoadedFolder(controller));
    for (UIViewController *child in controller.childViewControllers)
        BTApplyController(child, depth + 1);
}

static bool BTIsPageScrollGesture(id controller, id gesture) {
    return gesture && gesture == BTObjectIvar(controller, "_pagingViewScrollPanGesture");
}

static void BTApplyMain(id controller) {
    // iOS 18.6 exports separate scrolling and dismissal recognizer ivars.
    // Only the scrolling recognizer is disabled. Presentation, dismissal,
    // the editing long press and gestures inside modules remain native.
    id gesture = BTObjectIvar(controller, "_pagingViewScrollPanGesture");
    if ([gesture isKindOfClass:[UIGestureRecognizer class]] && ((UIGestureRecognizer *)gesture).enabled)
        ((UIGestureRecognizer *)gesture).enabled = NO;
    id pager = BTObjectIvar(controller, "_pagingViewController");
    if ([pager isKindOfClass:[UIViewController class]]) BTApplyController(pager, 0);
}

// Each class/selector pair has its own typed original. Separate replacements
// are essential when both a CCUI subclass and its superclass call through.
#define BT_PAGE_METHODS(tag) \
    static long long (*BTOrig_##tag##Default)(id, SEL); \
    static long long BTHook_##tag##Default(id self, SEL cmd) { \
        (void)cmd; return BTFirstPage(self); \
    } \
    static bool (*BTOrig_##tag##Animated)(id, SEL, long long, bool); \
    static bool BTHook_##tag##Animated(id self, SEL cmd, long long page, bool animated) { \
        long long target = BTTargetPage(self, page); \
        return BTOrig_##tag##Animated(self, cmd, target, page == target && animated); \
    } \
    static bool (*BTOrig_##tag##Completion)(id, SEL, long long, bool, id); \
    static bool BTHook_##tag##Completion(id self, SEL cmd, long long page, bool animated, id completion) { \
        long long target = BTTargetPage(self, page); \
        return BTOrig_##tag##Completion(self, cmd, target, page == target && animated, completion); \
    } \
    static void (*BTOrig_##tag##Decelerate)(id, SEL, long long, id); \
    static void BTHook_##tag##Decelerate(id self, SEL cmd, long long page, id completion) { \
        BTOrig_##tag##Decelerate(self, cmd, BTTargetPage(self, page), completion); \
    }

#define BT_FOLDER_METHODS(tag) \
    BT_PAGE_METHODS(tag) \
    static void (*BTOrig_##tag##Layout)(id, SEL); \
    static void BTHook_##tag##Layout(id self, SEL cmd) { \
        BTOrig_##tag##Layout(self, cmd); BTApplyFolder(self); \
    } \
    static void (*BTOrig_##tag##Window)(id, SEL); \
    static void BTHook_##tag##Window(id self, SEL cmd) { \
        BTOrig_##tag##Window(self, cmd); BTApplyFolder(self); \
    } \
    static void (*BTOrig_##tag##Index)(id, SEL, long long); \
    static void BTHook_##tag##Index(id self, SEL cmd, long long page) { \
        BTOrig_##tag##Index(self, cmd, BTTargetPage(self, page)); \
    } \
    static void (*BTOrig_##tag##Deferred)(id, SEL, long long, bool); \
    static void BTHook_##tag##Deferred(id self, SEL cmd, long long page, bool defer) { \
        BTOrig_##tag##Deferred(self, cmd, BTTargetPage(self, page), defer); \
    } \
    static bool (*BTOrig_##tag##CanChange)(id, SEL, unsigned long long); \
    static bool BTHook_##tag##CanChange(id self, SEL cmd, unsigned long long page) { \
        return (!BTFolderReady(self) || page == (unsigned long long)BTFirstPage(self)) && \
               BTOrig_##tag##CanChange(self, cmd, page); \
    } \
    static void (*BTOrig_##tag##Offset)(id, SEL, CGPoint, bool); \
    static void BTHook_##tag##Offset(id self, SEL cmd, CGPoint point, bool animated) { \
        CGPoint target = BTConstrainedOffset(self, point); \
        BTOrig_##tag##Offset(self, cmd, target, CGPointEqualToPoint(point, target) && animated); \
    } \
    static bool (*BTOrig_##tag##Hidden)(id, SEL); \
    static bool BTHook_##tag##Hidden(id self, SEL cmd) { (void)self; (void)cmd; return true; } \
    static void (*BTOrig_##tag##SetHidden)(id, SEL, bool); \
    static void BTHook_##tag##SetHidden(id self, SEL cmd, bool hidden) { \
        (void)hidden; BTOrig_##tag##SetHidden(self, cmd, true); \
    } \
    static void (*BTOrig_##tag##Alpha)(id, SEL, double); \
    static void BTHook_##tag##Alpha(id self, SEL cmd, double alpha) { \
        (void)alpha; BTOrig_##tag##Alpha(self, cmd, 0); \
    }

#define BT_CONTROLLER_METHODS(tag) \
    BT_PAGE_METHODS(tag) \
    static void (*BTOrig_##tag##Index)(id, SEL, long long); \
    static void BTHook_##tag##Index(id self, SEL cmd, long long page) { \
        BTOrig_##tag##Index(self, cmd, BTTargetPage(self, page)); \
    } \
    static bool (*BTOrig_##tag##CanChange)(id, SEL, id, long long); \
    static bool BTHook_##tag##CanChange(id self, SEL cmd, id folder, long long page) { \
        return (BTTargetPage(self, page) == page) && BTOrig_##tag##CanChange(self, cmd, folder, page); \
    } \
    static void (*BTOrig_##tag##Layout)(id, SEL); \
    static void BTHook_##tag##Layout(id self, SEL cmd) { \
        BTOrig_##tag##Layout(self, cmd); BTApplyFolder(BTLoadedFolder(self)); \
    } \
    static void (*BTOrig_##tag##Appear)(id, SEL, BOOL); \
    static void BTHook_##tag##Appear(id self, SEL cmd, BOOL animated) { \
        BTOrig_##tag##Appear(self, cmd, animated); BTApplyFolder(BTLoadedFolder(self)); \
    }

BT_FOLDER_METHODS(Folder)
BT_FOLDER_METHODS(RootFolder)
BT_CONTROLLER_METHODS(Controller)
BT_CONTROLLER_METHODS(RootController)

static void (*BTOrig_ScrollEnabled)(id, SEL, BOOL);
static void BTHook_ScrollEnabled(id self, SEL cmd, BOOL enabled) {
    BTOrig_ScrollEnabled(self, cmd, BTFolderForScroll(self) ? NO : enabled);
}

static void (*BTOrig_ScrollOffset)(id, SEL, CGPoint);
static void BTHook_ScrollOffset(id self, SEL cmd, CGPoint point) {
    BTOrig_ScrollOffset(self, cmd, BTConstrainedOffset(BTFolderForScroll(self), point));
}

static void (*BTOrig_ScrollAnimated)(id, SEL, CGPoint, BOOL);
static void BTHook_ScrollAnimated(id self, SEL cmd, CGPoint point, BOOL animated) {
    CGPoint target = BTConstrainedOffset(BTFolderForScroll(self), point);
    BTOrig_ScrollAnimated(self, cmd, target, CGPointEqualToPoint(point, target) && animated);
}

static void (*BTOrig_ScrollDecelerate)(id, SEL, CGPoint);
static void BTHook_ScrollDecelerate(id self, SEL cmd, CGPoint point) {
    BTOrig_ScrollDecelerate(self, cmd, BTConstrainedOffset(BTFolderForScroll(self), point));
}

static void (*BTOrig_ScrollAuto)(id, SEL, CGPoint);
static void BTHook_ScrollAuto(id self, SEL cmd, CGPoint point) {
    BTOrig_ScrollAuto(self, cmd, BTConstrainedOffset(BTFolderForScroll(self), point));
}

static void (*BTOrig_PageHidden)(id, SEL, BOOL);
static void BTHook_PageHidden(id self, SEL cmd, BOOL hidden) {
    BTOrig_PageHidden(self, cmd, BTIsOurPageControl(self) ? YES : hidden);
}

static void (*BTOrig_PageAlpha)(id, SEL, CGFloat);
static void BTHook_PageAlpha(id self, SEL cmd, CGFloat alpha) {
    BTOrig_PageAlpha(self, cmd, BTIsOurPageControl(self) ? 0 : alpha);
}

static void (*BTOrig_MainLayout)(id, SEL);
static void BTHook_MainLayout(id self, SEL cmd) {
    BTOrig_MainLayout(self, cmd); BTApplyMain(self);
}

static void (*BTOrig_MainAppear)(id, SEL, BOOL);
static void BTHook_MainAppear(id self, SEL cmd, BOOL animated) {
    BTOrig_MainAppear(self, cmd, animated); BTApplyMain(self);
}

static BOOL (*BTOrig_MainGesture)(id, SEL, id);
static BOOL BTHook_MainGesture(id self, SEL cmd, id gesture) {
    return BTIsPageScrollGesture(self, gesture) ? NO : BTOrig_MainGesture(self, cmd, gesture);
}

static void (*BTOrig_PagerLayout)(id, SEL);
static void BTHook_PagerLayout(id self, SEL cmd) {
    BTOrig_PagerLayout(self, cmd); BTApplyController(self, 0);
}

static void (*BTOrig_PagerAppear)(id, SEL, BOOL);
static void BTHook_PagerAppear(id self, SEL cmd, BOOL animated) {
    BTOrig_PagerAppear(self, cmd, animated); BTApplyController(self, 0);
}

static void BTInstall(const char *className, const char *selectorName, IMP replacement,
                      IMP *original, const char *result, unsigned count, ...) {
    if (*original) return;
    Class cls = objc_getClass(className);
    SEL selector = sel_registerName(selectorName);
    va_list arguments;
    va_start(arguments, count);
    bool match = cls && BTMethodMatches(cls, selector, result, count, arguments);
    va_end(arguments);
    if (match) MSHookMessageEx(cls, selector, replacement, original);
}

#define BT_HOOK(cls, selector, tag, result, count, ...) \
    BTInstall(cls, selector, (IMP)BTHook_##tag, (IMP *)&BTOrig_##tag, result, count, ##__VA_ARGS__)

#define BT_INSTALL_PAGES(cls, tag) \
    BT_HOOK(cls, "defaultPageIndex", tag##Default, @encode(long long), 0); \
    BT_HOOK(cls, "setCurrentPageIndex:animated:", tag##Animated, @encode(bool), 2, @encode(long long), @encode(bool)); \
    BT_HOOK(cls, "setCurrentPageIndex:animated:completion:", tag##Completion, @encode(bool), 3, @encode(long long), @encode(bool), "@?"); \
    BT_HOOK(cls, "scrollUsingDecelerationAnimationToPageIndex:withCompletionHandler:", tag##Decelerate, @encode(void), 2, @encode(long long), "@?")

#define BT_INSTALL_FOLDER(cls, tag) \
    BT_INSTALL_PAGES(cls, tag); \
    BT_HOOK(cls, "layoutSubviews", tag##Layout, @encode(void), 0); \
    BT_HOOK(cls, "didMoveToWindow", tag##Window, @encode(void), 0); \
    BT_HOOK(cls, "_setCurrentPageIndex:", tag##Index, @encode(void), 1, @encode(long long)); \
    BT_HOOK(cls, "_setCurrentPageIndex:deferringPageControlUpdate:", tag##Deferred, @encode(void), 2, @encode(long long), @encode(bool)); \
    BT_HOOK(cls, "canChangeCurrentPageIndexToIndex:", tag##CanChange, @encode(bool), 1, @encode(unsigned long long)); \
    BT_HOOK(cls, "_setScrollViewContentOffset:animated:", tag##Offset, @encode(void), 2, @encode(CGPoint), @encode(bool)); \
    BT_HOOK(cls, "isPageControlHidden", tag##Hidden, @encode(bool), 0); \
    BT_HOOK(cls, "setPageControlHidden:", tag##SetHidden, @encode(void), 1, @encode(bool)); \
    BT_HOOK(cls, "setPageControlAlpha:", tag##Alpha, @encode(void), 1, @encode(double))

#define BT_INSTALL_CONTROLLER(cls, tag) \
    BT_INSTALL_PAGES(cls, tag); \
    BT_HOOK(cls, "setCurrentPageIndex:", tag##Index, @encode(void), 1, @encode(long long)); \
    BT_HOOK(cls, "folderView:canChangeCurrentPageIndexToIndex:", tag##CanChange, @encode(bool), 2, @encode(id), @encode(long long)); \
    BT_HOOK(cls, "viewDidLayoutSubviews", tag##Layout, @encode(void), 0); \
    BT_HOOK(cls, "viewWillAppear:", tag##Appear, @encode(void), 1, @encode(BOOL))

static void BTInstallHooks(void) {
    BT_INSTALL_FOLDER(BTFolderClass, Folder);
    BT_INSTALL_FOLDER(BTRootFolderClass, RootFolder);
    BT_INSTALL_CONTROLLER(BTControllerClass, Controller);
    BT_INSTALL_CONTROLLER(BTRootControllerClass, RootController);
    BT_HOOK("CCUIIconScrollView", "setScrollEnabled:", ScrollEnabled, @encode(void), 1, @encode(BOOL));
    BT_HOOK("CCUIIconScrollView", "setContentOffset:", ScrollOffset, @encode(void), 1, @encode(CGPoint));
    BT_HOOK("CCUIIconScrollView", "setContentOffset:animated:", ScrollAnimated, @encode(void), 2, @encode(CGPoint), @encode(BOOL));
    BT_HOOK("CCUIIconScrollView", "_setContentOffsetWithDecelerationAnimation:", ScrollDecelerate, @encode(void), 1, @encode(CGPoint));
    BT_HOOK("CCUIIconScrollView", "_autoScrollAssistantUpdateContentOffset:", ScrollAuto, @encode(void), 1, @encode(CGPoint));
    // SBIconListPageControl is shared. These two hooks require its current
    // Control Center folder owner; Home Screen page dots pass through intact.
    BT_HOOK("SBIconListPageControl", "setHidden:", PageHidden, @encode(void), 1, @encode(BOOL));
    BT_HOOK("SBIconListPageControl", "setAlpha:", PageAlpha, @encode(void), 1, @encode(CGFloat));
    BT_HOOK("CCUIMainViewController", "viewDidLayoutSubviews", MainLayout, @encode(void), 0);
    BT_HOOK("CCUIMainViewController", "viewWillAppear:", MainAppear, @encode(void), 1, @encode(BOOL));
    BT_HOOK("CCUIMainViewController", "gestureRecognizerShouldBegin:", MainGesture, @encode(BOOL), 1, @encode(id));
    BT_HOOK("CCUIPagingViewController", "viewDidLayoutSubviews", PagerLayout, @encode(void), 0);
    BT_HOOK("CCUIPagingViewController", "viewWillAppear:", PagerAppear, @encode(void), 1, @encode(BOOL));
}

static volatile int BTInstallQueued;
static void BTInstallOnMainQueue(void *context) {
    (void)context;
    __sync_lock_test_and_set(&BTInstallQueued, 0);
    @autoreleasepool { BTInstallHooks(); }
}

static void BTImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    if (__sync_bool_compare_and_swap(&BTInstallQueued, 0, 1))
        dispatch_async_f(dispatch_get_main_queue(), NULL, BTInstallOnMainQueue);
}

__attribute__((constructor)) static void BTInitialize(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
            [NSProcessInfo processInfo].operatingSystemVersion.majorVersion != 18) return;
        BTInstallHooks();
        _dyld_register_func_for_add_image(BTImageAdded);
    }
}
