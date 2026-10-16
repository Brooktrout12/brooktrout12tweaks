#pragma once
#include <stddef.h>
#include <stdbool.h>

/* Inputs are Unicode-folded, lowercase alphanumeric strings from Foundation. */
bool BC18WarningText(const char *normalized);
bool BC18LearnMoreText(const char *normalized);

enum {
    BC18Group = 1 << 0,
    BC18Warning = 1 << 1,
    BC18Protected = 1 << 2,
    BC18LearnMore = 1 << 3
};
enum { BC18Keep, BC18Remove, BC18ClearGroup };

/* Pure policy shared by the live filter and the host regression tests. */
void BC18PlanWarningRemoval(const unsigned char *flags, size_t count,
                           unsigned char *actions);
