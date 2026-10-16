#include "../UnlockPolicy.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    // A Face ID match alone cannot launch through the lock screen or through
    // its outgoing animation. Both independent UI states must have cleared.
    assert(SPDecideUnlock(true, true, true, true, true, false, true) == SPUnlockWait);
    assert(SPDecideUnlock(true, true, true, false, true, false, true) == SPUnlockWait);
    assert(SPDecideUnlock(true, true, true, true, false, false, true) == SPUnlockWait);
    assert(SPDecideUnlock(true, true, false, false, false, false, true) == SPUnlockWait);
    assert(SPDecideUnlock(true, true, true, false, false, false, true) == SPUnlockPerform);

    // Canceling invalidates the generation and clears the pending action. An
    // unrelated successful unlock, even immediately afterwards, stays inert.
    assert(SPDecideUnlock(false, true, true, false, false, false, true) == SPUnlockDiscard);
    assert(SPDecideUnlock(true, false, true, false, false, false, true) == SPUnlockDiscard);
    assert(SPDecideUnlock(false, false, true, false, false, false, true) == SPUnlockDiscard);

    // Relocking/screen-off must win when authentication or UI flags lag by a
    // run-loop turn; waking from a dark screen is allowed to remain pending.
    assert(SPDecideUnlock(true, true, true, false, false, true, true) == SPUnlockCancelForScreenOff);
    assert(SPDecideUnlock(true, true, false, true, true, true, false) == SPUnlockWait);

    // There is no elapsed-time gate on active passcode entry. Many observations
    // leave an unauthenticated attempt waiting until actual authentication.
    for (int tick = 0; tick < 1500; ++tick)
        assert(SPDecideUnlock(true, true, false, true, true, false, true) == SPUnlockWait);
    puts("unlock policy: passed");
    return 0;
}
