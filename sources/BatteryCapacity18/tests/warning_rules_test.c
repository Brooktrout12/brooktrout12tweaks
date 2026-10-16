#include "../WarningRules.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static void check(const unsigned char *flags, const unsigned char *expected, size_t count) {
    unsigned char actual[32];
    assert(count <= sizeof(actual));
    memset(actual, 0xFF, sizeof(actual));
    BC18PlanWarningRemoval(flags, count, actual);
    assert(!memcmp(actual, expected, count));
}

int main(void) {
    assert(BC18WarningText("importantbatterymessage"));
    assert(BC18WarningText("unabletoverifythisiphonehasagenuineapplebatterydetailsfromthisbatterymaynotbeaccurate"));
    assert(BC18WarningText("wichtigebatterienachricht"));
    assert(BC18WarningText("esnichtuberpruftwerdenobdiesesiphoneubereineoriginalbatterieverfugt"));
    assert(!BC18WarningText("thisiphoneisunabletodeterminebatteryhealth"));
    assert(!BC18WarningText("peakperformancecapability"));
    assert(!BC18WarningText("optimizedbatterycharging"));
    assert(!BC18WarningText("batteryhealth"));
    assert(!BC18WarningText(NULL));
    assert(BC18LearnMoreText("learnmore"));
    assert(BC18LearnMoreText("weitereinformationen"));
    assert(!BC18LearnMoreText("learnmoreaboutoptimizedbatterycharging"));

    /* Screenshot: custom warning card and Learn More in their own section,
       followed by capacity, performance and charging groups. */
    const unsigned char screenshot[] = {BC18Group, BC18Warning, BC18LearnMore,
        BC18Group, BC18Protected, BC18Protected, BC18Protected, BC18Protected,
        BC18Group, BC18Protected, BC18Group, BC18Protected};
    const unsigned char screenshotExpected[] = {BC18Remove, BC18Remove, BC18Remove,
        BC18Keep, BC18Keep, BC18Keep, BC18Keep, BC18Keep,
        BC18Keep, BC18Keep, BC18Keep, BC18Keep};
    check(screenshot, screenshotExpected, sizeof(screenshot));

    /* Header warning plus link. */
    const unsigned char header[] = {BC18Group | BC18Warning, BC18LearnMore,
        BC18Group, BC18Protected};
    const unsigned char headerExpected[] = {BC18Remove, BC18Remove, BC18Keep, BC18Keep};
    check(header, headerExpected, sizeof(header));

    /* Mixed section: do not drop unknown controls or unrelated Learn More. */
    const unsigned char mixed[] = {BC18Group | BC18Warning, BC18Warning,
        BC18Protected, BC18LearnMore};
    const unsigned char mixedExpected[] = {BC18ClearGroup, BC18Remove, BC18Keep, BC18Keep};
    check(mixed, mixedExpected, sizeof(mixed));

    /* A cell containing both a protected control and warning is preserved. */
    const unsigned char protected[] = {BC18Group, BC18Warning | BC18Protected};
    const unsigned char protectedExpected[] = {BC18Keep, BC18Keep};
    check(protected, protectedExpected, sizeof(protected));

    const unsigned char normal[] = {BC18Group, BC18LearnMore, BC18Group, BC18Protected};
    const unsigned char normalExpected[] = {BC18Keep, BC18Keep, BC18Keep, BC18Keep};
    check(normal, normalExpected, sizeof(normal));

    /* Before and after an asynchronous warning insertion / rendered discovery. */
    const unsigned char late[] = {BC18Group, BC18Protected, BC18Group, BC18Warning};
    const unsigned char lateExpected[] = {BC18Keep, BC18Keep, BC18Remove, BC18Remove};
    check(late, lateExpected, sizeof(late));
    BC18PlanWarningRemoval(NULL, 0, NULL);
    puts("Warning text and section-removal regression tests passed.");
    return 0;
}
