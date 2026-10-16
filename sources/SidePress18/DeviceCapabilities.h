#pragma once
#import <LocalAuthentication/LocalAuthentication.h>

// The Accessibility click-speed page controls the Home button on Touch ID
// devices. Never add side-button choices to that native Home-button page.
// An unavailable/unknown biometric capability also takes the separate UI path.
static inline BOOL SPNeedsSeparateSideButtonTiming(void) {
    LAContext *context = [LAContext new];
    (void)[context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:NULL];
    return context.biometryType != LABiometryTypeFaceID;
}
