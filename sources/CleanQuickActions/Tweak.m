#import "Compatibility.h"
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dispatch/dispatch.h>
#import "Runtime.h"
#import "Preferences.h"
#import "Rules.h"
#include <mach-o/dyld.h>
#include <limits.h>
#include <pthread.h>

// Per-view state and ownership belong only to this tweak. Other appearance
// tweaks, including Dawn 18, can chain the same UIKit methods independently.
@interface CQASeparatorState : NSObject {
@public
    CQAVisibilityState visibility;
    BOOL writing;
}
@end
@implementation CQASeparatorState
@end

static BOOL CQAEnabled;
static Class CQAIconViewClass;
static Class CQASeparatorClasses[3];
static NSHashTable<UIView *> *CQAMenuRoots;
static NSHashTable<UIView *> *CQAManagedSeparators;
static char CQAMenuOwnerKey, CQAStateKey;
static void (*CQAOriginalCreateMenu)(id, SEL, id);
static void (*CQAOriginalListLayout)(id, SEL);
static void (*CQAOriginalSetHidden[3])(id, SEL, BOOL);
static void (*CQAOriginalDidMoveToSuperview[3])(id, SEL);
static void (*CQAOriginalDidMoveToWindow[3])(id, SEL);

static BOOL CQAIsSeparator(UIView *view) {
    for (NSUInteger index = 0; index < 3; index++)
        if (CQASeparatorClasses[index] && [view isKindOfClass:CQASeparatorClasses[index]]) return YES;
    return NO;
}

static BOOL CQAIsIconMenu(UIView *view) {
    for (NSUInteger depth = 0; view && depth < 64; depth++, view = view.superview) {
        NSNumber *owner = objc_getAssociatedObject(view, &CQAMenuOwnerKey);
        // An explicit NO stops a nested unrelated menu inheriting an icon scope.
        if (owner) return owner.boolValue;
    }
    return NO;
}

static CQASeparatorState *CQAState(UIView *view, BOOL create) {
    CQASeparatorState *state = objc_getAssociatedObject(view, &CQAStateKey);
    if (!state && create) {
        state = [CQASeparatorState new];
        objc_setAssociatedObject(view, &CQAStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [CQAManagedSeparators addObject:view];
    }
    return state;
}

static BOOL CQARequestedHidden(UIView *view, BOOL requested) {
    if (!pthread_main_np()) return requested;
    BOOL active = CQAEnabled && CQAIsIconMenu(view);
    CQASeparatorState *state = CQAState(view, active);
    if (!state || state->writing) return requested;
    // Preserve UIKit's latest requested value during recycling/highlighting.
    return CQAInterceptNativeHidden(&state->visibility, requested, active);
}

static void CQAApplySeparator(UIView *view) {
    if (!pthread_main_np()) return;
    BOOL active = CQAEnabled && CQAIsIconMenu(view);
    CQASeparatorState *state = CQAState(view, active);
    if (!state || state->writing) return;
    BOOL current = view.hidden;
    BOOL target = CQAVisibilityTransition(&state->visibility, current, active);
    if (current != target) {
        state->writing = YES;
        view.hidden = target;
        state->writing = NO;
    }
}

static void CQARefreshTree(UIView *root) {
    if (!root || !pthread_main_np()) return;
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if (CQAIsSeparator(view)) CQAApplySeparator(view);
        // The walk reads the existing menu only: no forced layout, frame,
        // height, alpha, background, material, text or interaction changes.
        [pending addObjectsFromArray:view.subviews];
    }
}

static void CQACreateMenu(id self, SEL cmd, id menu) {
    CQAOriginalCreateMenu(self, cmd, menu);
    if (!pthread_main_np()) return;
    id menuView = CQAGetObject(self, NSSelectorFromString(@"menuView"));
    if (![menuView isKindOfClass:UIView.class]) return;
    id presentation = CQAGetObject(self, NSSelectorFromString(@"delegate"));
    id interaction = CQAGetObject(presentation, NSSelectorFromString(@"delegate"));
    BOOL iconMenu = NO;
    if ([interaction isKindOfClass:UIContextMenuInteraction.class]) {
        id owner = CQAGetObject(interaction, NSSelectorFromString(@"delegate"));
        id source = CQAGetObject(interaction, NSSelectorFromString(@"view"));
        iconMenu = CQAIconViewClass && [owner isKindOfClass:CQAIconViewClass] && source == owner;
    }
    objc_setAssociatedObject(menuView, &CQAMenuOwnerKey, @(iconMenu), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (iconMenu) [CQAMenuRoots addObject:menuView];
    else [CQAMenuRoots removeObject:menuView];
    CQARefreshTree(menuView); // Also restores views if a menu changes ownership.
}

static void CQAListLayout(id self, SEL cmd) {
    CQAOriginalListLayout(self, cmd);
    // Decoration/supplementary views can be created after the root menu.
    // Specific separator lifecycle hooks also cover later scrolling/reuse.
    if (pthread_main_np() && CQAIsIconMenu(self)) CQARefreshTree(self);
}

#define CQA_SEPARATOR_HOOKS(INDEX) \
static void CQASetHidden##INDEX(id self, SEL cmd, BOOL hidden) { \
    CQAOriginalSetHidden[INDEX](self, cmd, CQARequestedHidden(self, hidden)); \
} \
static void CQADidMoveToSuperview##INDEX(id self, SEL cmd) { \
    CQAOriginalDidMoveToSuperview[INDEX](self, cmd); \
    CQAApplySeparator(self); \
} \
static void CQADidMoveToWindow##INDEX(id self, SEL cmd) { \
    CQAOriginalDidMoveToWindow[INDEX](self, cmd); \
    CQAApplySeparator(self); \
}

