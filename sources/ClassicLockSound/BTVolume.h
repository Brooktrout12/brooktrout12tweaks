#ifndef BT_VOLUME_H
#define BT_VOLUME_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Percent is linear PCM amplitude relative to the original recording. */
int BTVolumePercent(double value);
bool BTScaleCAF(uint8_t *bytes, size_t length, unsigned int percent);
#endif
