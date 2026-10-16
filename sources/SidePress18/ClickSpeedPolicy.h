#pragma once
#include <math.h>

// Native recognizers may split the multi-click window into smaller waits.
// Scale those waits relative to the native window instead of leaving a
// 150 ms component unchanged merely because it is already below 160 ms.
static inline double SPScaledClickWait(double wait, double nativeWindow, double requestedWindow) {
    if (!isfinite(wait) || wait <= 0 || !isfinite(requestedWindow) || requestedWindow <= 0) return wait;
    if (!isfinite(nativeWindow) || nativeWindow <= 0) return fmin(wait, requestedWindow);
    return wait * fmin(1.0, requestedWindow / nativeWindow);
}
