#include "../SkipGate.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    RABSkipGate gate = {0};
    uint64_t first = 0, duplicate = 123, second = 0;
    assert(RABSkipRequest(&gate, &first) == RABSkipQueued);
    assert(RABSkipRequest(&gate, &duplicate) == RABSkipAlreadyPending);
    assert(duplicate == 123); // The duplicate does not acquire a runnable ticket.
    assert(!RABSkipTake(&gate, first + 1));
    assert(RABSkipTake(&gate, first));
    assert(!RABSkipTake(&gate, first));
    assert(gate.attempts == 1);
    assert(RABSkipRequest(&gate, &second) == RABSkipQueued);
    RABSkipClose(&gate); // Ad ends before the queued main-thread action runs.
    assert(!RABSkipTake(&gate, second));
    assert(RABSkipRequest(&gate, &duplicate) == RABSkipRejected);
    RABSkipReopen(&gate); // A genuinely new prepare/break can use this manager.
    assert(RABSkipRequest(&gate, &first) == RABSkipQueued);
    assert(!RABSkipTake(&gate, second)); // Old work cannot skip the new ad.
    assert(RABSkipTake(&gate, first));
    for (unsigned i = 1; i < 12; ++i) {
        assert(RABSkipRequest(&gate, &first) == RABSkipQueued);
        assert(RABSkipTake(&gate, first));
    }
    assert(RABSkipRequest(&gate, &first) == RABSkipRejected);
    RABSkipReopen(&gate); // Reopen while active must not reset the limit.
    assert(gate.attempts == 12);
    puts("skip gate: deduplication, stale callbacks, cancellation, reopen and attempt limit passed");
    return 0;
}
