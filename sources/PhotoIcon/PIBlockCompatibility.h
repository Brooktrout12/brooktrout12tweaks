#pragma once

// A legacy Linux arm64e compiler leaves stack-block isa pointers unsigned.
// System Objective-C APIs may retain a callback before copying it. Give them
// the Blocks runtime's owned copy instead of the original stack object.
// Keep this raw-pointer boundary out of line: ARC is allowed to elide ordinary
// block copies, particularly for synchronous/noescape framework callbacks.
#ifdef __cplusplus
extern "C" {
#endif
void *PICopyBlockForSystem(const void *block)
    __attribute__((noinline, visibility("hidden")));
#ifdef __cplusplus
}
#endif

// typeof is unevaluated: the callback expression is evaluated exactly once.
// Transfer the copy's +1 ownership to ARC without losing the block's signature.
// Only pass capturing/heap callbacks, never global or noescape literals.
// _Block_copy is a no-op for globals; the old compiler's global isa is also
// unsigned, so transferring such a result to ARC would crash on release.
// check_system_blocks.py enforces this at each Objective-C handoff.
#define PI_SYSTEM_BLOCK(...) \
    ((__bridge_transfer __typeof__((__VA_ARGS__))) \
        PICopyBlockForSystem((__bridge const void *)(__VA_ARGS__)))
