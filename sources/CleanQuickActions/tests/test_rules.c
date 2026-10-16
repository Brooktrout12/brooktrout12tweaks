#include "../Rules.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    assert(CQAIsSpringBoardPath("/System/Library/CoreServices/SpringBoard.app/SpringBoard"));
    assert(CQAIsSpringBoardPath("/Applications/SpringBoard.app/SpringBoard"));
    assert(!CQAIsSpringBoardPath(NULL));
    assert(!CQAIsSpringBoardPath(""));
    assert(!CQAIsSpringBoardPath("/usr/libexec/fileproviderd"));
    assert(!CQAIsSpringBoardPath("/Applications/Preferences.app/Preferences"));
    assert(!CQAIsSpringBoardPath("/Applications/Fake.app/SpringBoard"));
    assert(!CQAIsSpringBoardPath("/Applications/SpringBoard.app/SpringBoard/child"));

    // Repeated application must not replace the native visibility with our
    // forced value. OFF must not expose separators UIKit originally hid.
    for (int initiallyHidden = 0; initiallyHidden <= 1; initiallyHidden++) {
        CQAVisibilityState state = {0};
        bool shown = initiallyHidden;
        for (int round = 0; round < 100; round++) {
            shown = CQAVisibilityTransition(&state, shown, true);
            assert(shown && state.managed);
            for (int layout = 0; layout < 10; layout++)
                assert(CQAVisibilityTransition(&state, shown, true));
            shown = CQAVisibilityTransition(&state, shown, false);
            assert(shown == (bool)initiallyHidden && !state.managed);
        }
    }
    for (int requested = 0; requested <= 1; requested++) {
        CQAVisibilityState state = {0};
        bool hidden = CQAVisibilityTransition(&state, false, true);
        hidden = CQAInterceptNativeHidden(&state, requested, true);
        assert(hidden);
        // Same transition restores on OFF or on moving to a non-icon menu.
        hidden = CQAVisibilityTransition(&state, hidden, false);
        assert(hidden == (bool)requested && !state.managed);
        assert(CQAVisibilityTransition(&state, hidden, false) == hidden);
    }
    CQAVisibilityState state = {0};
    assert(!CQAVisibilityTransition(&state, false, false));
    assert(CQAVisibilityTransition(&state, true, false));
    assert(!state.managed);
    assert(!CQAInterceptNativeHidden(&state, false, false));
    assert(CQAInterceptNativeHidden(&state, true, false));
    assert(!state.managed);
    // Native changes while disabled become the next restoration baseline.
    assert(CQAVisibilityTransition(&state, true, true));
    assert(CQAVisibilityTransition(&state, true, false));
    puts("PASS: process scope, repeat toggles, native updates and restoration");
    return 0;
}
