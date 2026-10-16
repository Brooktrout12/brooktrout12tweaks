#pragma once
#include <stdbool.h>
#include <stdint.h>

// Main-thread state. The epoch prevents delayed pauses from affecting a later
// foreground session, including a fast leave -> return -> leave sequence.
typedef struct {
    uint64_t epoch;
    bool inactive;
} YSForegroundState;

// An owner found during Shorts playback stays eligible while its window is
// being hidden by the system. Navigating away inside YouTube retires it.
typedef struct { bool active; } YSShortsOwnerState;
static inline void YSShortsOwnerAppearedOrPlayed(YSShortsOwnerState *owner) {
    owner->active = true;
}
static inline void YSShortsOwnerDisappeared(YSShortsOwnerState *owner, bool systemTransition) {
    if (!systemTransition) owner->active = false;
}
static inline bool YSShouldCaptureOwner(const YSShortsOwnerState *owner) {
    return owner->active;
}

static inline uint64_t YSLeaveForeground(YSForegroundState *state) {
    state->inactive = true;
    return ++state->epoch;
}

static inline void YSEnterForeground(YSForegroundState *state) {
    state->inactive = false;
    ++state->epoch;
}

static inline bool YSShouldPause(const YSForegroundState *state, uint64_t epoch,
                                 bool hasShortsTarget) {
    return hasShortsTarget && state->inactive && state->epoch == epoch;
}
