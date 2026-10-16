#import "PIBlockCompatibility.h"
#include <Block.h>

void *PICopyBlockForSystem(const void *block) {
    // This is a C runtime call, not [block copy] or [block retain]. libclosure
    // performs the copy and initializes the heap block's authenticated metadata.
    // Call sites must satisfy the non-global, escaping-block contract in the
    // header. _Block_copy does NOT normalize globals: it returns them unchanged.
    return _Block_copy(block);
}
