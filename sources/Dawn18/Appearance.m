#import "Compatibility.h"
// Dawn 18 — Brooktrout12. Original implementation; no Dawn/Cephei code.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <substrate.h>
#import <pthread.h>
#import <limits.h>
#import "Preferences.h"
#import "Runtime.h"
#if !D18_APPLICATIONS
#import "Preview.h"
#import "ClassicMenu.h"
#endif

static D18Configuration D18Config;
static char D18StateKey, D18ApplyingKey;
static BOOL D18RefreshQueued;

// Both libraries may be mapped before the process guard runs. Give compiled
// observer classes distinct names to avoid duplicate Objective-C classes.
#if D18_APPLICATIONS
#define D18LifecycleObserver D18AppsLifecycleObserver
#else
#define D18LifecycleObserver D18SpringBoardLifecycleObserver
#endif
@interface D18LifecycleObserver : NSObject
- (void)appearanceContextChanged:(NSNotification *)notification;
@end
static D18LifecycleObserver *D18Observer;

static void (*D18OriginalViewSetStyle)(id, SEL, UIUserInterfaceStyle);
static void (*D18OriginalControllerSetStyle)(id, SEL, UIUserInterfaceStyle);
static void (*D18OriginalViewWillAppear)(id, SEL, BOOL);
static void (*D18OriginalViewDidLoad)(id, SEL);

#if !D18_APPLICATIONS
static void (*D18OriginalDidMoveToWindow)(id, SEL);
static void (*D18OriginalDidMoveToSuperview)(id, SEL);
static CFMutableDictionaryRef D18ClassKinds;
static void (*D18OriginalCreateMenuView)(id, SEL, id);
static void (*D18OriginalMenuListLayout)(id, SEL);
static char D18IconMenuKey, D18NotificationOptionsMenuKey;
static Class D18IconViewClass;
static void D18Apply(id object, BOOL isController);
static BOOL D18IsNotificationOptionsSource(UIView *view);

static D18Element D18RawElement(id object) {
    if (!object) return D18None;
    Class initialClass = object_getClass(object);
    const void *key = (__bridge const void *)initialClass;
    const void *cached = CFDictionaryGetValue(D18ClassKinds, key);
    if (cached) return (D18Element)((intptr_t)cached - 2);
    D18Element result = D18None;
    for (Class cls = initialClass; cls; cls = class_getSuperclass(cls)) {
        result = D18ElementForClassName(class_getName(cls));
        if (result != D18None) break;
    }
    CFDictionarySetValue(D18ClassKinds, key, (const void *)(intptr_t)(result + 2));
    return result;
}

static BOOL D18ObjectIsBannerContext(id object) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls))
        if (D18IsBannerContext(class_getName(cls))) return YES;
    return NO;
}

static BOOL D18NotificationOwnerIsBanner(id owner) {
    // iOS presents the expanded platter outside the short-look hierarchy.
    // Its delegate is the originating short-look controller, whose delegate
    // identifies the destination. Long-look controllers use that destination
    // directly. Follow only notification controllers, never arbitrary delegates.
    for (NSUInteger depth = 0; owner && depth < 8; depth++) {
        if (D18ObjectIsBannerContext(owner)) return YES;
        if (![owner isKindOfClass:UIViewController.class] ||
            D18RawElement(owner) != D18NotificationSurface) return NO;
        id next = D18GetObject(owner, NSSelectorFromString(@"delegate"));
        if (next == owner) return NO;
        owner = next;
    }
    return NO;
}

