#include "BTVolume.h"
#include <math.h>
#include <string.h>

static uint32_t BTReadBE32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | p[3];
}
static uint64_t BTReadBE64(const uint8_t *p) {
    return ((uint64_t)BTReadBE32(p) << 32) | BTReadBE32(p + 4);
}
int BTVolumePercent(double value) {
    if (!isfinite(value)) return 100;
    if (value <= 0) return 0;
    if (value >= 100) return 100;
    return (int)(value + 0.5);
}
bool BTScaleCAF(uint8_t *bytes, size_t length, unsigned int percent) {
    /* Accept the shipped, uncompressed stereo format only. Validate the
       entire container before modifying any byte; never guess PCM offsets. */
    if (!bytes || percent > 100 || length < 8 ||
        memcmp(bytes, "caff\0\1", 6) != 0) return false;
    size_t position = 8, dataOffset = 0, dataLength = 0;
    bool description = false, audio = false;
    while (position < length) {
        if (length - position < 12) return false;
        uint8_t *chunk = bytes + position;
        uint64_t size = BTReadBE64(chunk + 4);
        position += 12;
        if (size > length - position) return false;
        if (memcmp(chunk, "desc", 4) == 0) {
            if (description || audio || size != 32 || position != 20) return false;
            const uint8_t *format = bytes + position;
            /* IEEE-754 44100.0, big-endian CAF fields; signed little-endian PCM. */
            if (BTReadBE64(format) != UINT64_C(0x40e5888000000000) ||
                memcmp(format + 8, "lpcm", 4) != 0 ||
                BTReadBE32(format + 12) != 2 ||
                BTReadBE32(format + 16) != 4 ||
                BTReadBE32(format + 20) != 1 ||
                BTReadBE32(format + 24) != 2 ||
                BTReadBE32(format + 28) != 16) return false;
            description = true;
        } else if (memcmp(chunk, "data", 4) == 0) {
            if (!description || audio || size < 4 || (size - 4) % 4 != 0) return false;
            dataOffset = position + 4; /* Skip the CAF edit count. */
            dataLength = (size_t)size - 4;
            audio = true;
        }
        position += (size_t)size;
    }
    if (!description || !audio || !dataLength) return false;
    if (percent == 100) return true; /* Bit-for-bit original at maximum. */
    for (size_t i = dataOffset; i < dataOffset + dataLength; i += 2) {
        uint32_t encoded = bytes[i] | ((uint32_t)bytes[i + 1] << 8);
        int32_t sample = encoded >= 32768 ? (int32_t)encoded - 65536 : (int32_t)encoded;
        int32_t numerator = sample * (int32_t)percent;
        int32_t scaled = numerator >= 0 ? (numerator + 50) / 100 : -((-numerator + 50) / 100);
        uint32_t output = scaled < 0 ? (uint32_t)(scaled + 65536) : (uint32_t)scaled;
        bytes[i] = (uint8_t)output;
        bytes[i + 1] = (uint8_t)(output >> 8);
    }
    return true;
}
