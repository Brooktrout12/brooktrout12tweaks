#include "../BSAnimationState.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    // Regression: the actual 18.6 report has no legacy fade methods. That
    // must not disable the supported state setter/factor lookup path.
    assert(BSChooseHookMode(false,true,true,true,true,true) == BSHookBacklightState);
    assert(BSChooseHookMode(true,true,true,true,true,true) == BSHookBacklightState);
    assert(BSChooseHookMode(true,false,false,true,true,true) == BSHookLegacyDuration);
    assert(BSChooseHookMode(false,true,false,true,true,true) == BSHookNone);
    assert(BSChooseHookMode(false,false,true,true,true,true) == BSHookNone);
    assert(BSChooseHookMode(false,true,true,false,true,true) == BSHookNone);
    assert(BSChooseHookMode(false,true,true,true,false,true) == BSHookNone);
    assert(BSChooseHookMode(false,true,true,true,true,false) == BSHookNone);
    BSAnimationState state = {0};
    assert(BSClampDuration(NAN) == BS_DEFAULT_DURATION);
    assert(BSClampDuration(INFINITY) == BS_DEFAULT_DURATION);
    assert(BSClampDuration(-20) == BS_MIN_DURATION);
    assert(BSClampDuration(90) == BS_MAX_DURATION);
    assert(fabs(BSClampDuration(0.568) - 0.55) < 1e-9);
    assert(BSCanStart(true,true,true,false,0,3,false));
    assert(BSCanStart(true,true,true,false,0,99,true));
    assert(!BSCanStart(true,true,true,false,0,8,false)); // auto-lock
    assert(!BSCanStart(true,true,false,false,0,3,false)); // already off
    assert(!BSCanStart(false,true,true,false,0,3,false));
    assert(!BSCanStart(true,false,true,false,0,3,false));
    assert(!BSCanStart(true,true,true,false,0.5,3,false)); // brightness change
    assert(!BSCanStart(true,true,true,false,NAN,3,false));
    assert(!BSCanStart(true,true,true,false,-1,3,false));
    uint64_t first = BSBegin(&state,10,0.55);
    assert(!BSCanStart(true,true,true,state.active,0,3,false));
    assert(fabs(BSRemaining(&state,10.2) - 0.35) < 1e-9);
    assert(BSRemaining(&state,11) == 0);
    BSCancel(&state); // wake before completion
    assert(!state.active && BSRemaining(&state,10.3) == 0);
    uint64_t second = BSBegin(&state,10.4,2);
    assert(second != first);
    assert(!BSExpire(&state,first)); // old timer cannot kill a new lock
    assert(state.active);
    assert(fabs(BSRemaining(&state,10.9) - 1.5) < 1e-9);
    assert(BSExpire(&state,second));
    assert(!state.active && !BSExpire(&state,second));
    puts("PASS: iOS 18.6 hook-selection regression, input bounds, manual-lock eligibility, shared deadline, wake cancellation, stale timer isolation.");
    return 0;
}