static BOOL D18HasContext(UIView *view, UIViewController *controller, BOOL banner) {
    // A notification card class is reused for banners and Notification Center.
    // Inspect the owning hierarchy instead of imposing one global card style.
    UIViewController *owner = controller;
    UIView *current = view;
    for (NSUInteger depth = 0; current && depth < 128; depth++, current = current.superview) {
        if (banner ? D18ObjectIsBannerContext(current) : D18RawElement(current) == D18AppLibrary)
            return YES;
        UIResponder *responder = current.nextResponder;
        if (!owner && [responder isKindOfClass:UIViewController.class]) owner = (id)responder;
    }
    for (NSUInteger depth = 0; owner && depth < 64; depth++, owner = owner.parentViewController) {
        if (banner ? D18NotificationOwnerIsBanner(owner) : D18RawElement(owner) == D18AppLibrary)
            return YES;
    }
    return NO;
}

static D18Element D18ResolveElement(id object, BOOL isController) {
    if (!isController && objc_getAssociatedObject(object, &D18IconMenuKey)) return D18QuickActions;
    if (!isController && objc_getAssociatedObject(object, &D18NotificationOptionsMenuKey)) return D18Notifications;
    D18Element element = D18RawElement(object);
    UIViewController *controller = isController ? object : nil;
    UIView *view = isController ? (controller.isViewLoaded ? controller.view : nil) : object;
    // iOS 18 explicitly sets the closed tile's background appearance from its
    // icon-material traits. The background may be a generic UIView/material,
    // so class names alone miss it. Match the owner's actual backgroundView.
    // Do not override SBFolderIconImageView itself or its mini-app-icon grid.
    if (!isController && element == D18None &&
        D18RawElement(view.superview) == D18FolderIconSurface &&
        D18GetObject(view.superview, NSSelectorFromString(@"backgroundView")) == view)
        element = D18Folders;
    // The swipe buttons on iOS 18 are shared PlatterKit views, not the older
    // NCNotificationListCellActionButton. Include their actual material child
    // as well, without assigning all MTMaterialView/UIButton instances a theme.
    if (!isController && element == D18None &&
        D18RawElement(view.superview) == D18PlatterActionSurface &&
        D18GetObject(view.superview, NSSelectorFromString(@"backgroundView")) == view)
        element = D18PlatterActionSurface;
    if (element == D18PlatterActionSurface)
        return !isController && D18IsNotificationOptionsSource(view.superview) ?
            D18Notifications : D18None;
    if (element == D18None || element == D18FolderIconSurface) return D18None;
    if (element == D18NotificationSurface)
        return D18HasContext(view, controller, YES) ? D18Banners : D18Notifications;
    // App Library's expanded categories must not acquire the Home Screen
    // folder choice just because they reuse a folder background class.
    if (element == D18Folders && D18HasContext(view, controller, NO)) return D18AppLibrary;
    return element;
}

static BOOL D18IsNotificationOptionsSource(UIView *view) {
    // The Options popup is detached from its swipe button once presented.
    // Identify its *source*, not generic menu/UIButton classes. This also works
    // if UIKit attaches the interaction to a child inside the action button.
    for (NSUInteger depth = 0; view && depth < 32; depth++, view = view.superview) {
        for (Class cls = object_getClass(view); cls; cls = class_getSuperclass(cls)) {
            if (D18IsNotificationOptionsSourceClass(class_getName(cls))) return YES;
        }
    }
    return NO;
}

