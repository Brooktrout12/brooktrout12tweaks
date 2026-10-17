#import "BSAnimationEffects.h"
#include <math.h>

static void BSKeyframes(CALayer *layer, NSString *keyPath, NSArray *values,
                         NSArray<NSNumber *> *times, double duration, NSString *curve) {
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:keyPath];
    animation.values = values;
    animation.keyTimes = times;
    animation.duration = duration;
    animation.calculationMode = kCAAnimationLinear;
    NSMutableArray *curves = [NSMutableArray arrayWithCapacity:times.count - 1];
    for (NSUInteger i = 1; i < times.count; ++i)
        [curves addObject:[CAMediaTimingFunction functionWithName:curve]];
    animation.timingFunctions = curves;
    // Set the final model value first so removal cannot flash the full image.
    [layer setValue:values.lastObject forKeyPath:keyPath];
    [layer addAnimation:animation forKey:[@"BlurSleep." stringByAppendingString:keyPath]];
}

static void BSOriginalBlur(CALayer *layer, double duration) {
    // Same radius, opacity and timing as the user-confirmed 1.0.2 renderer.
    layer.opacity = 0;
    [layer setValue:@36 forKeyPath:@"filters.sleepBlur.inputRadius"];
    CABasicAnimation *blur = [CABasicAnimation animationWithKeyPath:@"filters.sleepBlur.inputRadius"];
    blur.fromValue = @0; blur.toValue = @36;
    blur.duration = duration;
    blur.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @1; fade.toValue = @0;
    fade.duration = duration;
    fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:blur forKey:@"BlurSleep.blur"];
    [layer addAnimation:fade forKey:@"BlurSleep.fade"];
}

