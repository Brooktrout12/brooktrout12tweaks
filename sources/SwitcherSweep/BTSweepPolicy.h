#ifndef BT_SWEEP_POLICY_H
#define BT_SWEEP_POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <math.h>
#include <string.h>
#include <strings.h>

typedef struct { double x, y, width, height; } BTSweepRect;

static inline bool BTSweepCanCloseBundle(const char *bundle) {
    if (!bundle || !*bundle || strlen(bundle) > 512) return false;
    // Selection still comes only from real App Switcher display items.
    // Never target the shell or a system daemon, even if represented in a layout.
    const char *excluded[] = {"com.apple.springboard", "com.apple.backboardd",
        "com.apple.runningboardd", "com.apple.frontboard", "com.apple.WindowServer"};
    for (size_t i=0; i<sizeof(excluded)/sizeof(excluded[0]); ++i)
        if (strcasecmp(bundle, excluded[i]) == 0) return false;
    return true;
}

static inline BTSweepRect BTSweepButtonFrame(double width, double height,
                                             double left, double right, double bottom) {
    if (!isfinite(width) || !isfinite(height) || !isfinite(left) ||
        !isfinite(right) || !isfinite(bottom) || width < 80 || height < 120)
        return (BTSweepRect){0,0,0,0};
    left=fmax(left,0); right=fmax(right,0); bottom=fmax(bottom,16);
    double available=width-left-right-32;
    double w=fmin(138,available), h=46;
    double gap=height<500 ? 8 : 28;
    if (w<64 || height-bottom-gap<h) return (BTSweepRect){0,0,0,0};
    return (BTSweepRect){left+(width-left-right-w)/2, height-bottom-gap-h, w, h};
}

static inline double BTSweepCardDelay(size_t index) {
    return fmin((double)index*0.028,0.112);
}
#endif
