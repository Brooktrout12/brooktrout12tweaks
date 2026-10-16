#pragma once
#include <math.h>

// UIKit-independent geometry, also exercised by the host-side tests.
typedef struct { double x, y, width, height; } PICropRect;

static inline double PIClamp(double value, double minimum, double maximum) {
    return fmin(fmax(value, minimum), maximum);
}

static inline double PIFillScale(double width, double height, double side) {
    if (width <= 0 || height <= 0 || side <= 0) return 1;
    return fmax(side / width, side / height);
}

static inline PICropRect PICropForViewport(double width, double height,
                                           double side, double scale,
                                           double offsetX, double offsetY) {
    double edge = fmin(side / fmax(scale, 0.000001), fmin(width, height));
    return (PICropRect){PIClamp(offsetX / scale, 0, width - edge),
                        PIClamp(offsetY / scale, 0, height - edge), edge, edge};
}
