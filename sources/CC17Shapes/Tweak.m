// CC17Shapes -- Copyright (c) 2026 brooktrout12. MIT license.
// Rootless, SpringBoard only, iOS 18. No preferences, timers, blocks or logging.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#include <string.h>
#include "BTShapeGeometry.h"

typedef struct SBIconImageInfo {
    CGSize size;
    CGFloat scale;
    CGFloat continuousCornerRadius;
} SBIconImageInfo;

// Compare ABI encodings, ignoring qualifiers and optional field labels.
// Never install a guessed signature or send an unchecked private selector.
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

static bool BTMethodIs(Class cls, SEL selector, const char *result, const char *argument) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != (argument ? 3u : 2u)) return false;
    char encoding[512];
    method_getReturnType(method, encoding, sizeof(encoding));
    if (!BTTypeIs(encoding, result)) return false;
    if (argument) {
        method_getArgumentType(method, 2, encoding, sizeof(encoding));
        if (!BTTypeIs(encoding, argument)) return false;
    }
    return true;
}

static id BTObjectProperty(id object, const char *name) {
    if (!object) return nil;
    SEL selector = sel_registerName(name);
    if (!BTMethodIs(object_getClass(object), selector, @encode(id), NULL)) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static id BTObjectIvar(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    if (!ivar || ivar_getTypeEncoding(ivar)[0] != '@') return nil;
    return object_getIvar(object, ivar);
}

static bool BTIsConnectivityOwner(id object) {
    // Match the grouped module, not individual Wi-Fi/AirDrop/etc. controllers:
    // those controllers can also supply separate controls outside this group.
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        const char *name = class_getName(cls);
        if (strncmp(name, "CCUIConnectivity", 16) == 0 ||
            strstr(name, "ConnectivityModule") != NULL) return true;
    }
    if ([object isKindOfClass:[UIViewController class]]) {
        id identifier = BTObjectProperty(object, "moduleIdentifier");
        if ([identifier isKindOfClass:[NSString class]]) {
            const char *name = [identifier UTF8String];
            if (name && (strcmp(name, "com.apple.control-center.ConnectivityModule") == 0 ||
                         strcmp(name, "com.apple.control-center.Connectivity") == 0)) return true;
        }
    }
    return false;
}

static bool BTInConnectivityGroup(id object) {
    if (![object isKindOfClass:[UIResponder class]]) return false;
    UIResponder *responder = object;
    for (unsigned depth = 0; responder && depth < 48; ++depth) {
        if (BTIsConnectivityOwner(responder)) return true;
        if ([responder isKindOfClass:[UIViewController class]]) {
            UIViewController *parent = ((UIViewController *)responder).parentViewController;
            for (unsigned level = 0; parent && level < 16; ++level) {
                if (BTIsConnectivityOwner(parent)) return true;
                parent = parent.parentViewController;
            }
        }
        UIResponder *next = responder.nextResponder;
        if (next == responder) break;
        responder = next;
    }
    return false;
}

static bool BTIsGroupedConnectivityButton(id object) {
    if (!BTInConnectivityGroup(object)) return false;
    // Only the inner buttons are exempt. The surrounding connectivity platter
    // now follows exactly the same corner rule as media and other large tiles.
    UIView *view = [object isKindOfClass:[UIView class]] ? object :
        ([object isKindOfClass:[UIViewController class]] ? ((UIViewController *)object).viewIfLoaded : nil);
    Class round = objc_getClass("CCUIRoundButton");
    Class labeled = objc_getClass("CCUILabeledRoundButton");
    for (unsigned depth = 0; view && depth < 48; ++depth, view = view.superview)
        if ((round && [view isKindOfClass:round]) || (labeled && [view isKindOfClass:labeled])) return true;
    return false;
}

static CGSize BTObjectSize(id object) {
    if ([object isKindOfClass:[UIView class]]) return ((UIView *)object).bounds.size;
    SEL infoSelector = sel_registerName("iconImageInfo");
    if (BTMethodIs(object_getClass(object), infoSelector, @encode(SBIconImageInfo), NULL)) {
        SBIconImageInfo info = ((SBIconImageInfo (*)(id, SEL))objc_msgSend)(object, infoSelector);
        return info.size;
    }
    if ([object isKindOfClass:[UIViewController class]])
        return ((UIViewController *)object).viewIfLoaded.bounds.size;
    return CGSizeZero;
}

static char BTReadingLayoutUnitKey;
// Used only before native grid metrics become available. Main and gallery
// caches are separate so previews cannot change the main grid's corner size.
static CGFloat BTMainUnitSide = 68.0, BTGalleryUnitSide = 56.0;

static unsigned BTControlLayoutKind(id object) {
    Class main = objc_getClass("_TtC15ControlCenterUI14IconListLayout");
    Class gallery = objc_getClass("_TtC23ControlCenterUIServices29ControlsGalleryIconListLayout");
    if (gallery && [object isKindOfClass:gallery]) return 2;
    if (main && [object isKindOfClass:main]) return 1;
    return 0;
}

