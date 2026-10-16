#import "Compatibility.h"
// SwitcherSweep 1.0.7 — brooktrout12
// Native App Switcher deletion; UIKit material and short-lived card snapshots.
// No new Objective-C classes, compiled block literals, or process-wide C hooks.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <dispatch/dispatch.h>
#include "BTSweepPolicy.h"
#include "BTSweepPresentation.h"
#include "BTSweepPending.h"

static char BTStateKey;
static Class BTFluidClass;
static Class BTContainerClass;
static unsigned long long BTGeneration;
static const char *BTDeleteName = "switcherContentController:deletedDisplayItem:inAppLayout:forReason:";
static const char *BTHomeName = "_dismissSwitcherNoninteractivelyToAppLayout:dismissFloatingSwitcher:animated:";
static const char *BTScheduledNames[] = {"btss_commit:", "btss_returnHome:", "btss_cleanup:"};

static bool BTType(const char *type, char expected) {
    while (*type && strchr("rnNoORV",*type)) ++type;
    if (expected=='@') return type[0]=='@' && type[1]!='?';
    return type[0]==expected && type[1]=='\0';
}

static bool BTMethod(Class cls, const char *name, char result, const char *arguments) {
    Method method=cls ? class_getInstanceMethod(cls,sel_registerName(name)) : NULL;
    if (!method || method_getNumberOfArguments(method)!=strlen(arguments)) return false;
    char type[256]={0};
    method_getReturnType(method,type,sizeof(type));
    if (!BTType(type,result)) return false;
    for (unsigned i=0; arguments[i]; ++i) {
        method_getArgumentType(method,i,type,sizeof(type));
        if (!BTType(type,arguments[i])) return false;
    }
    return true;
}

static bool BTCan(id object, const char *name, char result, const char *arguments) {
    return object && BTMethod(object_getClass(object),name,result,arguments);
}

static id BTGet(id object, const char *name) {
    return BTCan(object,name,'@',"@:") ?
        ((id(*)(id,SEL))objc_msgSend)(object,sel_registerName(name)) : nil;
}

static bool BTBool(id object, const char *name) {
    return BTCan(object,name,'B',"@:") &&
        ((bool(*)(id,SEL))objc_msgSend)(object,sel_registerName(name));
}

static bool BTReadEnvironmentMode(id object,long long *value) {
    if (!BTCan(object,"unlockedEnvironmentMode",'q',"@:")) return false;
    *value=((long long(*)(id,SEL))objc_msgSend)(object,sel_registerName("unlockedEnvironmentMode"));
    return true;
}

static bool BTReadLayoutTargetsSwitcher(id layout,bool *matches) {
    static bool known=false;
    static long long switcherMode;
    if (!known) {
        id requestClass=(id)objc_getClass("SBSwitcherTransitionRequest");
        // These factories only construct request data; no request is submitted.
        // Derive native enum values instead of assuming a numeric constant.
        id switcher=BTGet(requestClass,"requestForActivatingAppSwitcher");
        id home=BTGet(requestClass,"requestForActivatingHomeScreen");
        long long homeMode;
        known=BTReadEnvironmentMode(switcher,&switcherMode) &&
              BTReadEnvironmentMode(home,&homeMode) && switcherMode!=homeMode;
    }
    long long destination;
    if (!known || !BTReadEnvironmentMode(layout,&destination)) return false;
    *matches=destination==switcherMode;
    return true;
}

static bool BTTransitionTargetsSwitcher(id context) {
    bool matches=false;
    return BTReadLayoutTargetsSwitcher(BTGet(context,"toLayoutState"),&matches) && matches;
}

static id BTCoordinator(void) {
    id cls=(id)objc_getClass("SBMainSwitcherControllerCoordinator");
    return BTGet(cls,"sharedInstanceIfExists") ?: BTGet(cls,"sharedInstance");
}

