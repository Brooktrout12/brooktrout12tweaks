#ifndef BT_SWEEP_PENDING_H
#define BT_SWEEP_PENDING_H
#include <stdbool.h>
#include <math.h>

typedef enum {
    BTSweepPendingWait, BTSweepPendingStart, BTSweepPendingPause,
    BTSweepPendingCancel, BTSweepPendingFail
} BTSweepPendingAction;

// Called with live coordinator state, not an inferred transition-end pointer.
// Missing windows / non-switcher layouts must persist before proving departure.
// A phase-1 interruption rolls back visuals while preserving the accepted tap.
static inline BTSweepPendingAction BTSweepEvaluatePending(bool inWindow,
    bool visible, bool transitioning, bool ready, unsigned phase,
    double elapsed, double outsideFor) {
    if (!isfinite(elapsed) || !isfinite(outsideFor) || elapsed<0 || outsideFor<0)
        return BTSweepPendingFail;
    if (outsideFor>=0.20) return BTSweepPendingCancel;
    if (phase>=2) return BTSweepPendingWait; // Close commands already own the action.
    if (phase==1) return (!inWindow || !visible || transitioning) ?
        BTSweepPendingPause : BTSweepPendingWait;
    if (elapsed>=5.0) return BTSweepPendingFail; // Bound unresolved waiting; no indefinite polling.
    if (!inWindow || !visible || transitioning || !ready) return BTSweepPendingWait;
    return BTSweepPendingStart;
}

#endif
