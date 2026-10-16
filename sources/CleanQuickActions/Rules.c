#include "Rules.h"
#include <string.h>

bool CQAIsSpringBoardPath(const char *path) {
    return path && (!strcmp(path, "/System/Library/CoreServices/SpringBoard.app/SpringBoard") ||
                    !strcmp(path, "/Applications/SpringBoard.app/SpringBoard"));
}

bool CQAVisibilityTransition(CQAVisibilityState *state, bool currentHidden, bool active) {
    if (active) {
        if (!state->managed) state->nativeHidden = currentHidden;
        state->managed = true;
        return true;
    }
    if (!state->managed) return currentHidden;
    state->managed = false;
    return state->nativeHidden;
}

bool CQAInterceptNativeHidden(CQAVisibilityState *state, bool requestedHidden, bool active) {
    state->nativeHidden = requestedHidden;
    state->managed = active;
    return active || requestedHidden;
}
