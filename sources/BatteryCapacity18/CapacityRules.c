#include "CapacityRules.h"
#include <math.h>

static bool valid(BCReading r, bool design) {
    if (!r.numeric || !isfinite(r.value) || r.value != floor(r.value)) return false;
    if (r.value < (design ? 300 : 1) || r.value > 50000) return false;
    // Common invalid / uninitialised fuel-gauge sentinels.
    return r.value != 32767 && r.value != 65535;
}

static bool validCurrentCharge(BCReading r) {
    if (!r.numeric || !isfinite(r.value) || r.value != floor(r.value)) return false;
    // Empty is a valid current-charge reading; it is distinct from missing.
    if (r.value < 0 || r.value > 50000) return false;
    return r.value != 32767 && r.value != 65535;
}

BCCapacities BCSelectCapacities(const BCReading *readings, size_t count) {
    BCCapacities result = {0};
    const BCSource fccOrder[] = {BCSourceNominal, BCSourceBatteryDataNominal,
        BCSourceRawMaximum, BCSourceBatteryDataRawMaximum};
    const BCSource designOrder[] = {BCSourceDesign, BCSourceBatteryDataDesign};
    const BCSource currentOrder[] = {BCSourceRawCurrent, BCSourceBatteryDataRawCurrent};
    if (!readings) return result;
    for (size_t rank = 0; rank < sizeof(fccOrder) / sizeof(fccOrder[0]); rank++) {
        for (size_t i = 0; i < count && !result.hasFullCharge; i++) {
            if (readings[i].source == fccOrder[rank] && valid(readings[i], false)) {
                result.fullChargeMAh = (long long)readings[i].value;
                result.fullChargeSource = readings[i].source;
                result.hasFullCharge = true;
            }
        }
    }
    for (size_t rank = 0; rank < sizeof(designOrder) / sizeof(designOrder[0]); rank++) {
        for (size_t i = 0; i < count && !result.hasDesign; i++) {
            if (readings[i].source == designOrder[rank] && valid(readings[i], true)) {
                result.designMAh = (long long)readings[i].value;
                result.designSource = readings[i].source;
                result.hasDesign = true;
            }
        }
    }
    result.hasRatio = result.hasFullCharge && result.hasDesign;
    if (result.hasRatio) {
        result.ratioPercent = 100.0 * (double)result.fullChargeMAh / (double)result.designMAh;
    }
    for (size_t rank = 0; rank < sizeof(currentOrder) / sizeof(currentOrder[0]); rank++) {
        for (size_t i = 0; i < count && !result.hasCurrentCharge; i++) {
            if (readings[i].source == currentOrder[rank] && validCurrentCharge(readings[i])) {
                result.currentChargeMAh = (long long)readings[i].value;
                result.currentChargeSource = readings[i].source;
                result.hasCurrentCharge = true;
            }
        }
    }
    // Do not cap at 100%, derive mAh from percentages, or multiply by cell count.
    return result;
}

const char *BCSourceKey(BCSource source) {
    switch (source) {
        case BCSourceNominal: return "NominalChargeCapacity";
        case BCSourceBatteryDataNominal: return "BatteryData.NominalChargeCapacity";
        case BCSourceRawMaximum: return "AppleRawMaxCapacity";
        case BCSourceBatteryDataRawMaximum: return "BatteryData.AppleRawMaxCapacity";
        case BCSourceDesign: return "DesignCapacity";
        case BCSourceBatteryDataDesign: return "BatteryData.DesignCapacity";
        case BCSourceRawCurrent: return "AppleRawCurrentCapacity";
        case BCSourceBatteryDataRawCurrent: return "BatteryData.AppleRawCurrentCapacity";
        default: return "Unavailable";
    }
}
