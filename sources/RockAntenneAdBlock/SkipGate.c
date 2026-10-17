#include "SkipGate.h"

RABSkipDecision RABSkipRequest(RABSkipGate *gate, uint64_t *ticket) {
    if (gate->closed || gate->attempts >= 12) return RABSkipRejected;
    if (gate->pending) return RABSkipAlreadyPending;
    gate->pending = true;
    *ticket = ++gate->generation;
    return RABSkipQueued;
}
bool RABSkipTake(RABSkipGate *gate, uint64_t ticket) {
    if (gate->closed || !gate->pending || gate->generation != ticket) return false;
    gate->pending = false;
    ++gate->attempts;
    return true;
}
void RABSkipClose(RABSkipGate *gate) {
    ++gate->generation;
    gate->pending = false;
    gate->closed = true;
}
void RABSkipReopen(RABSkipGate *gate) {
    if (!gate->closed) return;
    ++gate->generation;
    gate->attempts = 0;
    gate->pending = false;
    gate->closed = false;
}
