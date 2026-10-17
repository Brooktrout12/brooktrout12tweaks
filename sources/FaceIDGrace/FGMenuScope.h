#pragma once
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>

static pthread_key_t FGMenuDepthKey;

static inline bool FGMenuActive(void) {
    return (uintptr_t)pthread_getspecific(FGMenuDepthKey) != 0;
}

static inline bool FGEnterMenu(uintptr_t *previous) {
    *previous = (uintptr_t)pthread_getspecific(FGMenuDepthKey);
    if (*previous == UINTPTR_MAX) return false;
    return pthread_setspecific(FGMenuDepthKey, (void *)(*previous + 1)) == 0;
}

static inline void FGLeaveMenu(uintptr_t previous) {
    pthread_setspecific(FGMenuDepthKey, (void *)previous);
}