CQA_SEPARATOR_HOOKS(0)
CQA_SEPARATOR_HOOKS(1)
CQA_SEPARATOR_HOOKS(2)

static void CQAConfigurationChanged(BOOL enabled) {
    CQAEnabled = enabled;
    // Include detached/recycled views so turning OFF restores every view we
    // own, even when its previous menu is no longer on screen.
    for (UIView *view in CQAManagedSeparators.allObjects) CQAApplySeparator(view);
    for (UIView *menu in CQAMenuRoots.allObjects) CQARefreshTree(menu);
}

static void CQAStart(void *context) {
    (void)context;
    @autoreleasepool {
        if (!BTSupportsIOS17And18()) return;
        CQAIconViewClass = NSClassFromString(@"SBIconView");
        Class controller = NSClassFromString(@"_UIContextMenuUIController");
        SEL create = NSSelectorFromString(@"_createMenuViewIfNecessaryForMenu:");
        if (!CQAIconViewClass || !CQAMethodMatches(controller, create, 'v', "@")) return;
        CQAMenuRoots = [NSHashTable weakObjectsHashTable];
        CQAManagedSeparators = [NSHashTable weakObjectsHashTable];

        // Verified UIKit separator classes. Never hook generic collection
        // cells, global separator colors, or guessed thin UIView geometry.
        NSArray<NSString *> *names = @[@"_UIContextMenuSeparatorView",
            @"_UIContextMenuReusableSeparatorView", @"_UIContextMenuGradientMaskSectionSeparatorView"];
        IMP hidden[] = {(IMP)CQASetHidden0, (IMP)CQASetHidden1, (IMP)CQASetHidden2};
        IMP moved[] = {(IMP)CQADidMoveToSuperview0, (IMP)CQADidMoveToSuperview1, (IMP)CQADidMoveToSuperview2};
        IMP window[] = {(IMP)CQADidMoveToWindow0, (IMP)CQADidMoveToWindow1, (IMP)CQADidMoveToWindow2};
        for (NSUInteger index = 0; index < 3; index++) {
            Class cls = NSClassFromString(names[index]);
            if (![cls isSubclassOfClass:UIView.class] || cls == UIView.class ||
                !CQAMethodMatches(cls, @selector(setHidden:), 'v', "b") ||
                !CQAMethodMatches(cls, @selector(didMoveToSuperview), 'v', "") ||
                !CQAMethodMatches(cls, @selector(didMoveToWindow), 'v', "")) continue;
            // Avoid double interception if a later OS changes their ancestry.
            BOOL overlaps = NO;
            for (NSUInteger earlier = 0; earlier < index; earlier++) {
                Class other = CQASeparatorClasses[earlier];
                if (other && ([cls isSubclassOfClass:other] || [other isSubclassOfClass:cls])) overlaps = YES;
            }
            if (overlaps) continue;
            CQASeparatorClasses[index] = cls;
            MSHookMessageEx(cls, @selector(setHidden:), hidden[index], (IMP *)&CQAOriginalSetHidden[index]);
            MSHookMessageEx(cls, @selector(didMoveToSuperview), moved[index], (IMP *)&CQAOriginalDidMoveToSuperview[index]);
            MSHookMessageEx(cls, @selector(didMoveToWindow), window[index], (IMP *)&CQAOriginalDidMoveToWindow[index]);
        }
        MSHookMessageEx(controller, create, (IMP)CQACreateMenu, (IMP *)&CQAOriginalCreateMenu);
        Class list = NSClassFromString(@"_UIContextMenuListView");
        if ([list isSubclassOfClass:UIView.class] && CQAMethodMatches(list, @selector(layoutSubviews), 'v', ""))
            MSHookMessageEx(list, @selector(layoutSubviews), (IMP)CQAListLayout, (IMP *)&CQAOriginalListLayout);
        CQAObservePreference(CQAConfigurationChanged);
    }
}

__attribute__((constructor)) static void CQAInitialize(void) {
    char path[PATH_MAX];
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0 || !CQAIsSpringBoardPath(path)) return;
    // Defer Objective-C, preferences and hooks until outside dyld's init lock.
    dispatch_async_f(dispatch_get_main_queue(), NULL, CQAStart);
}