static NSMutableDictionary *BTState(id owner, bool create) {
    NSMutableDictionary *state=objc_getAssociatedObject(owner,&BTStateKey);
    if (!state && create) {
        state=[NSMutableDictionary dictionary];
        objc_setAssociatedObject(owner,&BTStateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static void BTTryPending(UIViewController *owner);
static void BTSchedulePending(UIViewController *owner);

static void BTDiscardPending(UIViewController *owner) {
    NSMutableDictionary *state=BTState(owner,false);
    id token=[[state[@"pendingClose"] retain] autorelease];
    // Invalidate ownership first, before UI changes can reenter layout hooks.
    for (NSString *key in @[@"pendingClose",@"pendingSince",@"pendingWakeScheduled",@"pendingOutsideSince"])
        [state removeObjectForKey:key];
    if (token) [NSObject cancelPreviousPerformRequestsWithTarget:owner
        selector:sel_registerName("btss_pendingWake:") object:token];
    [(UIButton *)state[@"button"] setTitle:@"Close All" forState:UIControlStateNormal];
}

static bool BTIsActive(UIViewController *owner) {
    if (!owner.isViewLoaded || !owner.view.window) return false;
    id switcher=BTGet(owner,"switcherController");
    return BTCan(switcher,"isMainSwitcherVisible",'B',"@:") ?
        BTBool(switcher,"isMainSwitcherVisible") : BTBool(BTCoordinator(),"isAnySwitcherVisible");
}

typedef struct {
    bool inWindow,visible,transitioning,liveKnown,layoutKnown,layoutSwitcher;
} BTNativeStatus;

static void BTRememberTransitionCoordinator(id owner,id coordinator) {
    if (!BTCan(coordinator,"isTransitioning",'B',"@:")) return;
    // Observe the native coordinator without adding a retain cycle.
    NSHashTable *weak=[NSHashTable weakObjectsHashTable];
    [weak addObject:coordinator];
    BTState(owner,true)[@"nativeTransitionCoordinator"]=weak;
}

static BTNativeStatus BTReadNativeStatus(UIViewController *owner) {
    NSMutableDictionary *state=BTState(owner,false);
    BTNativeStatus result={0};
    result.inWindow=owner.isViewLoaded && owner.view.window!=nil;
    result.visible=BTIsActive(owner);
    id coordinator=[(NSHashTable *)state[@"nativeTransitionCoordinator"] anyObject];
    result.liveKnown=BTCan(coordinator,"isTransitioning",'B',"@:");
    if (result.liveKnown) result.transitioning=BTBool(coordinator,"isTransitioning");
    else {
        id context=state[@"transitionContext"];
        result.transitioning=context && !(BTCan(context,"isComplete",'B',"@:") && BTBool(context,"isComplete"));
    }
    id layout=BTGet(BTGet(owner,"switcherController"),"layoutState");
    result.layoutKnown=BTReadLayoutTargetsSwitcher(layout,&result.layoutSwitcher);
    return result;
}

static void BTFinishRequest(UIViewController *owner) {
    NSMutableDictionary *state=BTState(owner,false);
    if (!state[@"pendingClose"]) return;
    BTDiscardPending(owner);
}

static id BTDeletionDelegate(id owner) {
    id delegate=BTGet(owner,"delegate");
    if (BTCan(delegate,BTDeleteName,'v',"@:@@@q")) return delegate;
    delegate=BTCoordinator();
    return BTCan(delegate,BTDeleteName,'v',"@:@@@q") ? delegate : nil;
}

static bool BTHomeSupported(void) {
    id coordinator=BTCoordinator();
    return (BTCan(coordinator,BTHomeName,'B',"@:@BB") &&
            BTCan((id)objc_getClass("SBAppLayout"),"homeScreenAppLayout",'@',"@:")) ||
           BTCan(coordinator,"handleHomeButtonPress",'B',"@:");
}

static NSArray *BTLayouts(id owner) {
    NSMutableOrderedSet *layouts=[NSMutableOrderedSet orderedSet];
    id local=BTGet(owner,"appLayouts"), all=BTGet(BTCoordinator(),"recentAppLayouts");
    if ([local isKindOfClass:[NSArray class]]) [layouts addObjectsFromArray:local];
    if ([all isKindOfClass:[NSArray class]]) [layouts addObjectsFromArray:all];
    return [layouts array];
}

static NSArray *BTTargets(id owner) {
    NSMutableArray *targets=[NSMutableArray array];
    NSMutableSet *seen=[NSMutableSet set];
    // Snapshot the collection before deleting anything. Offscreen items have
    // no instantiated card; native display-item deletion does not require one.
    NSArray *layouts=[[BTLayouts(owner) copy] autorelease];
    for (id layout in layouts) {
        if (BTCan(owner,"_supportsKillingForAppLayout:",'B',"@:@") &&
            !((bool(*)(id,SEL,id))objc_msgSend)(owner,
                sel_registerName("_supportsKillingForAppLayout:"),layout)) continue;
        id items=BTGet(layout,"allItems");
        if (![items isKindOfClass:[NSArray class]]) continue;
        for (id item in [[items copy] autorelease]) {
            id bundle=BTGet(item,"bundleIdentifier");
            if (![bundle isKindOfClass:[NSString class]] ||
                !BTSweepCanCloseBundle([bundle UTF8String]) ||
                BTBool(item,"isHomeScreenDisplayItem")) continue;
            // SBDisplayItem equality includes scene identity, so multiple app
            // windows are retained while duplicate references are excluded.
            if ([seen containsObject:item]) continue;
            [seen addObject:item];
            [targets addObject:@{@"layout":layout, @"item":item}];
        }
    }
    return targets;
}

static bool BTHasTargets(id owner) {
    id local=BTGet(owner,"appLayouts");
    if (![local isKindOfClass:[NSArray class]]) return false;
    for (id layout in local) {
        id items=BTGet(layout,"allItems");
        if (![items isKindOfClass:[NSArray class]]) continue;
        for (id item in items) {
            id bundle=BTGet(item,"bundleIdentifier");
            if ([bundle isKindOfClass:[NSString class]] &&
                BTSweepCanCloseBundle([bundle UTF8String]) &&
                !BTBool(item,"isHomeScreenDisplayItem")) return true;
        }
    }
    return false;
}

static void BTDetachButton(UIViewController *owner) {
    NSMutableDictionary *state=BTState(owner,false);
    UIButton *button=[[state[@"button"] retain] autorelease];
    if (!button) return;
    UIVisualEffectView *blur=[[state[@"blur"] retain] autorelease];
    // Clear ownership first in case UIKit synchronously invokes a layout hook.
    [state removeObjectForKey:@"button"];
    [state removeObjectForKey:@"blur"];
    // This controller also participates in ordinary app/Home transitions.
    // An alpha-zero ancestor does not tear down a live backdrop renderer.
    // Remove the material itself before the native transition takes snapshots.
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    button.userInteractionEnabled=NO;
    button.accessibilityElementsHidden=YES;
    button.hidden=YES;
    [button.layer removeAnimationForKey:@"brooktrout12.switchersweep.borderEntry"];
    blur.effect=nil;
    [button removeFromSuperview];
    [CATransaction commit];
}

static void BTCollectContainers(UIView *root, NSMutableArray *result, unsigned depth) {
    if (depth>18) return;
    // UIView.subviews is back-to-front order; the snapshots preserve that order.
    for (UIView *view in root.subviews) {
        if (BTContainerClass && [view isKindOfClass:BTContainerClass]) {
            [result addObject:view];
        } else BTCollectContainers(view,result,depth+1);
    }
}

static bool BTCardIsTarget(UIView *card,NSArray *targets) {
    id layout=BTGet(card,"appLayout");
    if (!layout) return false;
    for (NSDictionary *target in targets)
        if ([layout isEqual:target[@"layout"]]) return true;
    return false;
}

static void BTFinishVisuals(UIViewController *owner) {
    NSMutableDictionary *state=BTState(owner,false);
    NSArray *hidden=[[state[@"hiddenViews"] copy] autorelease];
    UIView *overlay=[[state[@"overlay"] retain] autorelease];
    [state removeObjectForKey:@"hiddenViews"];
    [state removeObjectForKey:@"overlay"];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    overlay.hidden=YES;
    [overlay removeFromSuperview];
    for (NSDictionary *entry in hidden) {
        UIView *view=entry[@"view"];
        // A recycled container belongs to native layout again, not our sweep.
        if ([BTGet(view,"appLayout") isEqual:entry[@"layout"]])
            view.hidden=[entry[@"hidden"] boolValue];
    }
    [CATransaction commit];
}

static void BTRestore(UIViewController *owner) {
    BTFinishVisuals(owner);
    NSMutableDictionary *state=BTState(owner,false);
    for (NSString *key in @[@"targets",@"deleteDelegate",@"token",@"phase"])
        [state removeObjectForKey:key];
}

static void BTPauseSweep(UIViewController *owner) {
    NSMutableDictionary *state=BTState(owner,false);
    id token=state[@"token"];
    if (token) for (unsigned i=0; i<3; ++i)
        [NSObject cancelPreviousPerformRequestsWithTarget:owner
            selector:sel_registerName(BTScheduledNames[i]) object:token];
    BTRestore(owner);
}

static void BTCancel(UIViewController *owner) {
    BTFinishRequest(owner);
    BTPauseSweep(owner);
}

static void BTKeepCardsHidden(UIViewController *owner) {
    NSMutableDictionary *state=BTState(owner,false);
    NSMutableArray *hidden=state[@"hiddenViews"];
    if (!hidden) return;
    // Native layout updates can create/reveal another card during deletion.
    // Keep those cards behind the temporary sweep until Home takes over.
    NSMutableArray *cards=[NSMutableArray array];
    BTCollectContainers(owner.view,cards,0);
    for (UIView *card in cards) {
        if (!BTCardIsTarget(card,state[@"targets"])) continue;
        bool known=false;
        for (NSDictionary *entry in hidden) if (entry[@"view"]==card) { known=true; break; }
        if (!known) [hidden addObject:@{@"view":card,@"hidden":@(card.hidden),@"layout":BTGet(card,"appLayout")}];
        card.hidden=YES;
    }
    UIView *overlay=state[@"overlay"];
    if (overlay.superview==owner.view) [owner.view bringSubviewToFront:overlay];
}

static void BTRevealButton(UIButton *button,UIVisualEffectView *blur) {
    // Fade the material from no effect to the native blur. Keep the button and
    // effect view at alpha 1: fading their parent caused the earlier artifact.
    // Legacy UIView animation transactions avoid compiled block literals on
    // the Linux arm64e toolchain. UIKit animates the effect and title together.
    const double duration=0.18;
    // Still present on iOS 18; deliberately used for the block-free ABI.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [UIView beginAnimations:@"brooktrout12.switchersweep.buttonEntry" context:NULL];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
    [UIView setAnimationBeginsFromCurrentState:YES];
    blur.effect=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    button.titleLabel.alpha=1;
    [UIView commitAnimations];
#pragma clang diagnostic pop
    CABasicAnimation *border=[CABasicAnimation animationWithKeyPath:@"borderColor"];
    border.fromValue=(id)[UIColor colorWithWhite:1 alpha:0].CGColor;
    border.toValue=(id)[UIColor colorWithWhite:1 alpha:0.2].CGColor;
    border.duration=duration;
    border.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [button.layer addAnimation:border forKey:@"brooktrout12.switchersweep.borderEntry"];
}

static UIButton *BTButton(UIViewController *owner,CGRect frame) {
    NSMutableDictionary *state=BTState(owner,true);
    UIButton *button=state[@"button"];
    if (button) {
        button.frame=frame;
        [(UIView *)state[@"blur"] setFrame:button.bounds];
        if (button.superview!=owner.view) [owner.view addSubview:button];
        return button;
    }
    button=[UIButton buttonWithType:UIButtonTypeCustom];
    button.frame=frame;
    button.opaque=NO;
    button.exclusiveTouch=YES;
    button.clipsToBounds=YES;
    button.layer.cornerRadius=23;
    button.layer.cornerCurve=kCACornerCurveContinuous;
    button.layer.borderWidth=1.0/[UIScreen mainScreen].scale;
    button.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.2].CGColor;
    [button setTitle:state[@"pendingClose"] ? @"Closing…" : @"Close All" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    button.titleLabel.alpha=0;
    button.accessibilityLabel=@"Close All Apps";
    button.accessibilityHint=@"Closes apps in the App Switcher and returns to the Home Screen.";
    UIVisualEffectView *blur=[[[UIVisualEffectView alloc]
        initWithEffect:nil] autorelease];
    blur.frame=button.bounds;
    blur.opaque=NO;
    blur.clipsToBounds=YES;
    blur.layer.cornerRadius=23;
    blur.layer.cornerCurve=kCACornerCurveContinuous;
    blur.userInteractionEnabled=NO;
    blur.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    blur.contentView.backgroundColor=[UIColor colorWithWhite:1 alpha:0];
    [button insertSubview:blur atIndex:0];
    [button addTarget:owner action:sel_registerName("btss_press:") forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:owner action:sel_registerName("btss_highlight:") forControlEvents:UIControlEventTouchDown|UIControlEventTouchDragEnter];
    [button addTarget:owner action:sel_registerName("btss_unhighlight:") forControlEvents:UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
    state[@"button"]=button; state[@"blur"]=blur;
    [owner.view addSubview:button];
    BTRevealButton(button,blur);
    return button;
}

static void BTUpdateImpl(UIViewController *owner) {
    if (![owner isKindOfClass:BTFluidClass] || !owner.isViewLoaded) return;
    NSMutableDictionary *state=BTState(owner,true);
    int phase=[state[@"phase"] intValue];
    if (phase) {
        BTDetachButton(owner);
        if (phase==1 && !BTIsActive(owner)) BTPauseSweep(owner);
        // Once Home has been requested, native transitions own the real cards.
        // Never hide new containers or restore old flags in their animations.
        else { if (phase==1 || phase==2) BTKeepCardsHidden(owner); return; }
    }
    // Entering the switcher is the sole exception to transition teardown.
    // The destination is known before the old visibility flag catches up.
    bool transitioning=state[@"transitionContext"]!=nil;
    bool canAppear=BTSweepButtonCanAppear(owner.view.window!=nil,BTIsActive(owner),
        transitioning,[state[@"enteringSwitcher"] boolValue],[state[@"disappearing"] boolValue]);
    if (!canAppear || !BTDeletionDelegate(owner) || !BTHomeSupported() || !BTHasTargets(owner)) {
        BTDetachButton(owner);
        return;
    }
    CGRect bounds=owner.view.bounds; UIEdgeInsets safe=owner.view.safeAreaInsets;
    BTSweepRect frame=BTSweepButtonFrame(bounds.size.width,bounds.size.height,safe.left,safe.right,safe.bottom);
    if (frame.width<=0) { BTDetachButton(owner); return; }
    UIButton *button=BTButton(owner,CGRectMake(bounds.origin.x+frame.x,bounds.origin.y+frame.y,frame.width,frame.height));
    button.userInteractionEnabled=YES;
    button.accessibilityElementsHidden=NO;
    [owner.view bringSubviewToFront:button];
}

static void BTUpdate(UIViewController *owner) {
    if (!owner || ![owner isKindOfClass:BTFluidClass]) return;
    NSMutableDictionary *state=BTState(owner,true);
    if ([state[@"updating"] boolValue]) return;
    state[@"updating"]=@YES;
    @try { BTUpdateImpl(owner); }
    @finally { [state removeObjectForKey:@"updating"]; }
    // Drain after the current native callback stack; another entry context
    // can begin synchronously as part of finishing the preceding one.
    BTSchedulePending(owner);
}

static bool BTTokenMatches(id owner, id token) {
    NSMutableDictionary *state=BTState(owner,false);
    return token && [token isEqual:state[@"token"]] && state[@"phase"]!=nil;
}

static void BTPost(UIViewController *owner, const char *name, id token, double delay) {
    [owner performSelector:sel_registerName(name) withObject:token afterDelay:delay
                  inModes:@[NSRunLoopCommonModes]];
}

static void BTAnimateSnapshot(UIView *snapshot, UIView *overlay, unsigned index, bool reduced) {
    double delay=reduced ? 0 : BTSweepCardDelay(index);
    double duration=reduced ? 0.16 : 0.24;
    double localTime=[snapshot.layer convertTime:CACurrentMediaTime() fromLayer:nil];
    CABasicAnimation *move=[CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    move.fromValue=@0;
    move.toValue=@(reduced ? 0 : -(CGRectGetHeight(overlay.bounds)+80));
    CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue=@1; fade.toValue=@0;
    CAAnimationGroup *group=[CAAnimationGroup animation];
    group.animations=@[move,fade]; group.duration=duration;
    group.beginTime=localTime+delay;
    group.timingFunction=[CAMediaTimingFunction functionWithControlPoints:0.32 :0 :0.85 :0.6];
    group.fillMode=kCAFillModeBoth; group.removedOnCompletion=NO;
    // The finished state belongs on the model layer too. A native snapshot
    // must not recapture the pre-animation card after its presentation faded.
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    snapshot.layer.opacity=0;
    snapshot.layer.transform=CATransform3DMakeTranslation(0,reduced ? 0 : -(CGRectGetHeight(overlay.bounds)+80),0);
    [snapshot.layer addAnimation:group forKey:@"brooktrout12.switchersweep.card"];
    [CATransaction commit];
}

static void BTStartSweep(UIViewController *owner,id delegate,NSArray *targets) {
    NSMutableDictionary *state=BTState(owner,false);
    NSNumber *token=@(++BTGeneration);
    state[@"token"]=token; state[@"phase"]=@1;
    state[@"targets"]=targets; state[@"deleteDelegate"]=delegate;
    BTDetachButton(owner);

    UIControl *overlay=[[[UIControl alloc] initWithFrame:owner.view.bounds] autorelease];
    overlay.opaque=NO;
    overlay.backgroundColor=[UIColor clearColor];
    overlay.clipsToBounds=YES;
    overlay.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    overlay.accessibilityElementsHidden=YES;
    NSMutableArray *cards=[NSMutableArray array];
    BTCollectContainers(owner.view,cards,0);
    [owner.view addSubview:overlay]; state[@"overlay"]=overlay;
    NSMutableArray *hidden=[NSMutableArray array]; state[@"hiddenViews"]=hidden;
    bool reduced=UIAccessibilityIsReduceMotionEnabled();
    NSMutableArray *snapshots=[NSMutableArray array];
    for (UIView *card in cards) {
        if (!BTCardIsTarget(card,targets)) continue;
        if (card.hidden || card.alpha<0.01 || !card.window) continue;
        CGRect frame=[card convertRect:card.bounds toView:overlay];
        if (!CGRectIntersectsRect(frame,overlay.bounds) || CGRectIsEmpty(frame)) continue;
        UIView *snapshot=[card snapshotViewAfterScreenUpdates:NO];
        if (!snapshot) continue;
        snapshot.userInteractionEnabled=NO; snapshot.frame=frame;
        [overlay addSubview:snapshot];
        [snapshots addObject:snapshot];
        [hidden addObject:@{@"view":card,@"hidden":@(card.hidden),@"layout":BTGet(card,"appLayout")}];
        card.hidden=YES;
    }
    // Only count visible snapshots for timing; offscreen cards cannot flatten
    // the stagger by consuming the capped delay range.
    for (unsigned i=0; i<snapshots.count; ++i)
        BTAnimateSnapshot(snapshots[i],overlay,(unsigned)(snapshots.count-1-i),reduced);
    BTKeepCardsHidden(owner);
    BTPost(owner,"btss_commit:",token,reduced ? 0.18 : 0.38);
}

static void BTSchedulePending(UIViewController *owner) {
    NSMutableDictionary *state=BTState(owner,false);
    id token=state[@"pendingClose"];
    if (!token || [state[@"pendingWakeScheduled"] boolValue]) return;
    state[@"pendingWakeScheduled"]=@YES;
    BTPost(owner,"btss_pendingWake:",token,1.0/60.0);
}

static void BTTryPending(UIViewController *owner) {
    NSMutableDictionary *state=BTState(owner,false);
    if (!state[@"pendingClose"] || [state[@"drainingPending"] boolValue]) return;
    state[@"drainingPending"]=@YES;
    @try {
        BTNativeStatus live=BTReadNativeStatus(owner);
        double now=CACurrentMediaTime(), elapsed=now-[state[@"pendingSince"] doubleValue];
        bool outside=!live.visible && (!live.inWindow ||
            (!live.transitioning && live.layoutKnown && !live.layoutSwitcher));
        if (outside && !state[@"pendingOutsideSince"]) state[@"pendingOutsideSince"]=@(now);
        if (!outside) [state removeObjectForKey:@"pendingOutsideSince"];
        double outsideFor=state[@"pendingOutsideSince"] ? now-[state[@"pendingOutsideSince"] doubleValue] : 0;
        unsigned phase=[state[@"phase"] unsignedIntValue];
        id delegate=nil;
        NSArray *targets=nil;
        bool ready=false;
        if (live.inWindow && live.visible && !live.transitioning && !phase) {
            delegate=BTDeletionDelegate(owner);
            targets=BTTargets(owner);
            ready=delegate && BTHomeSupported() && targets.count;
        }
        BTSweepPendingAction action=BTSweepEvaluatePending(live.inWindow,live.visible,
            live.transitioning,ready,phase,elapsed,outsideFor);
        if (action==BTSweepPendingCancel || action==BTSweepPendingFail) {
            BTFinishRequest(owner);
            BTPauseSweep(owner);
            BTUpdate(owner);
            return;
        }
        if (action==BTSweepPendingPause) BTPauseSweep(owner);
        if (action==BTSweepPendingStart) BTStartSweep(owner,delegate,targets);
        // Keep the same intent until BTCommit actually sends close requests.
        // An opening retarget can pause/restart visuals without losing the tap.
        BTSchedulePending(owner);
    } @finally { [state removeObjectForKey:@"drainingPending"]; }
}

static void BTPendingWake(UIViewController *owner,SEL command,NSNumber *token) {
    (void)command;
    NSMutableDictionary *state=BTState(owner,false);
    // An already delivered callback from an old visit cannot affect a new tap.
    if (![token isEqual:state[@"pendingClose"]]) return;
    [state removeObjectForKey:@"pendingWakeScheduled"];
    BTTryPending(owner);
}

static void BTSetButtonHighlighted(UIViewController *owner,UIButton *sender,BOOL highlighted) {
    NSMutableDictionary *state=BTState(owner,false);
    if (!sender || state[@"button"]!=sender) return;
    UIVisualEffectView *blur=state[@"blur"];
    if (!blur) return;
    // Tint the entire material's content, leaving its live backdrop and all
    // ancestor opacity untouched. No scaling or extra touch-intercepting view.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [UIView beginAnimations:@"brooktrout12.switchersweep.buttonHighlight" context:NULL];
    [UIView setAnimationDuration:highlighted ? 0.06 : 0.14];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
    [UIView setAnimationBeginsFromCurrentState:YES];
    blur.contentView.backgroundColor=[UIColor colorWithWhite:1 alpha:highlighted ? 0.12 : 0];
    [UIView commitAnimations];
#pragma clang diagnostic pop
}

static void BTPress(UIViewController *owner, SEL command, UIButton *sender) {
    (void)command;
    NSMutableDictionary *state=BTState(owner,false);
    BTSetButtonHighlighted(owner,sender,NO);
    BTSweepTapAction action=BTSweepClassifyTap(owner.isViewLoaded && owner.view.window!=nil,
        BTIsActive(owner),state[@"transitionContext"]!=nil,[state[@"enteringSwitcher"] boolValue],
        [state[@"disappearing"] boolValue],state[@"phase"]!=nil,state[@"pendingClose"]!=nil);
    if (action==BTSweepTapIgnore) return;
    // Own the user's intent independently of any native transition context.
    // Settled taps use the same path and start synchronously when ready.
    state[@"pendingClose"]=@(++BTGeneration);
    state[@"pendingSince"]=@(CACurrentMediaTime());
    [sender setTitle:@"Closing…" forState:UIControlStateNormal];
    BTTryPending(owner);
}

static void BTHighlight(UIViewController *owner, SEL command, UIButton *sender) {
    (void)command;
    if (!BTState(owner,false)[@"pendingClose"])
        BTSetButtonHighlighted(owner,sender,YES);
}
static void BTUnhighlight(UIViewController *owner, SEL command, UIButton *sender) {
    (void)command;
    BTSetButtonHighlighted(owner,sender,NO);
}

static void BTCommit(UIViewController *owner, SEL command, NSNumber *token) {
    (void)command;
    if (!BTTokenMatches(owner,token)) return;
    NSMutableDictionary *state=BTState(owner,false);
    if (!state[@"pendingClose"] || [state[@"phase"] intValue]!=1) return;
    BTNativeStatus live=BTReadNativeStatus(owner);
    id delegate=state[@"deleteDelegate"];
    if (!live.inWindow || !live.visible || live.transitioning ||
        !BTCan(delegate,BTDeleteName,'v',"@:@@@q")) {
        BTPauseSweep(owner); BTUpdate(owner); BTSchedulePending(owner); return;
    }
    NSArray *targets=[[state[@"targets"] copy] autorelease];
    state[@"phase"]=@2;
    BTFinishRequest(owner);
    // This is the native callback for a user-deleted App Switcher display item.
    // It accepts real item/layout objects and works without a visible container.
    // Reason 0 is the normal native kill reason used by killContainer:forReason:.
    for (NSDictionary *target in targets) {
        @try {
            ((void(*)(id,SEL,id,id,id,long long))objc_msgSend)(delegate,
                sel_registerName(BTDeleteName),owner,target[@"item"],target[@"layout"],0);
        } @catch (NSException *exception) {
            NSLog(@"[SwitcherSweep] Native close request failed: %@",exception.name);
        }
    }
    BTPost(owner,"btss_returnHome:",token,0.08);
}

static void BTReturnHome(UIViewController *owner, SEL command, NSNumber *token) {
    (void)command;
    if (!BTTokenMatches(owner,token)) return;
    NSMutableDictionary *state=BTState(owner,false); state[@"phase"]=@3;
    // End our visual ownership synchronously, before iOS snapshots or animates
    // Home. The delayed cleanup below now only releases bookkeeping objects.
    BTDetachButton(owner);
    BTFinishVisuals(owner);
    if (BTIsActive(owner)) {
        id coordinator=BTCoordinator();
        id home=BTGet((id)objc_getClass("SBAppLayout"),"homeScreenAppLayout");
        bool dismissed=false;
        @try {
            if (home && BTCan(coordinator,BTHomeName,'B',"@:@BB"))
                dismissed=((bool(*)(id,SEL,id,bool,bool))objc_msgSend)(coordinator,
                    sel_registerName(BTHomeName),home,true,true);
            if (!dismissed && BTIsActive(owner) && BTCan(coordinator,"handleHomeButtonPress",'B',"@:"))
                ((bool(*)(id,SEL))objc_msgSend)(coordinator,sel_registerName("handleHomeButtonPress"));
        } @catch (NSException *exception) {
            NSLog(@"[SwitcherSweep] Native Home transition failed: %@",exception.name);
        }
    }
    BTPost(owner,"btss_cleanup:",token,0.4);
}

static void BTCleanup(UIViewController *owner, SEL command, NSNumber *token) {
    (void)command;
    if (BTTokenMatches(owner,token)) { BTRestore(owner); BTUpdate(owner); }
}

static void (*BTOriginalDidLoad)(id,SEL);
static void BTDidLoad(UIViewController *self,SEL command) { BTOriginalDidLoad(self,command); BTUpdate(self); }
static void (*BTOriginalDidLayout)(id,SEL);
static void BTDidLayout(UIViewController *self,SEL command) { BTOriginalDidLayout(self,command); BTUpdate(self); }
static void (*BTOriginalVisibleItems)(id,SEL);
static void BTVisibleItems(UIViewController *self,SEL command) { BTOriginalVisibleItems(self,command); BTUpdate(self); }
static void (*BTOriginalWillDisappear)(id,SEL,bool);
static void BTWillDisappear(UIViewController *self,SEL command,bool animated) {
    NSMutableDictionary *state=BTState(self,true);
    state[@"disappearing"]=@YES;
    BTDetachButton(self);
    if ([state[@"phase"] intValue]==1) BTPauseSweep(self);
    else if ([state[@"phase"] intValue]>=2) BTFinishVisuals(self);
    BTOriginalWillDisappear(self,command,animated);
    BTSchedulePending(self);
}
static void (*BTOriginalWillAppear)(id,SEL,bool);
static void BTWillAppear(UIViewController *self,SEL command,bool animated) {
    [BTState(self,false) removeObjectForKey:@"disappearing"];
    BTOriginalWillAppear(self,command,animated);
    BTUpdate(self);
}

static void BTTransitionStarting(id controller,id context) {
    id content=BTGet(controller,"contentViewController");
    if (![content isKindOfClass:BTFluidClass]) return;
    NSMutableDictionary *state=BTState(content,true);
    id next=context ?: [NSNull null];
    bool entering=BTTransitionTargetsSwitcher(context);
    // Presentation hints detach the material immediately. They do not prove
    // that an accepted action should be discarded; consult live native state.
    state[@"transitionContext"]=next;
    state[@"enteringSwitcher"]=@(entering);
    if (entering) [state removeObjectForKey:@"disappearing"];
    else BTDetachButton(content);
    // A gesture can interrupt the sweep before any close requests are sent.
    if ([state[@"phase"] intValue]==1) BTPauseSweep(content);
    // Native deletion may start its own transition before returnHome runs.
    // The sweep has finished by this point; stop touching native card views.
    else if ([state[@"phase"] intValue]>=2) BTFinishVisuals(content);
    if (entering) BTUpdate(content);
    BTSchedulePending(content);
}
static void (*BTOriginalPrepareTransition)(id,SEL,id);
static void BTPrepareTransition(id self,SEL command,id context) {
    BTTransitionStarting(self,context);
    BTOriginalPrepareTransition(self,command,context);
    // Preparation can attach the native view/window. Refresh within the same
    // event, rather than waiting for the half-second transition to finish.
    id content=BTGet(self,"contentViewController");
    if ([content isKindOfClass:BTFluidClass]) BTUpdate(content);
}
static void (*BTOriginalTransitionBegin)(id,SEL,id,id);
static void BTTransitionBegin(id self,SEL command,id coordinator,id context) {
    id owner=BTGet(self,"contentViewController");
    if ([owner isKindOfClass:BTFluidClass]) BTRememberTransitionCoordinator(owner,coordinator);
    BTTransitionStarting(self,context);
    BTOriginalTransitionBegin(self,command,coordinator,context);
    id content=BTGet(self,"contentViewController");
    if ([content isKindOfClass:BTFluidClass]) BTUpdate(content);
}
static void (*BTOriginalTransitionEnd)(id,SEL,id,id);
static void BTTransitionEnd(id self,SEL command,id coordinator,id context) {
    id owner=BTGet(self,"contentViewController");
    if ([owner isKindOfClass:BTFluidClass]) BTRememberTransitionCoordinator(owner,coordinator);
    BTOriginalTransitionEnd(self,command,coordinator,context);
    id content=BTGet(self,"contentViewController");
    if (![content isKindOfClass:BTFluidClass]) return;
    NSMutableDictionary *state=BTState(content,false);
    id current=state[@"transitionContext"];
    // An interrupted older transition must not reattach the material over a
    // newer app launch or Home gesture that is still in progress.
    if (current && current!=(context ?: [NSNull null])) return;
    [state removeObjectForKey:@"transitionContext"];
    [state removeObjectForKey:@"enteringSwitcher"];
    if (BTIsActive(content)) [state removeObjectForKey:@"disappearing"];
    if ([state[@"phase"] intValue]==3) BTCancel(content);
    BTUpdate(content);
    // BTUpdate attempts delivery; if visibility/layouts lag behind this event,
    // the pending request remains owned and its short-lived wake retries it.
}

static void (*BTOriginalContentTransitionBegin)(id,SEL,id,id);
static void BTContentTransitionBegin(id self,SEL command,id coordinator,id context) {
    BTRememberTransitionCoordinator(self,coordinator);
    unsigned phase=[BTState(self,false)[@"phase"] unsignedIntValue];
    if (phase==1) BTPauseSweep(self);
    else if (phase>=2) BTFinishVisuals(self);
    BTOriginalContentTransitionBegin(self,command,coordinator,context);
    BTSchedulePending(self);
}
static void (*BTOriginalContentTransitionEnd)(id,SEL,id,id);
static void BTContentTransitionEnd(id self,SEL command,id coordinator,id context) {
    BTRememberTransitionCoordinator(self,coordinator);
    BTOriginalContentTransitionEnd(self,command,coordinator,context);
    BTSchedulePending(self);
}

static bool (*BTOriginalShouldReceiveTouch)(id,SEL,id,id);
static bool BTShouldReceiveTouch(id self,SEL command,id recognizer,UITouch *touch) {
    NSMutableDictionary *state=BTState(self,false);
    UIView *view=touch.view, *button=state[@"button"], *overlay=state[@"overlay"];
    // The stock background tap recognizer must not consume this control's tap
    // and dismiss the switcher before UIButton receives TouchUpInside.
    if ((button.userInteractionEnabled &&
         (view==button || [view isDescendantOfView:button])) ||
        (overlay && (view==overlay || [view isDescendantOfView:overlay]))) return false;
    // A new deliberate touch outside the button cancels the waiting action.
    // A transient lifecycle callback during the original entry does not.
    if (state[@"pendingClose"] && !state[@"phase"]) {
        BTFinishRequest(self);
    }
    return BTOriginalShouldReceiveTouch(self,command,recognizer,touch);
}

static void BTInstall(void *context) {
    (void)context;
    @autoreleasepool {
        BTFluidClass=objc_getClass("SBFluidSwitcherViewController");
        BTContainerClass=objc_getClass("SBFluidSwitcherItemContainer");
        if (!BTFluidClass || !BTContainerClass ||
            !BTMethod(BTFluidClass,"appLayouts",'@',"@:") ||
            !BTMethod(BTFluidClass,"viewDidLoad",'v',"@:") ||
            !BTMethod(BTFluidClass,"viewDidLayoutSubviews",'v',"@:") ||
            !BTMethod(BTFluidClass,"viewWillDisappear:",'v',"@:B")) {
            NSLog(@"[SwitcherSweep] Unsupported App Switcher signatures; installation skipped.");
            return;
        }
        struct { const char *name; IMP function; } actions[] = {
            {"btss_press:",(IMP)BTPress},{"btss_highlight:",(IMP)BTHighlight},
            {"btss_unhighlight:",(IMP)BTUnhighlight},{"btss_commit:",(IMP)BTCommit},
            {"btss_returnHome:",(IMP)BTReturnHome},{"btss_cleanup:",(IMP)BTCleanup},
            {"btss_pendingWake:",(IMP)BTPendingWake}
        };
        for (unsigned i=0; i<sizeof(actions)/sizeof(actions[0]); ++i)
            if (!class_addMethod(BTFluidClass,sel_registerName(actions[i].name),actions[i].function,"v@:@")) return;
        MSHookMessageEx(BTFluidClass,sel_registerName("viewDidLoad"),(IMP)BTDidLoad,(IMP *)&BTOriginalDidLoad);
        MSHookMessageEx(BTFluidClass,sel_registerName("viewDidLayoutSubviews"),(IMP)BTDidLayout,(IMP *)&BTOriginalDidLayout);
        MSHookMessageEx(BTFluidClass,sel_registerName("viewWillDisappear:"),(IMP)BTWillDisappear,(IMP *)&BTOriginalWillDisappear);
        if (BTMethod(BTFluidClass,"viewWillAppear:",'v',"@:B"))
            MSHookMessageEx(BTFluidClass,sel_registerName("viewWillAppear:"),(IMP)BTWillAppear,(IMP *)&BTOriginalWillAppear);
        if (BTMethod(BTFluidClass,"_updateVisibleItems",'v',"@:"))
            MSHookMessageEx(BTFluidClass,sel_registerName("_updateVisibleItems"),(IMP)BTVisibleItems,(IMP *)&BTOriginalVisibleItems);
        if (BTMethod(BTFluidClass,"gestureRecognizer:shouldReceiveTouch:",'B',"@:@@"))
            MSHookMessageEx(BTFluidClass,sel_registerName("gestureRecognizer:shouldReceiveTouch:"),
                (IMP)BTShouldReceiveTouch,(IMP *)&BTOriginalShouldReceiveTouch);
        const char *contentBegin="layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:";
        const char *contentEnd="layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:";
        if (BTMethod(BTFluidClass,contentBegin,'v',"@:@@"))
            MSHookMessageEx(BTFluidClass,sel_registerName(contentBegin),(IMP)BTContentTransitionBegin,
                (IMP *)&BTOriginalContentTransitionBegin);
        if (BTMethod(BTFluidClass,contentEnd,'v',"@:@@"))
            MSHookMessageEx(BTFluidClass,sel_registerName(contentEnd),(IMP)BTContentTransitionEnd,
                (IMP *)&BTOriginalContentTransitionEnd);
        Class controller=objc_getClass("SBSwitcherController");
        const char *transition="layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:";
        if (BTMethod(controller,transition,'v',"@:@@")) {
            MSHookMessageEx(controller,sel_registerName(transition),(IMP)BTTransitionEnd,(IMP *)&BTOriginalTransitionEnd);
            const char *prepare="prepareForCoordinatedLayoutStateTransitionWithContext:";
            const char *begin="layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:";
            if (BTMethod(controller,prepare,'v',"@:@"))
                MSHookMessageEx(controller,sel_registerName(prepare),(IMP)BTPrepareTransition,(IMP *)&BTOriginalPrepareTransition);
            if (BTMethod(controller,begin,'v',"@:@@"))
                MSHookMessageEx(controller,sel_registerName(begin),(IMP)BTTransitionBegin,(IMP *)&BTOriginalTransitionBegin);
        }
    }
}

__attribute__((constructor)) static void BTInitialize(void) {
    @autoreleasepool {
        if (!BTSupportsIOS17And18()) return;
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        dispatch_async_f(dispatch_get_main_queue(),NULL,BTInstall);
    }
}
