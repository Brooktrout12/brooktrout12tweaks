#pragma once
#include <stdint.h>

// Stable preference IDs: upgrades preserve the user's existing selection.
typedef enum {
    BSStyleGaussianBlur = 0,
    BSStyleCRTTelevision,
    BSStyleIrisClose,
    BSStyleShrink,
    BSStyleSlideDown,
    BSStyleCardFlip,
    BSStyleLiquidGlass,
    BSStyleCount
} BSAnimationStyle;

static inline BSAnimationStyle BSNormalizeStyle(int64_t value) {
    return value >= 0 && value < BSStyleCount ? (BSAnimationStyle)value : BSStyleGaussianBlur;
}
