#ifndef SP_LAUNCH_POLICY_H
#define SP_LAUNCH_POLICY_H
#include <stdbool.h>

typedef enum {
    SPLaunchOrdinary,
    SPLaunchLockScreenCamera,
    SPLaunchSecureApp
} SPLaunchRoute;

// A visible Cover Sheet can be Notification Center on an unlocked device.
// Conversely, biometric authentication alone does not dismiss the UI lock.
static inline SPLaunchRoute SPRouteForApp(bool camera, bool uiLocked, bool coverVisible) {
    if (camera && (uiLocked || coverVisible)) return SPLaunchLockScreenCamera;
    if (uiLocked || coverVisible) return SPLaunchSecureApp;
    return SPLaunchOrdinary;
}
#endif
