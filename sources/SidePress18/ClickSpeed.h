#pragma once
#import "Shared.h"

// Stored separately from Apple's native speed enum. No system preference is
// left with an unsupported enum value when SidePress18 is uninstalled.
#define SP_CLICK_SPEED_KEY @"ClickSpeedOverride"

static inline NSInteger SPClickSpeedChoice(void) {
    id value = SPRead(SP_CLICK_SPEED_KEY, @0);
    NSInteger choice = [value isKindOfClass:NSNumber.class] ? [value integerValue] : 0;
    return choice == 1 || choice == 2 ? choice : 0;
}

static inline NSTimeInterval SPClickSpeedInterval(void) {
    switch (SPClickSpeedChoice()) {
        case 1: return 0.22;
        case 2: return 0.16;
        default: return 0.0; // Preserve the current native speed.
    }
}
