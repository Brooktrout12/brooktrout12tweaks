#ifndef BC18_AMPERAGE_RULES_H
#define BC18_AMPERAGE_RULES_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    BCAmperageSourceNone = 0,
    BCAmperageSourceInstant,
    BCAmperageSourceBatteryDataInstant,
    BCAmperageSourceAverage,
    BCAmperageSourceBatteryDataAverage,
    BCAmperageSourceLimit
} BCAmperageSource;

typedef enum {
    BCAmperageInputInvalid = 0,
    BCAmperageInputSigned,
    BCAmperageInputUnsigned,
    BCAmperageInputFloating
} BCAmperageInput;

typedef struct {
    BCAmperageSource source;
    BCAmperageInput kind;
    union {
        int64_t signedValue;
        uint64_t unsignedValue;
        double floatingValue;
    } value;
} BCAmperageReading;

typedef struct {
    long long signedMA; // Negative: discharging. Positive: charging. Zero is valid.
    BCAmperageSource source;
    bool available;
} BCAmperage;

BCAmperage BCSelectAmperage(const BCAmperageReading *readings, size_t count);
const char *BCAmperageSourceKey(BCAmperageSource source);

#endif
