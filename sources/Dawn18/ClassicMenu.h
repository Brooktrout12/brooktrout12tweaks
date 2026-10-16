#pragma once
#import <UIKit/UIKit.h>

// Caller verifies the private menu-list class and Home Screen ownership.
// Main-thread only. Updates the two native background effect views in place.
void D18UpdateClassicMenuMaterials(UIView *list, BOOL enabled);
