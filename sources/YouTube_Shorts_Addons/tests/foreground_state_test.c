#include <assert.h>
#include <stdio.h>
#include "../Shared/ForegroundState.h"

int main(void) {
    YSShortsOwnerState owner = {0};
    assert(!YSShouldCaptureOwner(&owner));
    YSShortsOwnerAppearedOrPlayed(&owner);
    assert(YSShouldCaptureOwner(&owner));
    // Regression: UIKit detached the Shorts view before the exit notification.
    YSShortsOwnerDisappeared(&owner, true);
    assert(YSShouldCaptureOwner(&owner));
    // Normal navigation to a long video must retire the Shorts owner.
    YSShortsOwnerDisappeared(&owner, false);
    assert(!YSShouldCaptureOwner(&owner));
    // Inactive/preloaded owners do not become active from disappearance alone.
    YSShortsOwnerDisappeared(&owner, true);
    assert(!YSShouldCaptureOwner(&owner));
    YSShortsOwnerAppearedOrPlayed(&owner);
    assert(YSShouldCaptureOwner(&owner));
    YSForegroundState s = {0};
    assert(!YSShouldPause(&s, 0, true));
    uint64_t first = YSLeaveForeground(&s);
    assert(YSShouldPause(&s, first, true));
    assert(!YSShouldPause(&s, first, false)); // Ordinary video, no Shorts target.
    YSEnterForeground(&s);
    assert(!YSShouldPause(&s, first, true)); // Quick return cancels pending pauses.
    uint64_t second = YSLeaveForeground(&s);
    assert(!YSShouldPause(&s, first, true)); // Old session cannot pause new session.
    assert(YSShouldPause(&s, second, true));
    uint64_t background = YSLeaveForeground(&s);
    assert(!YSShouldPause(&s, second, true)); // didEnterBackground supersedes resign.
    assert(YSShouldPause(&s, background, true));
    YSEnterForeground(&s);
    assert(!YSShouldPause(&s, background, true));
    for (unsigned i = 0; i < 10000; ++i) {
        uint64_t epoch = YSLeaveForeground(&s);
        assert(YSShouldPause(&s, epoch, true));
        YSEnterForeground(&s);
        assert(!YSShouldPause(&s, epoch, true));
    }
    puts("PASS: cached Shorts survive system detachment; in-app navigation retires them; background transitions, stale retries, 10000 rapid cycles");
}
