#import "ClassicMenu.h"
#import "Runtime.h"
#import <pthread.h>

@interface D18MenuMaterialState : NSObject
@property(nonatomic, strong) UIVisualEffect *nativeEffect;
@property(nonatomic, strong) UIColor *nativeColor;
@property(nonatomic, strong) UIVisualEffect *appliedEffect;
@property(nonatomic, strong) UIColor *appliedColor;
@property(nonatomic) BOOL applied;
@end
@implementation D18MenuMaterialState
@end

@interface D18MenuListMaterialState : NSObject
@property(nonatomic, strong) NSMapTable<UIVisualEffectView *, D18MenuMaterialState *> *backgrounds;
@property(nonatomic) BOOL updating;
@end
@implementation D18MenuListMaterialState
@end

static char D18MenuListMaterialKey;

static BOOL D18SameObject(id first, id second) {
    return first == second || [first isEqual:second];
}

static void D18UpdateMaterial(UIVisualEffectView *view, D18MenuMaterialState *state, BOOL enabled) {
    UIVisualEffect *currentEffect = view.effect;
    UIColor *currentColor = view.backgroundColor;
    BOOL effectIsOurs = state.applied && D18SameObject(currentEffect, state.appliedEffect);
    BOOL colorIsOurs = state.applied && D18SameObject(currentColor, state.appliedColor);

    // Preserve native changes observed during reuse/theme updates. Never save
    // our own classic effect as the native value to restore later.
    if (!effectIsOurs) state.nativeEffect = currentEffect;
    if (!colorIsOurs) state.nativeColor = currentColor;
    if (enabled) {
        if (!effectIsOurs) {
            // The original, pre-semantic light blur retains much more backdrop
            // color than iOS 18's menu material. Use the public UIKit effect.
            view.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
            // UIVisualEffectView copies its effect. Remember its stored value.
            state.appliedEffect = view.effect;
        }
        if (!colorIsOurs) {
            view.backgroundColor = UIColor.clearColor;
            state.appliedColor = view.backgroundColor;
        }
        state.applied = YES;
    } else if (state.applied) {
        // If UIKit has already supplied a new value, leave that value intact.
        if (effectIsOurs) view.effect = state.nativeEffect;
        if (colorIsOurs) view.backgroundColor = state.nativeColor;
        state.applied = NO;
    }
}

void D18UpdateClassicMenuMaterials(UIView *list, BOOL enabled) {
    if (!list || !pthread_main_np()) return;
    D18MenuListMaterialState *state = objc_getAssociatedObject(list, &D18MenuListMaterialKey);
    if (state.updating || (!enabled && !state)) return;
    if (!state) {
        state = [D18MenuListMaterialState new];
        state.backgrounds = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(list, &D18MenuListMaterialKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    state.updating = YES;
    @try {
        if (enabled) {
            // iOS 18 can embed a second effect behind the scrolling collection
            // view. Using only backgroundView misses that compositing path.
            for (NSString *name in @[@"backgroundView", @"cvBackgroundView"]) {
                id candidate = D18GetObject(list, NSSelectorFromString(name));
                if (![candidate isKindOfClass:UIVisualEffectView.class] ||
                    ![(UIView *)candidate isDescendantOfView:list]) continue;
                if (![state.backgrounds objectForKey:candidate])
                    [state.backgrounds setObject:[D18MenuMaterialState new] forKey:candidate];
            }
        }
        // Weak keys avoid retaining outgoing collection backgrounds. Restore
        // tracked views if replaced/reparented, or when leaving classic mode.
        for (UIVisualEffectView *background in state.backgrounds.keyEnumerator.allObjects) {
            BOOL keepClassic = enabled && [background isDescendantOfView:list];
            D18UpdateMaterial(background, [state.backgrounds objectForKey:background], keepClassic);
            if (!keepClassic) [state.backgrounds removeObjectForKey:background];
        }
    } @finally {
        state.updating = NO;
    }
    if (!enabled) objc_setAssociatedObject(list, &D18MenuListMaterialKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
