#pragma once
#include <stdbool.h>
#include <stdint.h>

#define BS_DEFAULT_DURATION 0.55
#define BS_MIN_DURATION 0.15
#define BS_MAX_DURATION 2.0
#define BS_CLEANUP_MARGIN 0.20

typedef struct {
    bool active;
    uint64_t generation;
    double start;
    double duration;
} BSAnimationState;

typedef enum { BSHookNone, BSHookLegacyDuration, BSHookBacklightState } BSHookMode;
BSHookMode BSChooseHookMode(bool legacyFade, bool stateSetter, bool factorLookup,
                           bool screenState, bool wake, bool renderer);

double BSClampDuration(double value);
bool BSCanStart(bool enabled, bool onMainThread, bool screenOn, bool active,
                double target, int64_t source, bool insideManualSleep);
uint64_t BSBegin(BSAnimationState *state, double now, double duration);
double BSRemaining(const BSAnimationState *state, double now);
void BSCancel(BSAnimationState *state);
bool BSExpire(BSAnimationState *state, uint64_t generation);
