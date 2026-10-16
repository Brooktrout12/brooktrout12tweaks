#ifndef BT_LOCK_SOUND_POLICY_H
#define BT_LOCK_SOUND_POLICY_H

#include <stdbool.h>
#include <stdint.h>

// iOS 18.6 device report: all six lock requests were feedback type 5,
// event 1002, with both system-sound IDs zero. These are different namespaces;
// testing systemSoundID==1100 therefore never selected those requests.
enum {
    BTSystemSoundType = 0,
    BTFeedbackSoundType = 5,
    BTLockFeedbackEvent = 1002
};

static inline bool BTIsLockFeedback(int64_t soundType, int64_t eventType) {
    return soundType == BTFeedbackSoundType && eventType == BTLockFeedbackEvent;
}

#endif
