#pragma once
#include <stdbool.h>

typedef struct { bool managed; bool nativeHidden; } CQAVisibilityState;

bool CQAIsSpringBoardPath(const char *path);
bool CQAVisibilityTransition(CQAVisibilityState *state, bool currentHidden, bool active);
bool CQAInterceptNativeHidden(CQAVisibilityState *state, bool requestedHidden, bool active);