static CGFloat BTRecordLayoutUnit(unsigned kind, CGSize size) {
    CGFloat *unit = kind == 2 ? &BTGalleryUnitSide : &BTMainUnitSide;
    if (BTIsSquareControl(size.width, size.height)) *unit = MIN(size.width, size.height);
    return *unit;
}

static CGFloat BTUnitForLayout(id layout) {
    unsigned kind = BTControlLayoutKind(layout);
    CGFloat fallback = kind == 2 ? BTGalleryUnitSide : BTMainUnitSide;
    if (!kind || objc_getAssociatedObject(layout, &BTReadingLayoutUnitKey)) return fallback;
    // A native base-info getter can itself call a grid-size getter. This guard
    // prevents a recursive metrics lookup through our two hooks.
    objc_setAssociatedObject(layout, &BTReadingLayoutUnitKey, [NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat result = fallback;
    @try { result = BTRecordLayoutUnit(kind, BTObjectSize(layout)); }
    @finally {
        objc_setAssociatedObject(layout, &BTReadingLayoutUnitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return result;
}

static CGFloat BTUnitForObject(id object) {
    if (BTControlLayoutKind(object)) return BTUnitForLayout(object);
    UIView *view = [object isKindOfClass:[UIView class]] ? object :
        ([object isKindOfClass:[UIViewController class]] ? ((UIViewController *)object).viewIfLoaded : nil);
    Class list = objc_getClass("SBIconListView");
    for (unsigned depth = 0; view && depth < 40; ++depth, view = view.superview) {
        if (list && [view isKindOfClass:list]) {
            id layout = BTObjectProperty(view, "layout");
            if (BTControlLayoutKind(layout)) return BTUnitForLayout(layout);
        }
    }
    Class gallery = objc_getClass("_TtC23ControlCenterUIServices30ControlContainerViewController");
    return gallery && [object isKindOfClass:gallery] ? BTGalleryUnitSide : BTMainUnitSide;
}

static CGFloat BTRadiusForObject(id object, CGFloat radius) {
    if (BTIsGroupedConnectivityButton(object)) return radius;
    CGSize size = BTObjectSize(object);
    return BTShapeRadius(size.width, size.height, radius, BTUnitForObject(object));
}

static SBIconImageInfo BTFixImageInfo(SBIconImageInfo info, CGFloat unitSide) {
    info.continuousCornerRadius = BTShapeRadius(info.size.width, info.size.height,
                                              info.continuousCornerRadius, unitSide);
    return info;
}

static bool BTIsGlyphOrChrome(UIView *view) {
    if ([view isKindOfClass:[UIImageView class]] || [view isKindOfClass:[UILabel class]] ||
        [view isKindOfClass:[UIActivityIndicatorView class]]) return true;
    const char *name = class_getName(object_getClass(view));
    return strstr(name, "Glyph") || strstr(name, "Badge") || strstr(name, "ResizeHandle") ||
           strstr(name, "Progress") || strstr(name, "PageIndicator") ||
           strstr(name, "RemoveButton") || strstr(name, "DeleteButton");
}

static bool BTIsBackgroundView(UIView *view) {
    if ([view isKindOfClass:[UIControl class]]) return true;
    const char *name = class_getName(object_getClass(view));
    return strstr(name, "Material") || strstr(name, "Background") ||
           strstr(name, "Backdrop") || strstr(name, "Platter") ||
           strstr(name, "EmptyGridCell") || strstr(name, "ContentContainer") ||
           strstr(name, "ControlHostView") || strstr(name, "ControlTemplateView");
}

static bool BTInsideControl(UIView *view) {
    // MTMaterialView is shared with other parts of SpringBoard. Check ancestry
    // on each call, so reparenting/reuse cannot leave a stale classification.
    for (unsigned depth = 0; view && depth < 32; ++depth, view = view.superview) {
        const char *name = class_getName(object_getClass(view));
        if (strstr(name, "CCUIContentModuleContentContainerView") ||
            strstr(name, "CCUIControlHostView") || strstr(name, "CCUIControlTemplateView") ||
            strstr(name, "CCUIButtonModuleView") || strstr(name, "CCUIRoundButton") ||
            strstr(name, "ControlCenterUI13EmptyGridCell")) return true;
    }
    return false;
}

static bool BTInsideSlider(UIView *view) {
    Class slider = objc_getClass("CCUIBaseSliderView");
    for (unsigned depth = 0; slider && view && depth < 32; ++depth, view = view.superview)
        if ([view isKindOfClass:slider]) return true;
    return false;
}

static bool BTFocusHasControlCenterOwner(id object) {
    if (![object isKindOfClass:[UIView class]]) return false;
    if (BTInsideControl(object)) return true;
    // Focus can move its content out of the compact view while retaining the
    // module's controller containment. Follow that live relationship as well.
    Class module = objc_getClass("CCUIContentModuleContainerViewController");
    Class host = objc_getClass("CCUIControlHostViewController");
    UIResponder *responder = object;
    for (unsigned depth = 0; responder && depth < 48; ++depth) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            UIViewController *controller = (UIViewController *)responder;
            for (unsigned level = 0; controller && level < 16; ++level) {
                if ((module && [controller isKindOfClass:module]) ||
                    (host && [controller isKindOfClass:host])) return true;
                controller = controller.parentViewController;
            }
        }
        UIResponder *next = responder.nextResponder;
        if (next == responder) break;
        responder = next;
    }
    return false;
}

// A path is eligible only if it is one closed circle covering the surface.
// In particular this rejects rings with holes, glyphs, arcs and progress paths.
typedef struct {
    CGRect box;
    CGPoint current, start;
    unsigned moves, segments, closes;
    bool valid;
} BTCircleCheck;

static bool BTOnCircle(BTCircleCheck *check, CGPoint point) {
    double x = (point.x - CGRectGetMidX(check->box)) / (check->box.size.width * 0.5);
    double y = (point.y - CGRectGetMidY(check->box)) / (check->box.size.height * 0.5);
    return isfinite(x) && isfinite(y) && fabs(x * x + y * y - 1.0) < 0.045;
}

static void BTCheckCircleElement(void *context, const CGPathElement *element) {
    BTCircleCheck *check = context;
    if (!check->valid) return;
    CGPoint from = check->current, to = from;
    if (element->type == kCGPathElementMoveToPoint) {
        check->start = check->current = element->points[0];
        check->valid = ++check->moves == 1 && BTOnCircle(check, check->current);
        return;
    }
    if (element->type == kCGPathElementCloseSubpath) {
        ++check->closes;
        check->valid = hypot(from.x - check->start.x, from.y - check->start.y) < 0.5;
        return;
    }
    ++check->segments;
    for (unsigned sample = 1; sample <= 8; ++sample) {
        double t = sample / 8.0, u = 1.0 - t;
        switch (element->type) {
            case kCGPathElementAddLineToPoint:
                to = CGPointMake(u * from.x + t * element->points[0].x,
                                 u * from.y + t * element->points[0].y);
                break;
            case kCGPathElementAddQuadCurveToPoint:
                to = CGPointMake(u*u*from.x + 2*u*t*element->points[0].x + t*t*element->points[1].x,
                                 u*u*from.y + 2*u*t*element->points[0].y + t*t*element->points[1].y);
                break;
            case kCGPathElementAddCurveToPoint:
                to = CGPointMake(u*u*u*from.x + 3*u*u*t*element->points[0].x +
                                 3*u*t*t*element->points[1].x + t*t*t*element->points[2].x,
                                 u*u*u*from.y + 3*u*u*t*element->points[0].y +
                                 3*u*t*t*element->points[1].y + t*t*t*element->points[2].y);
                break;
            default: check->valid = false; return;
        }
        if (!BTOnCircle(check, to)) { check->valid = false; return; }
    }
    check->current = to;
}

static void BTShapeCirclePath(CALayer *layer, CGSize surfaceSize, CGFloat unitSide) {
    if (![layer isKindOfClass:[CAShapeLayer class]]) return;
    CAShapeLayer *shape = (CAShapeLayer *)layer;
    if (!shape.path || shape.strokeStart != 0 || shape.strokeEnd != 1 || shape.lineDashPattern.count) return;
    CGRect box = CGPathGetPathBoundingBox(shape.path);
    if (!BTIsSquareControl(box.size.width, box.size.height) ||
        fabs(box.size.width - surfaceSize.width) > 3.0 ||
        fabs(box.size.height - surfaceSize.height) > 3.0) return;
    BTCircleCheck check = { .box = box, .valid = true };
    CGPathApply(shape.path, &check, BTCheckCircleElement);
    if (!check.valid || check.moves != 1 || check.closes != 1 || check.segments < 4) return;
    shape.path = [UIBezierPath bezierPathWithRoundedRect:box
                     cornerRadius:BTShapeRadius(box.size.width, box.size.height,
                                               MIN(box.size.width, box.size.height) * 0.5, unitSide)].CGPath;
}

static void BTShapeLayer(CALayer *layer, CGSize surfaceSize, CGFloat unitSide, unsigned depth) {
    if (!layer || depth > 3 || layer.contents) return;
    CGSize size = layer.bounds.size;
    if (size.width <= 0 || size.height <= 0) size = surfaceSize;
    // Do not traverse a smaller glyph layer inside a material's layer tree.
    if (fabs(size.width - surfaceSize.width) > 3.0 ||
        fabs(size.height - surfaceSize.height) > 3.0) return;
    CGFloat old = layer.cornerRadius;
    CGFloat radius = BTShapeRadius(size.width, size.height, old, unitSide);
    if (radius > 0 && BTIsControlSurface(size.width, size.height) &&
        ![layer.cornerCurve isEqualToString:kCACornerCurveContinuous])
        layer.cornerCurve = kCACornerCurveContinuous;
    if (radius != old) {
        layer.cornerRadius = radius;
    }
    BTShapeCirclePath(layer, size, unitSide);
    if (layer.mask) BTShapeLayer(layer.mask, size, unitSide, depth + 1);
    for (CALayer *child in layer.sublayers) {
        // UIView-owned sublayers are handled by the view walker, which can
        // distinguish a button background from a same-sized symbol view.
        if ([child.delegate isKindOfClass:[UIView class]]) continue;
        BTShapeLayer(child, size, unitSide, depth + 1);
    }
}

static void BTShapeSurface(UIView *view, CGFloat unitSide) {
    if (!view || BTIsGroupedConnectivityButton(view) || BTInsideSlider(view) || BTIsGlyphOrChrome(view) ||
        !BTIsControlSurface(view.bounds.size.width, view.bounds.size.height)) return;
    CGFloat old = view.layer.cornerRadius;
    CGFloat radius = BTShapeRadius(view.bounds.size.width, view.bounds.size.height, old, unitSide);
    if (radius != old) {
        SEL setter = sel_registerName("_setContinuousCornerRadius:");
        if (BTMethodIs(object_getClass(view), setter, @encode(void), @encode(CGFloat)))
            ((void (*)(id, SEL, CGFloat))objc_msgSend)(view, setter, radius);
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.layer.cornerRadius = radius;
    }
    BTShapeLayer(view.layer, view.bounds.size, unitSide, 0);
    if (view.maskView) BTShapeLayer(view.maskView.layer, view.bounds.size, unitSide, 0);
}

static void BTShapeTree(UIView *view, CGFloat unitSide, unsigned depth, unsigned *remaining, bool force) {
    if (!view || depth > 12 || *remaining == 0 || BTIsGroupedConnectivityButton(view) ||
        BTInsideSlider(view) || BTIsGlyphOrChrome(view)) return;
    --*remaining;
    if (force || BTIsBackgroundView(view)) BTShapeSurface(view, unitSide);
    for (UIView *child in view.subviews) BTShapeTree(child, unitSide, depth + 1, remaining, false);
}

static void BTStyleView(UIView *view) {
    if (![view isKindOfClass:[UIView class]] || BTIsGroupedConnectivityButton(view) || BTInsideSlider(view)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    unsigned remaining = 384;
    CGFloat unitSide = BTUnitForObject(view);
    BTShapeTree(view, unitSide, 0, &remaining, true);
    // These can be plain UIView instances, so use their semantic properties
    // instead of treating every plain UIView as a background.
    const char *properties[] = {"backgroundView", "normalStateBackgroundView",
        "selectedStateBackgroundView", "alternateSelectedStateBackgroundView", "moduleMaterialView"};
    for (unsigned i = 0; i < sizeof(properties)/sizeof(properties[0]); ++i) {
        id background = BTObjectProperty(view, properties[i]);
        if ([background isKindOfClass:[UIView class]]) BTShapeSurface(background, unitSide);
    }
    id highlight = BTObjectIvar(view, "_highlightedBackgroundView");
    if ([highlight isKindOfClass:[UIView class]]) BTShapeSurface(highlight, unitSide);
    [CATransaction commit];
}

static void BTStyleController(id controller) {
    if (![controller isKindOfClass:[UIViewController class]]) return;
    BTStyleView(((UIViewController *)controller).viewIfLoaded);
    const char *ivars[] = {"_contentContainerView", "_maskView", "_editingBorderView",
                          "_editingBorderMaskView", "_editingBorderContainerView"};
    for (unsigned i = 0; i < sizeof(ivars)/sizeof(ivars[0]); ++i) {
        id view = BTObjectIvar(controller, ivars[i]);
        if ([view isKindOfClass:[UIView class]]) BTStyleView(view);
    }
}

static char BTApplyingFocusKey;
static void BTStyleFocusControl(id control) {
    if (!BTFocusHasControlCenterOwner(control) || objc_getAssociatedObject(control, &BTApplyingFocusKey)) return;
    objc_setAssociatedObject(control, &BTApplyingFocusKey, [NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    @try {
        CGFloat unitSide = BTUnitForObject(control);
        BTShapeSurface(control, unitSide);
        // These exact views own the row's background and clipping. Avoid
        // touching text, glyphs, options buttons or individual menu actions.
        const char *parts[] = {"_backgroundView", "_contentView"};
        for (unsigned i = 0; i < sizeof(parts)/sizeof(parts[0]); ++i) {
            id part = BTObjectIvar(control, parts[i]);
            if ([part isKindOfClass:[UIView class]]) BTShapeSurface(part, unitSide);
        }
    } @finally {
        [CATransaction commit];
        objc_setAssociatedObject(control, &BTApplyingFocusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static CGFloat (*BTOrig_FocusFrameRadius)(id, SEL, CGRect);
static CGFloat BTHook_FocusFrameRadius(id self, SEL cmd, CGRect frame) {
    CGFloat native = BTOrig_FocusFrameRadius(self, cmd, frame);
    if (!BTFocusHasControlCenterOwner(self)) return native;
    // Use the incoming layout frame, not the still-compact bounds of a reused
    // DND control. Native background/clipping setup consumes this value.
    return BTShapeRadius(frame.size.width, frame.size.height, native, BTUnitForObject(self));
}

#define BT_FOCUS_RADIUS_SETTER(tag) \
    static void (*BTOrig_##tag)(id, SEL, CGFloat); \
    static void BTHook_##tag(id self, SEL cmd, CGFloat radius) { \
        BTOrig_##tag(self, cmd, BTFocusHasControlCenterOwner(self) ? BTRadiusForObject(self, radius) : radius); \
    }
BT_FOCUS_RADIUS_SETTER(FocusBackgroundRadius)
BT_FOCUS_RADIUS_SETTER(FocusBackgroundContinuousRadius)

#define BT_FOCUS_LAYOUT(tag) \
    static void (*BTOrig_##tag)(id, SEL); \
    static void BTHook_##tag(id self, SEL cmd) { \
        BTOrig_##tag(self, cmd); BTStyleFocusControl(self); \
    }
BT_FOCUS_LAYOUT(FocusLayout)
BT_FOCUS_LAYOUT(FocusSuperview)
BT_FOCUS_LAYOUT(FocusWindow)
BT_FOCUS_LAYOUT(FocusBackgroundConfigured)

// Each hook has its own typed original pointer. This is important when an
// overridden method calls a hooked superclass method: no receiver-based
// original-IMP lookup and no accidental recursion into the subclass.
#define BT_RADIUS_GETTER(tag) \
    static CGFloat (*BTOrig_##tag)(id, SEL); \
    static CGFloat BTHook_##tag(id self, SEL cmd) { \
        return BTRadiusForObject(self, BTOrig_##tag(self, cmd)); \
    }
#define BT_RADIUS_SETTER(tag) \
    static void (*BTOrig_##tag)(id, SEL, CGFloat); \
    static void BTHook_##tag(id self, SEL cmd, CGFloat value) { \
        BTOrig_##tag(self, cmd, BTRadiusForObject(self, value)); \
    }
#define BT_INFO_GETTER(tag) \
    static SBIconImageInfo (*BTOrig_##tag)(id, SEL); \
    static SBIconImageInfo BTHook_##tag(id self, SEL cmd) { \
        return BTFixImageInfo(BTOrig_##tag(self, cmd), BTUnitForObject(self)); \
    }
#define BT_INFO_SETTER(tag) \
    static void (*BTOrig_##tag)(id, SEL, SBIconImageInfo); \
    static void BTHook_##tag(id self, SEL cmd, SBIconImageInfo value) { \
        BTOrig_##tag(self, cmd, BTFixImageInfo(value, BTUnitForObject(self))); \
    }
#define BT_GRID_INFO_GETTER(tag) \
    static SBIconImageInfo (*BTOrig_##tag)(id, SEL, id); \
    static SBIconImageInfo BTHook_##tag(id self, SEL cmd, id grid) { \
        return BTFixImageInfo(BTOrig_##tag(self, cmd, grid), BTUnitForLayout(self)); \
    }
#define BT_BASE_INFO_GETTER(tag, kind) \
    static SBIconImageInfo (*BTOrig_##tag)(id, SEL); \
    static SBIconImageInfo BTHook_##tag(id self, SEL cmd) { \
        SBIconImageInfo info = BTOrig_##tag(self, cmd); \
        return BTFixImageInfo(info, BTRecordLayoutUnit(kind, info.size)); \
    }
#define BT_VIEW_LAYOUT(tag) \
    static void (*BTOrig_##tag)(id, SEL); \
    static void BTHook_##tag(id self, SEL cmd) { \
        BTOrig_##tag(self, cmd); BTStyleView(self); \
    }
#define BT_CONTROLLER_LAYOUT(tag) \
    static void (*BTOrig_##tag)(id, SEL); \
    static void BTHook_##tag(id self, SEL cmd) { \
        BTOrig_##tag(self, cmd); BTStyleController(self); \
    }

// Round-button instances can be created before they enter a view/controller
// hierarchy. Reapply their native circular radius once their connectivity
// owner is known, including every native selected/highlighted background.
static CGFloat BTConnectivityButtonRadius(UIView *view, CGFloat fallback) {
    CGSize size = view.bounds.size;
    return BTIsSquareControl(size.width, size.height) ? MIN(size.width, size.height) * 0.5 : fallback;
}

static CGFloat (*BTOrig_RoundGet)(id, SEL);
static CGFloat BTHook_RoundGet(id self, SEL cmd) {
    CGFloat value = BTOrig_RoundGet(self, cmd);
    return BTInConnectivityGroup(self) ? BTConnectivityButtonRadius(self, value) : BTRadiusForObject(self, value);
}

static void (*BTOrig_RoundSet)(id, SEL, CGFloat);
static void BTHook_RoundSet(id self, SEL cmd, CGFloat value) {
    CGFloat radius = BTInConnectivityGroup(self) ? BTConnectivityButtonRadius(self, value) : BTRadiusForObject(self, value);
    BTOrig_RoundSet(self, cmd, radius);
}

static void (*BTOrig_RoundLayout)(id, SEL);
static void BTHook_RoundLayout(id self, SEL cmd) {
    BTOrig_RoundLayout(self, cmd);
    if (BTInConnectivityGroup(self)) {
        CGSize size = ((UIView *)self).bounds.size;
        if (BTOrig_RoundSet && BTIsSquareControl(size.width, size.height))
            BTOrig_RoundSet(self, sel_registerName("_setCornerRadius:"), MIN(size.width, size.height) * 0.5);
    } else {
        BTStyleView(self);
    }
}

BT_RADIUS_GETTER(ButtonGet)
BT_RADIUS_SETTER(ButtonSet)
BT_VIEW_LAYOUT(ButtonLayout)
BT_RADIUS_GETTER(TemplateGet)
BT_RADIUS_SETTER(TemplateSet)
BT_VIEW_LAYOUT(TemplateLayout)
BT_RADIUS_GETTER(HostGet)
BT_RADIUS_SETTER(HostSet)
BT_VIEW_LAYOUT(HostLayout)
BT_RADIUS_GETTER(ContainerCompactGet)
BT_RADIUS_SETTER(ContainerCompactSet)
BT_RADIUS_GETTER(ContainerExpandedGet)
BT_RADIUS_SETTER(ContainerExpandedSet)
BT_RADIUS_SETTER(ContainerPrivateSet)
BT_VIEW_LAYOUT(ContainerLayout)
BT_INFO_GETTER(ModuleInfoGet)
BT_INFO_SETTER(ModuleInfoSet)
BT_RADIUS_GETTER(ModuleRadiusGet)
BT_CONTROLLER_LAYOUT(ModuleLayout)
BT_INFO_GETTER(GalleryInfoGet)
BT_INFO_SETTER(GalleryInfoSet)
BT_RADIUS_GETTER(GalleryRadiusGet)
BT_CONTROLLER_LAYOUT(GalleryLayout)
BT_BASE_INFO_GETTER(MainLayoutInfo, 1)
BT_GRID_INFO_GETTER(MainLayoutGridInfo)
BT_BASE_INFO_GETTER(GalleryLayoutInfo, 2)
BT_GRID_INFO_GETTER(GalleryLayoutGridInfo)
BT_VIEW_LAYOUT(EmptyCellLayout)

// Sliders own additional elastic and value-clipping surfaces. Supplying the
// radius through their native API updates those together, while preserving
// the straight boundary between the filled and unfilled portions.
static char BTApplyingSliderKey, BTSteppedRadiusKey;
static CGFloat (*BTOrig_SliderGet)(id, SEL);
static CGFloat BTHook_SliderGet(id self, SEL cmd) {
    CGFloat radius = BTOrig_SliderGet(self, cmd);
    return BTInsideControl(self) ? BTRadiusForObject(self, radius) : radius;
}

#define BT_SLIDER_RADIUS_SETTER(tag) \
    static void (*BTOrig_##tag)(id, SEL, CGFloat); \
    static void BTHook_##tag(id self, SEL cmd, CGFloat radius) { \
        BTOrig_##tag(self, cmd, BTInsideControl(self) ? BTRadiusForObject(self, radius) : radius); \
    }
BT_SLIDER_RADIUS_SETTER(SliderSet)
BT_SLIDER_RADIUS_SETTER(ContinuousSliderSet)
BT_SLIDER_RADIUS_SETTER(SteppedSliderSet)

static bool BTSteppedSliderNeedsRadius(id slider, CGFloat radius) {
    Class stepped = objc_getClass("CCUISteppedSliderView");
    if (!stepped || ![slider isKindOfClass:stepped] || !isfinite(radius) || radius <= 0) return false;
    NSNumber *last = objc_getAssociatedObject(slider, &BTSteppedRadiusKey);
    if (!last || last.doubleValue != radius) return true;
    // The subclass can retain a different container radius even when the
    // base-class property is already correct. Detect that exact mismatch.
    id container = BTObjectIvar(slider, "_stepViewsContainer");
    if (![container isKindOfClass:[UIView class]]) return false;
    CGFloat actual = ((UIView *)container).layer.cornerRadius;
    return isfinite(actual) && actual > 0 && fabs(actual - radius) > 0.000001;
}

static void BTStyleSlider(id slider) {
    if (!BTInsideControl(slider) || objc_getAssociatedObject(slider, &BTApplyingSliderKey)) return;
    objc_setAssociatedObject(slider, &BTApplyingSliderKey, [NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        SEL setter = sel_registerName("setContinuousSliderCornerRadius:");
        if (BTOrig_SliderGet && BTMethodIs(object_getClass(slider), setter, @encode(void), @encode(CGFloat))) {
            CGFloat old = BTOrig_SliderGet(slider, sel_registerName("continuousSliderCornerRadius"));
            CGFloat radius = BTRadiusForObject(slider, old);
            if (radius != old || BTSteppedSliderNeedsRadius(slider, radius)) {
                ((void (*)(id, SEL, CGFloat))objc_msgSend)(slider, setter, radius);
                Class stepped = objc_getClass("CCUISteppedSliderView");
                if (stepped && [slider isKindOfClass:stepped] && isfinite(radius) && radius > 0)
                    objc_setAssociatedObject(slider, &BTSteppedRadiusKey, @(radius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        // Do not walk the slider's partial fill as though it were another
        // module. Its native setter owns the elastic, fill and clipping views.
    } @finally {
        objc_setAssociatedObject(slider, &BTApplyingSliderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#define BT_SLIDER_LAYOUT(tag) \
    static void (*BTOrig_##tag)(id, SEL); \
    static void BTHook_##tag(id self, SEL cmd) { \
        BTOrig_##tag(self, cmd); BTStyleSlider(self); \
    }
BT_SLIDER_LAYOUT(SliderLayout)
BT_SLIDER_LAYOUT(SliderWindow)
BT_SLIDER_LAYOUT(ContinuousSliderElasticLayout)
BT_SLIDER_LAYOUT(SteppedSliderElasticLayout)
BT_SLIDER_LAYOUT(SteppedSliderStepsLayout)
BT_SLIDER_LAYOUT(SteppedSliderWindow)

static void (*BTOrig_MaterialLayout)(id, SEL);
static void BTHook_MaterialLayout(id self, SEL cmd) {
    BTOrig_MaterialLayout(self, cmd);
    if (BTInsideControl(self) && !BTInsideSlider(self)) BTStyleView(self);
}
static void (*BTOrig_MaterialRadius)(id, SEL, CGFloat);
static void BTHook_MaterialRadius(id self, SEL cmd, CGFloat value) {
    BTOrig_MaterialRadius(self, cmd, BTInsideControl(self) && !BTInsideSlider(self) ? BTRadiusForObject(self, value) : value);
}

static void BTInstall(const char *className, const char *selectorName, IMP replacement,
                      IMP *original, const char *result, const char *argument) {
    if (*original) return;
    Class cls = objc_getClass(className);
    SEL selector = sel_registerName(selectorName);
    if (cls && BTMethodIs(cls, selector, result, argument))
        MSHookMessageEx(cls, selector, replacement, original);
}

#define BT_HOOK(cls, selector, tag, result, argument) \
    BTInstall(cls, selector, (IMP)BTHook_##tag, (IMP *)&BTOrig_##tag, result, argument)

static void BTInstallHooks(void) {
    BT_HOOK("CCUIRoundButton", "_cornerRadius", RoundGet, @encode(CGFloat), NULL);
    BT_HOOK("CCUIRoundButton", "_setCornerRadius:", RoundSet, @encode(void), @encode(CGFloat));
    BT_HOOK("CCUIRoundButton", "layoutSubviews", RoundLayout, @encode(void), NULL);
    BT_HOOK("CCUIButtonModuleView", "_continuousCornerRadius", ButtonGet, @encode(CGFloat), NULL);
    BT_HOOK("CCUIButtonModuleView", "_setContinuousCornerRadius:", ButtonSet, @encode(void), @encode(CGFloat));
    BT_HOOK("CCUIButtonModuleView", "layoutSubviews", ButtonLayout, @encode(void), NULL);
    BT_HOOK("CCUIControlTemplateView", "continuousCornerRadius", TemplateGet, @encode(CGFloat), NULL);
    BT_HOOK("CCUIControlTemplateView", "setContinuousCornerRadius:", TemplateSet, @encode(void), @encode(CGFloat));
    BT_HOOK("CCUIControlTemplateView", "layoutSubviews", TemplateLayout, @encode(void), NULL);
    BT_HOOK("CCUIControlHostView", "continuousCornerRadius", HostGet, @encode(CGFloat), NULL);
    BT_HOOK("CCUIControlHostView", "setContinuousCornerRadius:", HostSet, @encode(void), @encode(CGFloat));
    BT_HOOK("CCUIControlHostView", "layoutSubviews", HostLayout, @encode(void), NULL);
    BT_HOOK("CCUIContentModuleContentContainerView", "compactContinuousCornerRadius", ContainerCompactGet, @encode(CGFloat), NULL);
    BT_HOOK("CCUIContentModuleContentContainerView", "setCompactContinuousCornerRadius:", ContainerCompactSet, @encode(void), @encode(CGFloat));
    BT_HOOK("CCUIContentModuleContentContainerView", "expandedContinuousCornerRadius", ContainerExpandedGet, @encode(CGFloat), NULL);
    BT_HOOK("CCUIContentModuleContentContainerView", "setExpandedContinuousCornerRadius:", ContainerExpandedSet, @encode(void), @encode(CGFloat));
    BT_HOOK("CCUIContentModuleContentContainerView", "_setContinuousCornerRadius:", ContainerPrivateSet, @encode(void), @encode(CGFloat));
    BT_HOOK("CCUIContentModuleContentContainerView", "layoutSubviews", ContainerLayout, @encode(void), NULL);
    BT_HOOK("CCUIContentModuleContainerViewController", "iconImageInfo", ModuleInfoGet, @encode(SBIconImageInfo), NULL);
    BT_HOOK("CCUIContentModuleContainerViewController", "setIconImageInfo:", ModuleInfoSet, @encode(void), @encode(SBIconImageInfo));
    BT_HOOK("CCUIContentModuleContainerViewController", "continuousCornerRadius", ModuleRadiusGet, @encode(CGFloat), NULL);
    BT_HOOK("CCUIContentModuleContainerViewController", "viewDidLayoutSubviews", ModuleLayout, @encode(void), NULL);
    const char *gallery = "_TtC23ControlCenterUIServices30ControlContainerViewController";
    BT_HOOK(gallery, "iconImageInfo", GalleryInfoGet, @encode(SBIconImageInfo), NULL);
    BT_HOOK(gallery, "setIconImageInfo:", GalleryInfoSet, @encode(void), @encode(SBIconImageInfo));
    BT_HOOK(gallery, "continuousCornerRadius", GalleryRadiusGet, @encode(CGFloat), NULL);
    BT_HOOK(gallery, "viewDidLayoutSubviews", GalleryLayout, @encode(void), NULL);
    BT_HOOK("_TtC15ControlCenterUI14IconListLayout", "iconImageInfo", MainLayoutInfo, @encode(SBIconImageInfo), NULL);
    BT_HOOK("_TtC15ControlCenterUI14IconListLayout", "iconImageInfoForGridSizeClass:", MainLayoutGridInfo, @encode(SBIconImageInfo), @encode(id));
    const char *galleryLayout = "_TtC23ControlCenterUIServices29ControlsGalleryIconListLayout";
    BT_HOOK(galleryLayout, "iconImageInfo", GalleryLayoutInfo, @encode(SBIconImageInfo), NULL);
    BT_HOOK(galleryLayout, "iconImageInfoForGridSizeClass:", GalleryLayoutGridInfo, @encode(SBIconImageInfo), @encode(id));
    BT_HOOK("_TtC15ControlCenterUI13EmptyGridCell", "layoutSubviews", EmptyCellLayout, @encode(void), NULL);
    BT_HOOK("CCUIBaseSliderView", "continuousSliderCornerRadius", SliderGet, @encode(CGFloat), NULL);
    BT_HOOK("CCUIBaseSliderView", "setContinuousSliderCornerRadius:", SliderSet, @encode(void), @encode(CGFloat));
    BT_HOOK("CCUIContinuousSliderView", "setContinuousSliderCornerRadius:", ContinuousSliderSet, @encode(void), @encode(CGFloat));
    BT_HOOK("CCUISteppedSliderView", "setContinuousSliderCornerRadius:", SteppedSliderSet, @encode(void), @encode(CGFloat));
    BT_HOOK("CCUIBaseSliderView", "layoutSubviews", SliderLayout, @encode(void), NULL);
    BT_HOOK("CCUIBaseSliderView", "didMoveToWindow", SliderWindow, @encode(void), NULL);
    BT_HOOK("CCUIContinuousSliderView", "layoutElasticContentViews", ContinuousSliderElasticLayout, @encode(void), NULL);
    BT_HOOK("CCUISteppedSliderView", "layoutElasticContentViews", SteppedSliderElasticLayout, @encode(void), NULL);
    BT_HOOK("CCUISteppedSliderView", "_layoutStepViews", SteppedSliderStepsLayout, @encode(void), NULL);
    BT_HOOK("CCUISteppedSliderView", "didMoveToWindow", SteppedSliderWindow, @encode(void), NULL);
    BT_HOOK("FCUIActivityControl", "_cornerRadiusForControlFrame:", FocusFrameRadius, @encode(CGFloat), @encode(CGRect));
    BT_HOOK("FCUIActivityControl", "layoutSubviews", FocusLayout, @encode(void), NULL);
    BT_HOOK("FCUIActivityControl", "didMoveToSuperview", FocusSuperview, @encode(void), NULL);
    BT_HOOK("FCUIActivityControl", "didMoveToWindow", FocusWindow, @encode(void), NULL);
    BT_HOOK("FCUIActivityControl", "_configureBackgroundViewIfNecesssary", FocusBackgroundConfigured, @encode(void), NULL);
    BT_HOOK("_FCUIActivityControlBackgroundView", "_setCornerRadius:", FocusBackgroundRadius, @encode(void), @encode(CGFloat));
    BT_HOOK("_FCUIActivityControlBackgroundView", "_setContinuousCornerRadius:", FocusBackgroundContinuousRadius, @encode(void), @encode(CGFloat));
    BT_HOOK("MTMaterialView", "layoutSubviews", MaterialLayout, @encode(void), NULL);
    BT_HOOK("MTMaterialView", "setContinuousCornerRadius:", MaterialRadius, @encode(void), @encode(CGFloat));
}

static volatile int BTInstallQueued;
static void BTInstallOnMainQueue(void *context) {
    (void)context;
    __sync_lock_test_and_set(&BTInstallQueued, 0);
    @autoreleasepool { BTInstallHooks(); }
}

static void BTImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    // ObjC/Swift classes may not be registered until after dyld's callback.
    // The main-queue retry also handles frameworks loaded by a later submenu.
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
