#include "../AmperageRules.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static BCAmperageReading signedReading(BCAmperageSource source, int64_t value) {
    return (BCAmperageReading){.source = source, .kind = BCAmperageInputSigned,
        .value.signedValue = value};
}

static BCAmperageReading unsignedReading(BCAmperageSource source, uint64_t value) {
    return (BCAmperageReading){.source = source, .kind = BCAmperageInputUnsigned,
        .value.unsignedValue = value};
}

static BCAmperageReading floatingReading(BCAmperageSource source, double value) {
    return (BCAmperageReading){.source = source, .kind = BCAmperageInputFloating,
        .value.floatingValue = value};
}

static void check(BCAmperageReading reading, long long expected) {
    BCAmperage result = BCSelectAmperage(&reading, 1);
    assert(result.available && result.signedMA == expected && result.source == reading.source);
}

int main(void) {
    const BCAmperageSource instant = BCAmperageSourceInstant;
    // Check every accepted whole-mA value and both negative integer encodings.
    // In particular, a uint64_t -300 must not be rounded through double to zero.
    for (int64_t value = -50000; value <= 50000; value++) {
        check(signedReading(instant, value), value);
        check(floatingReading(instant, (double)value), value);
        check(unsignedReading(instant, (uint64_t)value), value);
        if (value < 0) {
            check(unsignedReading(instant, (uint32_t)value), value);
            check(signedReading(instant, (uint32_t)value), value);
        }
    }

    // Missing/invalid is distinct from zero. Do not decode 16-bit sentinels,
    // out-of-range currents, large integer limits, or imprecise wrapped floats.
    assert(!BCSelectAmperage(NULL, 0).available);
    BCAmperageReading invalid[] = {
        {.source = instant, .kind = BCAmperageInputInvalid}, // missing/string/boolean
        signedReading(instant, 50001), signedReading(instant, -50001),
        signedReading(instant, INT64_MIN), signedReading(instant, INT64_MAX),
        unsignedReading(instant, UINT64_MAX - 50000),
        unsignedReading(instant, UINT32_MAX - 50000),
        unsignedReading(instant, UINT64_C(1) << 32),
        unsignedReading(instant, UINT64_C(1) << 63),
        unsignedReading(instant, UINT16_MAX),
        floatingReading(instant, NAN), floatingReading(instant, INFINITY),
        floatingReading(instant, -INFINITY), floatingReading(instant, 1.5),
        floatingReading(instant, -1.5), floatingReading(instant, 50001),
        floatingReading(instant, -50001),
        floatingReading(instant, (double)(UINT64_MAX - 299)),
        floatingReading(instant, (double)(UINT32_MAX - 299)),
        signedReading(BCAmperageSourceNone, -300),
        signedReading((BCAmperageSource)99, -300)
    };
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++)
        assert(!BCSelectAmperage(&invalid[i], 1).available);

    // Priority is independent of input order. A preferred zero or charging
    // reading must win even when an older/averaged field says discharging.
    BCAmperageReading candidates[] = {
        signedReading(BCAmperageSourceBatteryDataAverage, -440),
        signedReading(BCAmperageSourceAverage, -330),
        signedReading(BCAmperageSourceBatteryDataInstant, -220),
        signedReading(instant, -110)
    };
    BCAmperage result = BCSelectAmperage(candidates, 4);
    assert(result.available && result.signedMA == -110 && result.source == instant);
    candidates[3] = signedReading(instant, 0);
    result = BCSelectAmperage(candidates, 4);
    assert(result.available && result.signedMA == 0 && result.source == instant);
    candidates[3] = signedReading(instant, 1200);
    result = BCSelectAmperage(candidates, 4);
    assert(result.available && result.signedMA == 1200 && result.source == instant);
    candidates[3].kind = BCAmperageInputInvalid;
    result = BCSelectAmperage(candidates, 4);
    assert(result.signedMA == -220 && result.source == BCAmperageSourceBatteryDataInstant);
    candidates[2] = floatingReading(BCAmperageSourceBatteryDataInstant, NAN);
    result = BCSelectAmperage(candidates, 4);
    assert(result.signedMA == -330 && result.source == BCAmperageSourceAverage);
    candidates[1] = signedReading(BCAmperageSourceAverage, INT64_MAX);
    result = BCSelectAmperage(candidates, 4);
    assert(result.signedMA == -440 && result.source == BCAmperageSourceBatteryDataAverage);
    candidates[0].kind = BCAmperageInputInvalid;
    assert(!BCSelectAmperage(candidates, 4).available);

    assert(!strcmp(BCAmperageSourceKey(instant), "InstantAmperage"));
    assert(!strcmp(BCAmperageSourceKey(BCAmperageSourceBatteryDataInstant), "BatteryData.InstantAmperage"));
    assert(!strcmp(BCAmperageSourceKey(BCAmperageSourceAverage), "Amperage"));
    assert(!strcmp(BCAmperageSourceKey(BCAmperageSourceBatteryDataAverage), "BatteryData.Amperage"));
    assert(!strcmp(BCAmperageSourceKey(BCAmperageSourceNone), "Unavailable"));
    puts("PASS: signed battery current in mA, exact 32/64-bit decoding, charging/zero/discharging, bounds, invalid data, and source fallback");
    return 0;
}
