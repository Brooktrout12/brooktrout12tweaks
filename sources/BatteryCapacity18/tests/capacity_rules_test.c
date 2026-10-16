#include "../CapacityRules.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#define VALUE(key, val) (BCReading){ key, val, true }
#define CHECK_CLOSE(a, b) assert(fabs((a) - (b)) < 0.000001)

int main(void) {
    // Hardware readings intentionally disagree with a hypothetical Apple 100%.
    BCReading normal[] = {VALUE(BCSourceNominal, 2593), VALUE(BCSourceDesign, 3046)};
    BCCapacities c = BCSelectCapacities(normal, 2);
    assert(c.fullChargeMAh == 2593 && c.designMAh == 3046);
    assert(c.hasRatio && c.fullChargeSource == BCSourceNominal);
    CHECK_CLOSE(c.ratioPercent, 100.0 * 2593.0 / 3046.0);

    // An iPad / another model must use its own reported design value.
    BCReading tablet[] = {VALUE(BCSourceBatteryDataNominal, 9900), VALUE(BCSourceBatteryDataDesign, 10758)};
    c = BCSelectCapacities(tablet, 2);
    assert(c.designMAh == 10758 && c.fullChargeMAh == 9900);
    assert(c.hasRatio);

    // Above-design packs must not be silently clamped to 100%.
    BCReading newPack[] = {VALUE(BCSourceNominal, 3230), VALUE(BCSourceDesign, 3046)};
    c = BCSelectCapacities(newPack, 2);
    assert(c.hasRatio && c.ratioPercent > 100 && c.fullChargeMAh == 3230);

    // A raw full-charge reading is a fallback, not a current-charge reading.
    BCReading raw[] = {VALUE(BCSourceRawMaximum, 2810), VALUE(BCSourceDesign, 3046)};
    c = BCSelectCapacities(raw, 2);
    assert(c.hasRatio && c.fullChargeSource == BCSourceRawMaximum && c.fullChargeMAh == 2810);

    BCReading nominalPreferred[] = {VALUE(BCSourceRawMaximum, 2600), VALUE(BCSourceBatteryDataNominal, 2780),
        VALUE(BCSourceNominal, 2800), VALUE(BCSourceDesign, 3046)};
    c = BCSelectCapacities(nominalPreferred, 4);
    assert(c.fullChargeMAh == 2800 && c.fullChargeSource == BCSourceNominal);

    // Invalid preferred fields must not prevent a valid lower-priority source.
    BCReading fallback[] = {VALUE(BCSourceNominal, 0), VALUE(BCSourceBatteryDataNominal, 65535),
        VALUE(BCSourceRawMaximum, 2700), VALUE(BCSourceDesign, 0), VALUE(BCSourceBatteryDataDesign, 3046)};
    c = BCSelectCapacities(fallback, 5);
    assert(c.hasRatio && c.fullChargeMAh == 2700 && c.designMAh == 3046);
    assert(c.fullChargeSource == BCSourceRawMaximum && c.designSource == BCSourceBatteryDataDesign);

    // Missing one side must not produce a zero or a guessed ratio.
    c = BCSelectCapacities(normal, 1);
    assert(c.hasFullCharge && !c.hasDesign && !c.hasRatio);
    c = BCSelectCapacities(normal + 1, 1);
    assert(!c.hasFullCharge && c.hasDesign && !c.hasRatio);
    c = BCSelectCapacities(NULL, 0);
    assert(!c.hasFullCharge && !c.hasDesign && !c.hasRatio);

    const double badValues[] = {0, -1, NAN, INFINITY, -INFINITY, 32767, 65535, 2147483647, 4294967295.0, 50001, 2800.5};
    for (size_t i = 0; i < sizeof(badValues) / sizeof(badValues[0]); i++) {
        BCReading bad[] = {VALUE(BCSourceNominal, badValues[i]), VALUE(BCSourceDesign, badValues[i])};
        c = BCSelectCapacities(bad, 2);
        assert(!c.hasFullCharge && !c.hasDesign && !c.hasRatio);
    }
    BCReading wrongType[] = {{BCSourceNominal, 2800, false}, {BCSourceDesign, 3046, false}};
    c = BCSelectCapacities(wrongType, 2);
    assert(!c.hasRatio && !c.hasFullCharge && !c.hasDesign);

    // A design value on a percentage scale cannot become a denominator.
    BCReading percentageDesign[] = {VALUE(BCSourceNominal, 2800), VALUE(BCSourceDesign, 100)};
    c = BCSelectCapacities(percentageDesign, 2);
    assert(c.hasFullCharge && !c.hasDesign && !c.hasRatio);

    // Unknown keys (including normalized MaxCapacity) are never accepted.
    BCReading unknown[] = {VALUE(BCSourceNone, 100), VALUE((BCSource)99, 3046)};
    c = BCSelectCapacities(unknown, 2);
    assert(!c.hasFullCharge && !c.hasDesign && !c.hasRatio);

    // Reported pack-level capacities must not be multiplied by cell count.
    BCReading twoCellPack[] = {VALUE(BCSourceBatteryDataRawMaximum, 4200), VALUE(BCSourceDesign, 4323)};
    c = BCSelectCapacities(twoCellPack, 2);
    assert(c.fullChargeMAh == 4200 && c.designMAh == 4323);
    CHECK_CLOSE(c.ratioPercent, 100.0 * 4200.0 / 4323.0);

    // Current charge is read independently in mAh, never from health or charge %.
    BCReading charged[] = {VALUE(BCSourceNominal, 3129), VALUE(BCSourceDesign, 3028),
        VALUE(BCSourceRawCurrent, 1472)};
    c = BCSelectCapacities(charged, 3);
    assert(c.hasCurrentCharge && c.currentChargeMAh == 1472);
    assert(c.currentChargeSource == BCSourceRawCurrent);
    assert(c.fullChargeMAh == 3129 && c.designMAh == 3028 && c.ratioPercent > 100);

    // Missing, invalid, zero, and small raw values must stay distinguishable.
    c = BCSelectCapacities(charged, 2);
    assert(!c.hasCurrentCharge && c.hasRatio);
    BCReading empty[] = {VALUE(BCSourceRawCurrent, 0)};
    c = BCSelectCapacities(empty, 1);
    assert(c.hasCurrentCharge && c.currentChargeMAh == 0);
    assert(!c.hasFullCharge && !c.hasDesign && !c.hasRatio);
    BCReading lowCharge[] = {VALUE(BCSourceRawCurrent, 50)};
    c = BCSelectCapacities(lowCharge, 1);
    assert(c.hasCurrentCharge && c.currentChargeMAh == 50);

    BCReading nestedCharge[] = {VALUE(BCSourceRawCurrent, -1),
        VALUE(BCSourceBatteryDataRawCurrent, 1680)};
    c = BCSelectCapacities(nestedCharge, 2);
    assert(c.hasCurrentCharge && c.currentChargeSource == BCSourceBatteryDataRawCurrent
        && c.currentChargeMAh == 1680);
    nestedCharge[0] = VALUE(BCSourceRawCurrent, 1642);
    c = BCSelectCapacities(nestedCharge, 2);
    assert(c.currentChargeSource == BCSourceRawCurrent && c.currentChargeMAh == 1642);
    nestedCharge[0] = VALUE(BCSourceRawCurrent, 0);
    c = BCSelectCapacities(nestedCharge, 2);
    assert(c.currentChargeSource == BCSourceRawCurrent && c.currentChargeMAh == 0);

    const double badCharge[] = {-1, NAN, INFINITY, -INFINITY, 32767, 65535,
        2147483647, 4294967295.0, 50001, 12.5};
    for (size_t i = 0; i < sizeof(badCharge) / sizeof(badCharge[0]); ++i) {
        BCReading bad[] = {VALUE(BCSourceRawCurrent, badCharge[i]),
            VALUE(BCSourceBatteryDataRawCurrent, badCharge[i])};
        assert(!BCSelectCapacities(bad, 2).hasCurrentCharge);
    }
    BCReading wrongChargeType[] = {{BCSourceRawCurrent, 1500, false}};
    assert(!BCSelectCapacities(wrongChargeType, 1).hasCurrentCharge);
    assert(!BCSelectCapacities(unknown, 2).hasCurrentCharge);
    assert(!strcmp(BCSourceKey(BCSourceRawCurrent), "AppleRawCurrentCapacity"));
    assert(!strcmp(BCSourceKey(BCSourceBatteryDataRawCurrent), "BatteryData.AppleRawCurrentCapacity"));

    puts("PASS: capacity selection, source precedence, multiple device sizes, >100%, missing data, invalid data, no normalized-capacity input, and pack units");
    puts("PASS: raw current charge in mAh, independent capacity metrics, source priority, valid zero, and invalid/missing fields");
    return 0;
}
