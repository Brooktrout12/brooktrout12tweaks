#include <assert.h>
#include <stdio.h>
#include "../BTSweepPending.h"

int main(void) {
    // A real entry may transiently disappear or retarget before it settles.
    assert(BTSweepEvaluatePending(true,false,true,false,0,0.00,0)==BTSweepPendingWait);
    assert(BTSweepEvaluatePending(false,false,true,false,0,0.08,0.02)==BTSweepPendingWait);
    assert(BTSweepEvaluatePending(true,false,true,false,0,0.12,0)==BTSweepPendingWait);
    assert(BTSweepEvaluatePending(true,false,false,false,0,0.40,0.01)==BTSweepPendingWait);
    assert(BTSweepEvaluatePending(true,true,false,false,0,0.42,0)==BTSweepPendingWait);
    assert(BTSweepEvaluatePending(true,true,false,true,0,0.44,0)==BTSweepPendingStart);
    // Starting the visual sweep does not consume the request. A retarget after
    // start pauses it, then the same request can start again without a new tap.
    assert(BTSweepEvaluatePending(true,true,false,false,1,0.45,0)==BTSweepPendingWait);
    assert(BTSweepEvaluatePending(true,true,true,false,1,0.47,0)==BTSweepPendingPause);
    assert(BTSweepEvaluatePending(true,true,true,true,0,0.48,0)==BTSweepPendingWait);
    assert(BTSweepEvaluatePending(true,true,false,true,0,0.60,0)==BTSweepPendingStart);
    assert(BTSweepEvaluatePending(true,true,false,false,1,0.80,0)==BTSweepPendingWait);
    assert(BTSweepEvaluatePending(true,true,false,true,2,0.98,0)==BTSweepPendingWait);
    // Steady taps have no imposed opening delay; transient absence isn't exit.
    assert(BTSweepEvaluatePending(true,true,false,true,0,0.00,0)==BTSweepPendingStart);
    assert(BTSweepEvaluatePending(false,false,false,false,0,0.10,0.10)==BTSweepPendingWait);
    assert(BTSweepEvaluatePending(false,false,false,false,0,0.22,0.20)==BTSweepPendingCancel);
    // A stuck native gate ends the wait instead of polling indefinitely.
    assert(BTSweepEvaluatePending(true,true,true,false,0,4.99,0)==BTSweepPendingWait);
    assert(BTSweepEvaluatePending(true,true,true,false,0,5.00,0)==BTSweepPendingFail);
    // Finishing an already-started sweep isn't cut off by a waiting deadline.
    assert(BTSweepEvaluatePending(true,true,false,false,1,5.01,0)==BTSweepPendingWait);
    assert(BTSweepEvaluatePending(true,true,false,true,0,NAN,0)==BTSweepPendingFail);
    puts("{\"result\":\"PASS\",\"pending_delivery_scenarios\":19,\"device_runtime_tested\":false}");
}
