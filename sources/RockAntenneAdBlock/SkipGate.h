#pragma once
#include <stdbool.h>
#include <stdint.h>

// Bounded, cancellable requests. The caller serializes access to each gate.
typedef struct {
    uint64_t generation;
    unsigned attempts;
    bool pending;
    bool closed;
} RABSkipGate;
typedef enum { RABSkipRejected, RABSkipAlreadyPending, RABSkipQueued } RABSkipDecision;
RABSkipDecision RABSkipRequest(RABSkipGate *gate, uint64_t *ticket);
bool RABSkipTake(RABSkipGate *gate, uint64_t ticket);
void RABSkipClose(RABSkipGate *gate);
void RABSkipReopen(RABSkipGate *gate);