static void BSCRT(UIImageView *image, UIView *container, double duration) {
    CALayer *layer = image.layer;
    CGFloat thin = 1.5 / MAX(1.0, image.bounds.size.height);
    // Symmetric compression about the default center anchor: top and bottom
    // meet first. Width contracts only once the image is a horizontal line.
    BSKeyframes(layer,@"transform.scale.y",@[@1,@0.96,@(thin),@(thin),@(thin)],
        @[@0,@0.12,@0.62,@0.82,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
    BSKeyframes(layer,@"transform.scale.x",@[@1,@1,@0.75,@0.001],
        @[@0,@0.66,@0.82,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
    BSKeyframes(layer,@"opacity",@[@1,@1,@0,@0],
        @[@0,@0.60,@0.76,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);

    // A narrow phosphor-like glow, never a full-screen white flash.
    CALayer *line = [CALayer layer];
    line.name = @"BlurSleep.CRTGlow";
    line.bounds = CGRectMake(0,0,container.bounds.size.width,1.5);
    line.position = CGPointMake(CGRectGetMidX(container.bounds),CGRectGetMidY(container.bounds));
    line.backgroundColor = UIColor.whiteColor.CGColor;
    line.cornerRadius = 0.75;
    line.shadowColor = UIColor.whiteColor.CGColor;
    line.shadowOpacity = 0.85;
    line.shadowRadius = 6;
    line.shadowOffset = CGSizeZero;
    [container.layer addSublayer:line];
    BSKeyframes(line,@"opacity",@[@0,@0,@1,@0.65,@0],
        @[@0,@0.56,@0.68,@0.92,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
    BSKeyframes(line,@"transform.scale.x",@[@1,@1,@0.002,@0.002],
        @[@0,@0.68,@0.94,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
}

static void BSIris(UIImageView *image, double duration) {
    CGSize size = image.bounds.size;
    // A circle as large as the diagonal includes all four screen corners.
    CGFloat diameter = hypot(size.width,size.height) + 2;
    CALayer *mask = [CALayer layer];
    mask.name = @"BlurSleep.IrisMask";
    mask.bounds = CGRectMake(0,0,diameter,diameter);
    mask.position = CGPointMake(CGRectGetMidX(image.bounds),CGRectGetMidY(image.bounds));
    mask.cornerRadius = diameter / 2;
    mask.backgroundColor = UIColor.blackColor.CGColor;
    mask.masksToBounds = YES;
    image.layer.mask = mask;
    BSKeyframes(mask,@"transform.scale",@[@1,@0.70,@0.001],
        @[@0,@0.4,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
    BSKeyframes(image.layer,@"opacity",@[@1,@1,@0],
        @[@0,@0.94,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
}

static void BSShrink(UIImageView *image, double duration) {
    BSKeyframes(image.layer,@"transform.scale",@[@1,@0.88,@0.001],
        @[@0,@0.22,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
    BSKeyframes(image.layer,@"cornerRadius",@[@0,@28,@28],
        @[@0,@0.25,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
    BSKeyframes(image.layer,@"opacity",@[@1,@1,@0],
        @[@0,@0.72,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
}

static void BSSlide(UIImageView *image, UIView *container, double duration) {
    CGFloat y = image.layer.position.y;
    BSKeyframes(image.layer,@"position.y",@[@(y),@(y + container.bounds.size.height * 1.05)],
        @[@0,@1],duration,kCAMediaTimingFunctionEaseIn);
    BSKeyframes(image.layer,@"opacity",@[@1,@1,@0],
        @[@0,@0.72,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
}

static void BSFlip(UIImageView *image, double duration) {
    CGFloat distance = MAX(image.bounds.size.width,image.bounds.size.height) * 2;
    CATransform3D perspective = CATransform3DIdentity;
    perspective.m34 = -1.0 / MAX(1.0,distance);
    CATransform3D middle = CATransform3DRotate(perspective,M_PI * 0.22,0,1,0);
    middle = CATransform3DScale(middle,0.92,0.92,1);
    CATransform3D end = CATransform3DRotate(perspective,M_PI_2,0,1,0);
    end = CATransform3DScale(end,0.8,0.8,1);
    image.layer.doubleSided = NO;
    BSKeyframes(image.layer,@"transform",@[[NSValue valueWithCATransform3D:perspective],
        [NSValue valueWithCATransform3D:middle],[NSValue valueWithCATransform3D:end]],
        @[@0,@0.55,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
    BSKeyframes(image.layer,@"opacity",@[@1,@1,@0],
        @[@0,@0.65,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
}

// Keep exactly the same path commands, including when the radius is zero.
// Core Animation can then interpolate every rounded contour without snapping
// between a rectangle, capsule and circle. Coordinates are centered at (0,0).
static UIBezierPath *BSGlassContour(CGRect rect, CGFloat radius) {
    CGFloat r = MAX(0,MIN(radius,MIN(rect.size.width,rect.size.height) * 0.5));
    CGFloat x0 = CGRectGetMinX(rect), x1 = CGRectGetMaxX(rect);
    CGFloat y0 = CGRectGetMinY(rect), y1 = CGRectGetMaxY(rect);
    CGFloat c = r * 0.5522847498;
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(x0+r,y0)];
    [p addLineToPoint:CGPointMake(x1-r,y0)];
    [p addCurveToPoint:CGPointMake(x1,y0+r) controlPoint1:CGPointMake(x1-r+c,y0)
        controlPoint2:CGPointMake(x1,y0+r-c)];
    [p addLineToPoint:CGPointMake(x1,y1-r)];
    [p addCurveToPoint:CGPointMake(x1-r,y1) controlPoint1:CGPointMake(x1,y1-r+c)
        controlPoint2:CGPointMake(x1-r+c,y1)];
    [p addLineToPoint:CGPointMake(x0+r,y1)];
    [p addCurveToPoint:CGPointMake(x0,y1-r) controlPoint1:CGPointMake(x0+r-c,y1)
        controlPoint2:CGPointMake(x0,y1-r+c)];
    [p addLineToPoint:CGPointMake(x0,y0+r)];
    [p addCurveToPoint:CGPointMake(x0+r,y0) controlPoint1:CGPointMake(x0,y0+r-c)
        controlPoint2:CGPointMake(x0+r-c,y0)];
    [p closePath];
    return p;
}

static NSArray *BSGlassPaths(NSArray<NSValue *> *bounds, NSArray<NSNumber *> *radii,
                              NSInteger band) {
    NSMutableArray *paths = [NSMutableArray arrayWithCapacity:bounds.count];
    for (NSUInteger i = 0; i < bounds.count; ++i) {
        CGRect rect = bounds[i].CGRectValue;
        CGFloat shortSide = MIN(rect.size.width,rect.size.height);
        // Four adjacent rings concentrate the texture displacement at the rim.
        // Scale the rim down with the droplet so no inner contour can invert.
        CGFloat rim = MIN(18.0,shortSide * 0.22);
        CGFloat inset = band >= 0 ? rim * band / 4.0 : 0;
        CGFloat thickness = band >= 0 ? rim / 4.0 + MIN(0.3,shortSide * 0.01)
                                     : MIN(1.15,shortSide * 0.08);
        CGRect outer = CGRectInset(rect,inset,inset);
        CGRect inner = CGRectInset(outer,thickness,thickness);
        CGFloat r = radii[i].doubleValue - inset;
        UIBezierPath *path = BSGlassContour(outer,r);
        [path appendPath:BSGlassContour(inner,r - thickness)];
        // The array retains each CGPath after its temporary UIBezierPath dies.
        [paths addObject:(__bridge id)path.CGPath];
    }
    return paths;
}

static CAShapeLayer *BSGlassMask(CGRect bounds, NSArray *paths,
                                  NSArray<NSNumber *> *times, double duration) {
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.bounds = bounds;
    mask.position = CGPointZero;
    mask.fillColor = UIColor.whiteColor.CGColor;
    mask.fillRule = kCAFillRuleEvenOdd;
    // Use the typed CGPath setter; do not depend on KVC boxing a CF pointer.
    mask.path = (__bridge CGPathRef)paths.lastObject;
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"path"];
    animation.values = paths;
    animation.keyTimes = times;
    animation.duration = duration;
    animation.calculationMode = kCAAnimationLinear;
    [mask addAnimation:animation forKey:@"BlurSleep.GlassPath"];
    return mask;
}

static CALayer *BSGlassTexture(UIImageView *image, CGRect bounds) {
    CALayer *texture = [CALayer layer];
    texture.bounds = bounds;
    texture.position = CGPointZero;
    texture.contents = (__bridge id)image.image.CGImage;
    texture.contentsScale = image.image.scale;
    texture.contentsGravity = kCAGravityResizeAspectFill;
    texture.minificationFilter = kCAFilterTrilinear;
    // All lenses share the one existing screenshot; no repeated captures,
    // image processing on a display link, or iOS 26-only material APIs.
    return texture;
}

static double BSGlassTangent(const CGFloat *values, const double *stops, NSUInteger i) {
    if (i == 0 || i == 7) return 0;
    double leftTime = stops[i] - stops[i-1], rightTime = stops[i+1] - stops[i];
    double left = (values[i] - values[i-1]) / leftTime;
    double right = (values[i+1] - values[i]) / rightTime;
    if (left * right <= 0) return 0;
    double a = 2 * rightTime + leftTime, b = rightTime + 2 * leftTime;
    return (a+b) / (a/left + b/right);
}

static CGFloat BSGlassInterpolate(const CGFloat *values, const double *stops,
                                    NSUInteger segment, double u) {
    // Shape-preserving cubic Hermite interpolation: continuous velocity at
    // each stop, with no overshoot into negative sizes or excessive corners.
    double u2 = u*u, u3 = u2*u, dt = stops[segment+1] - stops[segment];
    return (2*u3-3*u2+1) * values[segment]
         + (u3-2*u2+u) * dt * BSGlassTangent(values,stops,segment)
         + (-2*u3+3*u2) * values[segment+1]
         + (u3-u2) * dt * BSGlassTangent(values,stops,segment+1);
}

static void BSLiquidGlass(UIImageView *image, UIView *container, double duration) {
    CGFloat w = image.bounds.size.width, h = image.bounds.size.height;
    CGRect full = CGRectMake(-w * 0.5,-h * 0.5,w,h);
    // A slight lateral swell while the lens compresses gives the motion a
    // liquid feel. Then the capsule gathers into a small round pearl.
    const double stops[] = {0,0.16,0.34,0.54,0.72,0.86,0.94,1};
    const CGFloat widths[] = {1,0.94,0.90,0.94,0.67,0.24,0.055,0};
    const CGFloat heights[] = {1,0.94,0.79,0.39,0.13,0.10,0.025,0};
    const CGFloat corners[] = {0,0.12,0.22,0.50,0.50,0.50,0.50,0.50};
    NSMutableArray<NSValue *> *bounds = [NSMutableArray array];
    NSMutableArray<NSNumber *> *radii = [NSMutableArray array];
    NSMutableArray<NSNumber *> *times = [NSMutableArray array];
    NSMutableArray<NSNumber *> *zooms = [NSMutableArray array];
    // Sample a smooth cubic trajectory once. Every contour and texture uses
    // the same samples, avoiding eight separate stop/start easing segments.
    for (NSUInteger sample = 0; sample <= 48; ++sample) {
        double t = (double)sample / 48.0;
        NSUInteger segment = 0;
        while (segment < 6 && t > stops[segment+1]) ++segment;
        double u = (t - stops[segment]) / (stops[segment+1] - stops[segment]);
        CGFloat bw = MAX(0.8,w * BSGlassInterpolate(widths,stops,segment,u));
        CGFloat bh = MAX(0.8,h * BSGlassInterpolate(heights,stops,segment,u));
        CGFloat radius = MIN(bw,bh) * BSGlassInterpolate(corners,stops,segment,u);
        [bounds addObject:[NSValue valueWithCGRect:CGRectMake(-bw*0.5,-bh*0.5,bw,bh)]];
        [radii addObject:@(radius)];
        [times addObject:@(t)];
        [zooms addObject:@(1.0 + sin(M_PI * t) * 0.055)];
    }

    CALayer *glass = [CALayer layer];
    glass.name = @"BlurSleep.LiquidGlass";
    glass.bounds = full;
    glass.position = CGPointMake(CGRectGetMidX(image.frame),CGRectGetMidY(image.frame));
    [container.layer addSublayer:glass];
    // An animated path also clips the highlight and the refraction bands.
    // Centered coordinates keep every sublayer aligned as the lens changes size.
    NSMutableArray *outline = [NSMutableArray arrayWithCapacity:bounds.count];
    for (NSUInteger i = 0; i < bounds.count; ++i)
        [outline addObject:(__bridge id)BSGlassContour(bounds[i].CGRectValue,radii[i].doubleValue).CGPath];
    glass.mask = BSGlassMask(full,outline,times,duration);
    glass.mask.name = @"BlurSleep.GlassSilhouette";
    CALayer *body = BSGlassTexture(image,full);
    [glass addSublayer:body];
    BSKeyframes(body,@"transform.scale",zooms,times,duration,kCAMediaTimingFunctionLinear);

    for (NSInteger band = 3; band >= 0; --band) {
        CALayer *lens = [CALayer layer];
        lens.name = @"BlurSleep.GlassRefraction";
        lens.bounds = full;
        lens.position = CGPointZero;
        lens.mask = BSGlassMask(full,BSGlassPaths(bounds,radii,band),times,duration);
        CALayer *texture = BSGlassTexture(image,full);
        [lens addSublayer:texture];
        [glass addSublayer:lens];
        NSMutableArray *bentZooms = [NSMutableArray arrayWithCapacity:times.count];
        for (NSUInteger i = 0; i < times.count; ++i) {
            double t = times[i].doubleValue;
            [bentZooms addObject:@(zooms[i].doubleValue + sin(M_PI*t) * (4-band) * 0.027)];
        }
        BSKeyframes(texture,@"transform.scale",bentZooms,times,duration,kCAMediaTimingFunctionLinear);
    }

    CAGradientLayer *tint = [CAGradientLayer layer];
    tint.bounds = full; tint.position = CGPointZero;
    tint.colors = @[(__bridge id)[UIColor colorWithWhite:1 alpha:0.08].CGColor,
                    (__bridge id)[UIColor colorWithRed:0.84 green:0.93 blue:1 alpha:0.025].CGColor,
                    (__bridge id)[UIColor colorWithWhite:0 alpha:0.04].CGColor,
                    (__bridge id)[UIColor colorWithWhite:1 alpha:0.06].CGColor];
    tint.locations = @[@0,@0.28,@0.70,@1];
    tint.startPoint = CGPointMake(0,0); tint.endPoint = CGPointMake(1,1);
    [glass addSublayer:tint];
    BSKeyframes(tint,@"bounds",bounds,times,duration,kCAMediaTimingFunctionLinear);

    CAGradientLayer *rim = [CAGradientLayer layer];
    rim.name = @"BlurSleep.GlassHighlight";
    rim.bounds = full; rim.position = CGPointZero;
    rim.colors = @[(__bridge id)[UIColor colorWithWhite:1 alpha:0.90].CGColor,
                   (__bridge id)[UIColor colorWithWhite:1 alpha:0.10].CGColor,
                   (__bridge id)[UIColor colorWithWhite:1 alpha:0.02].CGColor,
                   (__bridge id)[UIColor colorWithWhite:1 alpha:0.66].CGColor];
    rim.locations = @[@0,@0.30,@0.62,@1];
    rim.startPoint = CGPointMake(0,0); rim.endPoint = CGPointMake(1,1);
    rim.mask = BSGlassMask(full,BSGlassPaths(bounds,radii,-1),times,duration);
    [glass addSublayer:rim];
    BSKeyframes(rim,@"bounds",bounds,times,duration,kCAMediaTimingFunctionLinear);
    BSKeyframes(rim,@"startPoint",@[[NSValue valueWithCGPoint:CGPointMake(0,0)],
        [NSValue valueWithCGPoint:CGPointMake(1,0)]],@[@0,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
    BSKeyframes(rim,@"endPoint",@[[NSValue valueWithCGPoint:CGPointMake(1,1)],
        [NSValue valueWithCGPoint:CGPointMake(0,1)]],@[@0,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);

    CAGradientLayer *sheen = [CAGradientLayer layer];
    sheen.name = @"BlurSleep.GlassSheen";
    sheen.bounds = full; sheen.position = CGPointZero;
    sheen.colors = @[(__bridge id)UIColor.clearColor.CGColor,
                     (__bridge id)[UIColor colorWithWhite:1 alpha:0.14].CGColor,
                     (__bridge id)[UIColor colorWithWhite:1 alpha:0.025].CGColor,
                     (__bridge id)UIColor.clearColor.CGColor];
    sheen.locations = @[@0,@0.45,@0.55,@1];
    sheen.startPoint = CGPointMake(0,0.25); sheen.endPoint = CGPointMake(1,0.75);
    [glass addSublayer:sheen];
    BSKeyframes(sheen,@"position.x",@[@(-w),@(w)],@[@0,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
    BSKeyframes(sheen,@"opacity",@[@0,@1,@0.45,@0],@[@0,@0.32,@0.70,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
    // Dim the background first, leaving a luminous glass lens above it.
    // Final model opacity is zero for both siblings: removal cannot flash.
    BSKeyframes(image.layer,@"opacity",@[@1,@0.72,@0.18,@0,@0],
        @[@0,@0.24,@0.58,@0.86,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
    BSKeyframes(glass,@"opacity",@[@0,@1,@1,@0.85,@0],
        @[@0,@0.12,@0.78,@0.92,@1],duration,kCAMediaTimingFunctionEaseInEaseOut);
}

void BSApplyAnimationStyle(UIImageView *image, UIView *container,
                           BSAnimationStyle style, double duration) {
    container.clipsToBounds = YES;
    switch (BSNormalizeStyle(style)) {
        case BSStyleCRTTelevision: BSCRT(image,container,duration); break;
        case BSStyleIrisClose: BSIris(image,duration); break;
        case BSStyleShrink: BSShrink(image,duration); break;
        case BSStyleSlideDown: BSSlide(image,container,duration); break;
        case BSStyleCardFlip: BSFlip(image,duration); break;
        case BSStyleLiquidGlass: BSLiquidGlass(image,container,duration); break;
        default: BSOriginalBlur(image.layer,duration); break;
    }
}
