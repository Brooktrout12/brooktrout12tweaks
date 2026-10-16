#include "BSAnimationState.h"
#include <math.h>

BSHookMode BSChooseHookMode(bool legacyFade, bool stateSetter, bool factorLookup,
                           bool screenState, bool wake, bool renderer) {
    if (!screenState || !wake || !renderer) return BSHookNone;
    if (stateSetter && factorLookup) return BSHookBacklightState;
    return legacyFade ? BSHookLegacyDuration : BSHookNone;
}

double BSClampDuration(double value) {
    if (!isfinite(value)) return BS_DEFAULT_DURATION;
    if (value < BS_MIN_DURATION) return BS_MIN_DURATION;
    if (value > BS_MAX_DURATION) return BS_MAX_DURATION;
    return round(value * 20.0) / 20.0;
}

bool BSCanStart(bool enabled, bool onMainThread, bool screenOn, bool active,
                double target, int64_t source, bool insideManualSleep) {
    return enabled && onMainThread && screenOn && !active && isfinite(target)
        && target >= 0.0 && target <= 0.0001 && (source == 3 || insideManualSleep);
}

uint64_t BSBegin(BSAnimationState *state, double now, double duration) {
    state->active = true;
    state->start = now;
    state->duration = BSClampDuration(duration);
    return ++state->generation;
}

double BSRemaining(const BSAnimationState *state, double now) {
    if (!state->active || !isfinite(now)) return 0;
    return fmax(0, state->start + state->duration - now);
}

void BSCancel(BSAnimationState *state) {
    state->active = false;
    ++state->generation;
}

bool BSExpire(BSAnimationState *state, uint64_t generation) {
    if (!state->active || generation != state->generation) return false;
    BSCancel(state);
    return true;
}
