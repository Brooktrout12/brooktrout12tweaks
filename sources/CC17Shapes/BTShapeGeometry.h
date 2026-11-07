// Copyright (c) 2026 brooktrout12. MIT license.
#ifndef BT_SHAPE_GEOMETRY_H
#define BT_SHAPE_GEOMETRY_H

#include <math.h>
#include <stdbool.h>

// Keep circle recognition separate from the module-radius policy: rectangular
// modules are now eligible, but rings, tiny indicators and invalid frames aren't.
static inline bool BTIsSquareControl(double width, double height) {
    if (!isfinite(width) || !isfinite(height)) return false;
    double side = fmin(width, height);
    return side >= 12.0 && side <= 256.0 &&
           fabs(width - height) <= fmax(1.0, side * 0.035);
}

static inline bool BTIsControlSurface(double width, double height) {
    return isfinite(width) && isfinite(height) &&
           fmin(width, height) >= 12.0 && fmax(width, height) <= 2048.0;
}

static inline double BTShapeRadius(double width, double height, double nativeRadius,
                                   double unitSide) {
    if (!BTIsControlSurface(width, height) || !isfinite(nativeRadius) ||
        nativeRadius <= 0 || !isfinite(unitSide) || unitSide < 12 || unitSide > 256)
        return nativeRadius;
    double side = fmin(width, height);
    // All tiles in one grid use the single-cell radius. A 2x2 platter must not
    // acquire twice the corner radius of a 1x1 control. Small submenu buttons
    // can use smaller corners; zero-radius fills keep their straight edges.
    return fmin(side, unitSide) * 0.25;
}

#endif
