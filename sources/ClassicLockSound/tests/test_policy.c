#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include "../BTLockSoundPolicy.h"

int main(void) {
    // Regression fixture distilled from the phone report: all six native lock
    // attempts had soundType=5, eventType=1002 and systemSoundID=0. The previous
    // ID-1100 selection missed every one of them.
    static const struct { int64_t type, event; unsigned int systemID; } observed[] = {
        {5, 1002, 0}, {5, 1002, 0}, {5, 1002, 0},
        {5, 1002, 0}, {5, 1002, 0}, {5, 1002, 0}
    };
    for (unsigned i = 0; i < sizeof(observed)/sizeof(observed[0]); ++i) {
        assert(observed[i].systemID != 1100);
        assert(BTIsLockFeedback(observed[i].type, observed[i].event));
    }
    // Keep system-sound IDs, unrelated feedback and resolved/reused custom
    // sound objects out of the feedback redirect. In particular, the screenshot
    // sound ID 1108 is never interpreted as either an object or a lock event.
    assert(!BTIsLockFeedback(0, 1002));
    assert(!BTIsLockFeedback(0, 1108));
    assert(!BTIsLockFeedback(5, 1108));
    assert(!BTIsLockFeedback(5, 1100));
    assert(!BTIsLockFeedback(3, 1002));
    assert(!BTIsLockFeedback(5, 1002 + (INT64_C(1) << 32)));
    assert(!BTIsLockFeedback(5 + (INT64_C(1) << 32), 1002));
    assert(!BTIsLockFeedback(INT64_MIN, 1002));
    assert(!BTIsLockFeedback(5, INT64_MAX));
    unsigned matches = 0;
    for (int64_t type = -1; type <= 6; ++type)
        for (int64_t event = -1; event < 65536; ++event)
            if (BTIsLockFeedback(type, event)) ++matches;
    assert(matches == 1);
    puts("{\"result\":\"PASS\",\"observed_lock_events_selected\":6,\"selection_grid_cases\":524296,\"unrelated_sounds_excluded\":true,\"full_width_event_types\":true,\"device_playback_tested\":false}");
    return 0;
}
