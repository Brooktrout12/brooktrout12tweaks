// Regression coverage for consistent corners across module sizes.
#include <assert.h>
#include <stdio.h>
#include "../BTShapeGeometry.h"

int main(void) {
    struct { double width, height, nativeRadius; } tiles[] = {
        {68, 68, 34},       // 1x1 toggle.
        {150, 68, 34},      // Focus / wide tile.
        {68, 150, 34},      // Vertical brightness / volume slider.
        {150, 150, 32},     // Connectivity / media platter.
        {232, 150, 40},     // Resized rectangular module.
        {314, 314, 48},     // Large module.
    };
    for (unsigned i = 0; i < sizeof(tiles)/sizeof(tiles[0]); ++i) {
        double radius = BTShapeRadius(tiles[i].width, tiles[i].height, tiles[i].nativeRadius, 68);
        assert(radius == 17);
        assert(BTShapeRadius(tiles[i].width, tiles[i].height, radius, 68) == radius);
        // A zero-radius surface can be an intentional straight fill boundary.
        assert(BTShapeRadius(tiles[i].width, tiles[i].height, 0, 68) == 0);
    }
    // The gallery uses its own base cell, even for larger previews.
    assert(BTShapeRadius(56, 56, 28, 56) == 14);
    assert(BTShapeRadius(126, 126, 30, 56) == 14);
    assert(BTShapeRadius(56, 126, 28, 56) == 14);
    // Smaller submenu controls still fit their radius within their own size.
    assert(BTShapeRadius(24, 24, 12, 68) == 6);
    assert(BTShapeRadius(68, 70, 34, 68) == 17);
    // Layout resize and repeated native setter calls must not compound changes.
    for (unsigned unit = 32; unit <= 100; ++unit) {
        double base = BTShapeRadius(unit, unit, unit * 0.5, unit);
        double large = BTShapeRadius(unit * 2 + 14, unit * 2 + 14, 40, unit);
        assert(base == large);
        for (unsigned repeat = 0; repeat < 8; ++repeat)
            large = BTShapeRadius(unit * 2 + 14, unit * 2 + 14, large, unit);
        assert(base == large);
    }
    // Invalid metrics preserve the native value during initialization/teardown.
    assert(BTShapeRadius(0, 68, 34, 68) == 34);
    assert(BTShapeRadius(-68, 68, 34, 68) == 34);
    assert(BTShapeRadius(8, 8, 4, 68) == 4);
    assert(BTShapeRadius(NAN, 68, 34, 68) == 34);
    assert(BTShapeRadius(INFINITY, 68, 34, 68) == 34);
    assert(BTShapeRadius(68, 68, -1, 68) == -1);
    assert(BTShapeRadius(68, 68, 34, 0) == 34);
    assert(BTShapeRadius(68, 68, 34, NAN) == 34);
    assert(BTShapeRadius(68, 68, 34, 300) == 34);
    assert(BTShapeRadius(4096, 4096, 128, 68) == 128);
    assert(isnan(BTShapeRadius(68, 68, NAN, 68)));
    assert(isinf(BTShapeRadius(68, 68, INFINITY, 68)));
    // Radius coverage must not broaden the separate circle-path recognizer.
    assert(BTIsSquareControl(68, 68));
    assert(!BTIsSquareControl(68, 150));
    puts("{\"result\":\"PASS\",\"consistent_module_corners\":true,\"gallery_scale_separate\":true,\"straight_fills_preserved\":true,\"resize_and_nested_setters\":true,\"invalid_metrics_passthrough\":true,\"circle_recognition_preserved\":true,\"device_runtime_tested\":false}");
    return 0;
}