static void D18CreateMenuView(id self, SEL cmd, id menu) {
    D18OriginalCreateMenuView(self, cmd, menu);
    if (!pthread_main_np()) return;
    id menuView = D18GetObject(self, NSSelectorFromString(@"menuView"));
    if (![menuView isKindOfClass:UIView.class]) return;

    // iOS 18 creates the action list separately from the icon-preview
    // controller. Its menu style does not propagate preferredTraitCollection.
    // Follow the actual UIController -> presentation -> interaction ownership,
    // then mark its actual source scope. Generic action sheets remain unclassified.
    id presentation = D18GetObject(self, NSSelectorFromString(@"delegate"));
    id interaction = D18GetObject(presentation, NSSelectorFromString(@"delegate"));
    BOOL iconMenu = NO;
    BOOL notificationOptions = NO;
    if ([interaction isKindOfClass:UIContextMenuInteraction.class]) {
        id owner = D18GetObject(interaction, NSSelectorFromString(@"delegate"));
        id sourceView = D18GetObject(interaction, NSSelectorFromString(@"view"));
        iconMenu = D18IconViewClass && [owner isKindOfClass:D18IconViewClass] &&
                   sourceView == owner;
        notificationOptions = !iconMenu && [sourceView isKindOfClass:UIView.class] &&
                              D18IsNotificationOptionsSource(sourceView);
    }
    objc_setAssociatedObject(menuView, &D18IconMenuKey, iconMenu ? @YES : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(menuView, &D18NotificationOptionsMenuKey, notificationOptions ? @YES : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Apply before UIKit fills the new view with action cells. Their native
    // materials/text inherit this appearance, including subsequent submenus.
    // The regular state engine also handles later native setters and Default.
    D18Apply(menuView, NO);
}

static void D18UpdateMenuListMaterial(UIView *view) {
    if (D18RawElement(view) != D18ContextMenuListSurface) return;
    BOOL iconMenu = NO;
    // A menu list alone is not evidence of a Home Screen action menu. Resolve
    // the marker set by the existing verified SBIconView interaction source.
    UIView *owner = view;
    for (NSUInteger depth = 0; owner && depth < 64; depth++, owner = owner.superview) {
        if (objc_getAssociatedObject(owner, &D18NotificationOptionsMenuKey)) break;
        if (objc_getAssociatedObject(owner, &D18IconMenuKey)) { iconMenu = YES; break; }
    }
    D18UpdateClassicMenuMaterials(view, iconMenu && D18Config.values[D18QuickActions] == D18IOS10Style);
}

static void D18MenuListLayout(id self, SEL cmd) {
    D18OriginalMenuListLayout(self, cmd);
    if (pthread_main_np()) D18UpdateMenuListMaterial(self);
}
#endif

static int D18Selection(id object, BOOL isController) {
#if D18_APPLICATIONS
    // SpringBoard never enters this build. Applications is one global setting,
    // applied to app windows/controllers, not the Home Screen or daemons.
    if (!isController && ![object isKindOfClass:UIWindow.class]) return 0;
    return D18Config.values[D18Applications];
#else
    D18Element element = D18ResolveElement(object, isController);
    return element >= 0 && element < D18ElementCount ?
        D18SelectionForElement(element, D18Config.values[element]) : 0;
#endif
}

static D18StyleState D18ReadState(id object) {
    D18StyleState state = {false, 0};
    NSValue *stored = objc_getAssociatedObject(object, &D18StateKey);
    if (stored) [stored getValue:&state size:sizeof(state)];
    return state;
}

static void D18StoreState(id object, D18StyleState state) {
    id value = state.managed ? [NSValue valueWithBytes:&state objCType:@encode(D18StyleState)] : nil;
    objc_setAssociatedObject(object, &D18StateKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void D18Apply(id object, BOOL isController) {
    if (!object || !pthread_main_np() || objc_getAssociatedObject(object, &D18ApplyingKey)) return;
#if !D18_APPLICATIONS
    if (!isController) D18UpdateMenuListMaterial(object);
#endif
    int selection = D18Selection(object, isController);
    D18StyleState state = D18ReadState(object);
    if (!selection && !state.managed) return;
    // UIView and UIViewController expose the same public NSInteger property.
    UIUserInterfaceStyle current = [(UIView *)object overrideUserInterfaceStyle];
    D18StyleState previous = state;
    UIUserInterfaceStyle effective = (UIUserInterfaceStyle)D18Transition(&state, current, selection);
    if (previous.managed != state.managed || previous.nativeStyle != state.nativeStyle)
        D18StoreState(object, state);
    if (effective == current) return;
    objc_setAssociatedObject(object, &D18ApplyingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        [(UIView *)object setOverrideUserInterfaceStyle:effective];
    } @finally {
        objc_setAssociatedObject(object, &D18ApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UIUserInterfaceStyle D18StyleForNativeSetter(id object, BOOL isController,
                                                   UIUserInterfaceStyle requested) {
    if (!pthread_main_np() || objc_getAssociatedObject(object, &D18ApplyingKey)) return requested;
    int selection = D18Selection(object, isController);
    D18StyleState state = D18ReadState(object);
    if (!selection && !state.managed) return requested;
    UIUserInterfaceStyle effective = (UIUserInterfaceStyle)D18InterceptNativeStyle(&state, requested, selection);
    D18StoreState(object, state);
    return effective;
}

static void D18ViewSetStyle(id self, SEL cmd, UIUserInterfaceStyle style) {
    D18OriginalViewSetStyle(self, cmd, D18StyleForNativeSetter(self, NO, style));
}
static void D18ControllerSetStyle(id self, SEL cmd, UIUserInterfaceStyle style) {
    D18OriginalControllerSetStyle(self, cmd, D18StyleForNativeSetter(self, YES, style));
}
static void D18ViewWillAppear(id self, SEL cmd, BOOL animated) {
    D18Apply(self, YES);
    D18OriginalViewWillAppear(self, cmd, animated);
}
static void D18ViewDidLoad(id self, SEL cmd) {
    D18OriginalViewDidLoad(self, cmd);
    D18Apply(self, YES);
}

#if !D18_APPLICATIONS
static void D18DidMoveToWindow(id self, SEL cmd) {
    D18OriginalDidMoveToWindow(self, cmd);
    if ([(UIView *)self window]) D18Apply(self, NO);
}
static void D18DidMoveToSuperview(id self, SEL cmd) {
    D18OriginalDidMoveToSuperview(self, cmd);
    if ([(UIView *)self window]) D18Apply(self, NO);
}
#endif

static void D18RefreshViews(UIView *view, NSUInteger depth) {
    if (!view || depth > 128) return;
    D18Apply(view, NO);
#if !D18_APPLICATIONS
    // Snapshot each level because changing traits can rebuild child views.
    for (UIView *child in view.subviews.copy) D18RefreshViews(child, depth + 1);
#else
    (void)depth;
#endif
}

static void D18RefreshControllers(UIViewController *controller, NSUInteger depth) {
    if (!controller || depth > 64) return;
    D18Apply(controller, YES);
    for (UIViewController *child in controller.childViewControllers.copy)
        D18RefreshControllers(child, depth + 1);
    if (controller.presentedViewController)
        D18RefreshControllers(controller.presentedViewController, depth + 1);
}

static void D18RefreshAll(void) {
    UIApplication *application = UIApplication.sharedApplication;
    if (!application) return;
    NSMutableSet<UIWindow *> *windows = [NSMutableSet set];
    for (UIScene *scene in application.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class])
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    // SpringBoard also owns legacy windows that are not exposed by a scene.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:application.windows];
#pragma clang diagnostic pop
    for (UIWindow *window in windows) {
        D18RefreshControllers(window.rootViewController, 0);
        D18RefreshViews(window, 0);
    }
}

static void D18PerformRefresh(void *context) {
    (void)context;
    @autoreleasepool {
        D18RefreshQueued = NO;
        D18RefreshAll();
    }
}

static void D18ScheduleRefresh(void) {
    if (D18RefreshQueued) return;
    D18RefreshQueued = YES;
    dispatch_async_f(dispatch_get_main_queue(), NULL, D18PerformRefresh);
}

static void D18ScheduleRefreshOnMain(void *context) {
    (void)context;
    D18ScheduleRefresh();
}

@implementation D18LifecycleObserver
- (void)appearanceContextChanged:(NSNotification *)notification {
    (void)notification;
    if (pthread_main_np()) D18ScheduleRefresh();
    else dispatch_async_f(dispatch_get_main_queue(), NULL, D18ScheduleRefreshOnMain);
}
@end

static void D18ConfigurationChanged(D18Configuration configuration, void *context) {
    (void)context;
    D18Config = configuration;
    D18ScheduleRefresh();
}

// Public UIKit lifecycle/appearance hooks, validated before replacement.
static BOOL D18Hook(Class cls, SEL selector, IMP replacement, IMP *original, char argument) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != (argument ? 3u : 2u)) return NO;
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != 'v') return NO;
    if (argument) {
        method_getArgumentType(method, 2, type, sizeof(type));
        if (argument == 'i' ? (type[0] != 'q' && type[0] != 'Q') :
                             (type[0] != 'B' && type[0] != 'c')) return NO;
    }
    MSHookMessageEx(cls, selector, replacement, original);
    return *original != NULL;
}

static void D18Start(void *context) {
    (void)context;
    @autoreleasepool {
        if (!BTSupportsIOS17And18()) return;
#if !D18_APPLICATIONS
        D18ClassKinds = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);
        if (!D18ClassKinds) return;
#endif
        D18Hook(UIView.class, @selector(setOverrideUserInterfaceStyle:),
                (IMP)D18ViewSetStyle, (IMP *)&D18OriginalViewSetStyle, 'i');
        D18Hook(UIViewController.class, @selector(setOverrideUserInterfaceStyle:),
                (IMP)D18ControllerSetStyle, (IMP *)&D18OriginalControllerSetStyle, 'i');
        D18Hook(UIViewController.class, @selector(viewWillAppear:),
                (IMP)D18ViewWillAppear, (IMP *)&D18OriginalViewWillAppear, 'b');
        D18Hook(UIViewController.class, @selector(viewDidLoad),
                (IMP)D18ViewDidLoad, (IMP *)&D18OriginalViewDidLoad, 0);
#if !D18_APPLICATIONS
        D18Hook(UIView.class, @selector(didMoveToWindow),
                (IMP)D18DidMoveToWindow, (IMP *)&D18OriginalDidMoveToWindow, 0);
        D18Hook(UIView.class, @selector(didMoveToSuperview),
                (IMP)D18DidMoveToSuperview, (IMP *)&D18OriginalDidMoveToSuperview, 0);
        D18IconViewClass = NSClassFromString(@"SBIconView");
        Class menuController = NSClassFromString(@"_UIContextMenuUIController");
        SEL createMenuView = NSSelectorFromString(@"_createMenuViewIfNecessaryForMenu:");
        if (D18MethodMatches(menuController, createMenuView, 'v', "@"))
            MSHookMessageEx(menuController, createMenuView, (IMP)D18CreateMenuView,
                           (IMP *)&D18OriginalCreateMenuView);
        Class menuList = NSClassFromString(@"_UIContextMenuListView");
        if ([menuList isSubclassOfClass:UIView.class])
            D18Hook(menuList, @selector(layoutSubviews),
                    (IMP)D18MenuListLayout, (IMP *)&D18OriginalMenuListLayout, 0);
        D18StartNotificationPreview();
#endif
        D18ObserveConfiguration(D18ConfigurationChanged, NULL);
        D18Observer = [D18LifecycleObserver new];
        for (NSString *name in @[UIApplicationDidFinishLaunchingNotification,
                                 UIApplicationDidBecomeActiveNotification,
                                 UIWindowDidBecomeVisibleNotification,
                                 UISceneDidActivateNotification]) {
            [NSNotificationCenter.defaultCenter addObserver:D18Observer
                selector:@selector(appearanceContextChanged:) name:name object:nil];
        }
    }
}

__attribute__((constructor)) static void D18Initialize(void) {
    char path[PATH_MAX];
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0) return;
    D18Process role = D18ProcessForPath(path);
#if D18_APPLICATIONS
    if (role != D18ProcessApplication) return;
#else
    if (role != D18ProcessSpringBoard) return;
#endif
    // Never perform Objective-C initialization or preferences/XPC operations
    // under dyld's initializer lock. Excluded processes do not even enqueue.
    dispatch_async_f(dispatch_get_main_queue(), NULL, D18Start);
}
