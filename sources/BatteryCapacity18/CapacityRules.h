#ifndef BC18_CAPACITY_RULES_H
#define BC18_CAPACITY_RULES_H
#include <stdbool.h>
#include <stddef.h>

// Values are already reported in mAh. Normalized MaxCapacity/CurrentCapacity
// percentages are deliberately not represented in this interface.
typedef enum {
    BCSourceNone = 0,
    BCSourceNominal,
    BCSourceBatteryDataNominal,
    BCSourceRawMaximum,
    BCSourceBatteryDataRawMaximum,
    BCSourceDesign,
    BCSourceBatteryDataDesign,
    BCSourceRawCurrent,
    BCSourceBatteryDataRawCurrent,
    BCSourceLimit
} BCSource;

typedef struct {
    BCSource source;
    double value;
    bool numeric; // CFNumber, never CFBoolean or an unparsed string.
} BCReading;

typedef struct {
    long long fullChargeMAh;
    long long designMAh;
    BCSource fullChargeSource;
    BCSource designSource;
    bool hasFullCharge;
    bool hasDesign;
    bool hasRatio;
    double ratioPercent;
    long long currentChargeMAh;
    BCSource currentChargeSource;
    bool hasCurrentCharge;
} BCCapacities;

BCCapacities BCSelectCapacities(const BCReading *readings, size_t count);
const char *BCSourceKey(BCSource source);

#endif
