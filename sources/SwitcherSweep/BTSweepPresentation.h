#ifndef BT_SWEEP_PRESENTATION_H
#define BT_SWEEP_PRESENTATION_H
#include <stdbool.h>

// During a transition, its destination is authoritative: the old visibility
// flag can still describe Home/an app, or a switcher that is already leaving.
static inline bool BTSweepButtonCanAppear(bool inWindow, bool switcherVisible,
                                          bool transitioning, bool targetsSwitcher,
                                          bool disappearing) {
    if (!inWindow || disappearing) return false;
    return transitioning ? targetsSwitcher : switcherVisible;
}

typedef enum { BTSweepTapIgnore, BTSweepTapQueue, BTSweepTapRun } BTSweepTapAction;

static inline BTSweepTapAction BTSweepClassifyTap(bool inWindow, bool visible,
    bool transitioning, bool targetsSwitcher, bool disappearing,
    bool busy, bool pending) {
    if (busy || pending || !BTSweepButtonCanAppear(inWindow,visible,
        transitioning,targetsSwitcher,disappearing)) return BTSweepTapIgnore;
    return transitioning ? BTSweepTapQueue : BTSweepTapRun;
}

#endif
