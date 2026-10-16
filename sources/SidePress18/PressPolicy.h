#pragma once
#include <stdbool.h>

// Only resolves native events; no second recognizer and no extra click timer.
typedef enum { SPIdle, SPWaiting, SPResolvingSingle, SPConsumedDouble } SPPhase;
typedef struct {
    SPPhase phase;
    bool deferredSleep, deferredSound, performedSleep, performedSound;
} SPPressPolicy;

static inline void SPReset(SPPressPolicy *p) { *p = (SPPressPolicy){0}; }
static inline void SPBegin(SPPressPolicy *p) { SPReset(p); p->phase = SPWaiting; }
static inline bool SPDeferSleep(SPPressPolicy *p) {
    if (p->phase == SPWaiting || p->phase == SPConsumedDouble) {
        p->deferredSleep = true; return true;
    }
    if (p->phase == SPResolvingSingle) p->performedSleep = true;
    return false;
}
static inline bool SPDeferSound(SPPressPolicy *p) {
    if (p->phase == SPWaiting || p->phase == SPConsumedDouble) {
        p->deferredSound = true; return true;
    }
    if (p->phase == SPResolvingSingle) p->performedSound = true;
    return false;
}
static inline void SPResolveSingle(SPPressPolicy *p) { p->phase = SPResolvingSingle; }
static inline bool SPReplaySleep(SPPressPolicy *p) {
    return p->phase == SPResolvingSingle && p->deferredSleep && !p->performedSleep;
}
static inline bool SPReplaySound(SPPressPolicy *p) {
    return p->phase == SPResolvingSingle && p->deferredSound && !p->performedSound;
}
static inline void SPResolveDouble(SPPressPolicy *p) {
    SPReset(p); p->phase = SPConsumedDouble;
}
