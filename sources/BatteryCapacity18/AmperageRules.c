#include "AmperageRules.h"
#include <math.h>

// Broad sanity bound for a phone/tablet battery, not a model-specific estimate.
#define BC_MAX_CURRENT_MA INT64_C(50000)

static bool normalizeUnsigned(uint64_t value, long long *result) {
    if (value <= BC_MAX_CURRENT_MA) {
        *result = (long long)value;
    } else if (value >= UINT64_MAX - (BC_MAX_CURRENT_MA - 1)) {
        // Decode a negative 64-bit two's-complement reading without overflow
        // or rounding a large integer through double first.
        *result = -(long long)(UINT64_MAX - value) - 1;
    } else if (value <= UINT32_MAX && value >= UINT32_MAX - (BC_MAX_CURRENT_MA - 1)) {
        *result = -(long long)(UINT32_MAX - value) - 1;
    } else {
        return false;
    }
    return true;
}

static bool normalize(BCAmperageReading reading, long long *result) {
    switch (reading.kind) {
        case BCAmperageInputSigned:
            if (reading.value.signedValue >= 0)
                return normalizeUnsigned((uint64_t)reading.value.signedValue, result);
            if (reading.value.signedValue < -BC_MAX_CURRENT_MA) return false;
            *result = reading.value.signedValue;
            return true;
        case BCAmperageInputUnsigned:
            return normalizeUnsigned(reading.value.unsignedValue, result);
        case BCAmperageInputFloating: {
            double value = reading.value.floatingValue;
            // Only already-signed, exact whole-mA floats are usable. Wrapped
            // floating-point values may already have lost their low bits.
            if (!isfinite(value) || value != floor(value)
                || value < -BC_MAX_CURRENT_MA || value > BC_MAX_CURRENT_MA) return false;
            *result = (long long)value;
            return true;
        }
        default:
            return false;
    }
}

BCAmperage BCSelectAmperage(const BCAmperageReading *readings, size_t count) {
    BCAmperage result = {0};
    const BCAmperageSource order[] = {BCAmperageSourceInstant,
        BCAmperageSourceBatteryDataInstant, BCAmperageSourceAverage,
        BCAmperageSourceBatteryDataAverage};
    if (!readings) return result;
    for (size_t rank = 0; rank < sizeof(order) / sizeof(order[0]); rank++) {
        for (size_t i = 0; i < count; i++) {
            if (readings[i].source == order[rank] && normalize(readings[i], &result.signedMA)) {
                result.source = readings[i].source;
                result.available = true;
                return result;
            }
        }
    }
    return result;
}

const char *BCAmperageSourceKey(BCAmperageSource source) {
    switch (source) {
        case BCAmperageSourceInstant: return "InstantAmperage";
        case BCAmperageSourceBatteryDataInstant: return "BatteryData.InstantAmperage";
        case BCAmperageSourceAverage: return "Amperage";
        case BCAmperageSourceBatteryDataAverage: return "BatteryData.Amperage";
        default: return "Unavailable";
    }
}
