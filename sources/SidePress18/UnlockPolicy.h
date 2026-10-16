#ifndef SP_UNLOCK_POLICY_H
#define SP_UNLOCK_POLICY_H
#include <stdbool.h>

typedef enum {
    SPUnlockDiscard,
    SPUnlockWait,
    SPUnlockCancelForScreenOff,
    SPUnlockPerform
} SPUnlockDecision;

// Authentication and UI dismissal are independent. A canceled generation must
// never become ready after a later authentication, and screen-off wins over a
// transient combination of otherwise-unlocked state flags.
static inline SPUnlockDecision SPDecideUnlock(bool current, bool pending,
        bool authenticated, bool uiLocked, bool coverVisible,
        bool screenOff, bool sawScreenAwake) {
    if (!current || !pending) return SPUnlockDiscard;
    if (screenOff && sawScreenAwake) return SPUnlockCancelForScreenOff;
    if (authenticated && !uiLocked && !coverVisible && !screenOff) return SPUnlockPerform;
    return SPUnlockWait;
}
#endif
