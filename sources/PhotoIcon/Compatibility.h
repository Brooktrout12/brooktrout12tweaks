#pragma once
#import <Foundation/Foundation.h>

// Keep future major versions opt-in; all 17.x and 18.x point releases qualify.
static inline BOOL BTSupportsIOS17And18(void) {
    NSInteger major = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
    return major == 17 || major == 18;
}
