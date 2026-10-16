#include "../PressPolicy.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    SPPressPolicy p = {0};
    assert(!SPDeferSleep(&p)); // Disabled/native path.
    SPBegin(&p);
    assert(SPDeferSleep(&p)); assert(SPDeferSound(&p));
    SPResolveDouble(&p);
    assert(SPDeferSleep(&p)); // Late native final-up must not put it to sleep.
    assert(!SPReplaySleep(&p)); assert(!SPReplaySound(&p));
    SPReset(&p);
    assert(!SPDeferSleep(&p)); // Next ordinary sequence is not swallowed.

    SPBegin(&p); SPDeferSleep(&p); SPDeferSound(&p); SPResolveSingle(&p);
    assert(SPReplaySleep(&p)); assert(SPReplaySound(&p));
    assert(!SPDeferSleep(&p)); assert(!SPDeferSound(&p));
    assert(!SPReplaySleep(&p)); assert(!SPReplaySound(&p)); // At most once.

    SPBegin(&p); SPResolveSingle(&p);
    assert(!SPReplaySleep(&p)); // Wake-only first press must not replay a sleep.
    SPBegin(&p); SPDeferSleep(&p); SPReset(&p);
    assert(!SPReplaySleep(&p)); // Screenshot/long/SOS cancellation discards it.
    assert(!SPDeferSleep(&p));
    SPBegin(&p); SPDeferSleep(&p); SPBegin(&p); SPResolveSingle(&p);
    assert(!SPReplaySleep(&p)); // Stale deferred work cannot leak to another press.
    puts("PASS: double, single, native, wake-only, cancel, and stale-sequence policy");
}
