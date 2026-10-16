#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../ClickSpeedPolicy.h"

static void near(double actual, double expected) { assert(fabs(actual - expected) < 0.000001); }
int main(void) {
    // A recognizer's partial window must shorten too, not remain unchanged
    // because that component is shorter than the requested overall window.
    near(SPScaledClickWait(0.15, 0.30, 0.16), 0.08);
    near(SPScaledClickWait(0.30, 0.30, 0.22), 0.22);
    near(SPScaledClickWait(0.35, 0.70, 0.16), 0.08);
    // Native selection and zero-wait recognizers must introduce no delay.
    near(SPScaledClickWait(0.30, 0.30, 0), 0.30);
    near(SPScaledClickWait(0, 0.30, 0.16), 0);
    // Never slow an already shorter native window; handle absent metadata.
    near(SPScaledClickWait(0.05, 0.10, 0.16), 0.05);
    near(SPScaledClickWait(0.30, 0, 0.16), 0.16);
    near(SPScaledClickWait(0.30, NAN, 0.16), 0.16);
    near(SPScaledClickWait(0.30, 0.30, NAN), 0.30);
    puts("PASS: partial/native/absent timing windows and restoration policy");
}
