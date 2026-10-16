#include <assert.h>
#include <stdio.h>
#include "../LaunchPolicy.h"

int main(void) {
    // Cover Sheet visible does not imply the device is locked.
    assert(SPRouteForApp(false, false, false) == SPLaunchOrdinary);
    assert(SPRouteForApp(true, false, false) == SPLaunchOrdinary);
    assert(SPRouteForApp(false, false, true) == SPLaunchSecureApp);
    assert(SPRouteForApp(true, false, true) == SPLaunchLockScreenCamera);
    // Locked launches never take the ordinary foreground route, even when
    // the Cover Sheet itself is hidden behind another secure app.
    for (int visible = 0; visible <= 1; ++visible) {
        assert(SPRouteForApp(false, true, visible) == SPLaunchSecureApp);
        assert(SPRouteForApp(true, true, visible) == SPLaunchLockScreenCamera);
    }
    puts("PASS: native host routes for locked devices and Notification Center");
    return 0;
}
