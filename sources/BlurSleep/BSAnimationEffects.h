#pragma once
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include "BSAnimationStyle.h"

// Call inside a transaction with implicit actions disabled. The image starts
// centered at full size. The container is black. All styles end transparent.
void BSApplyAnimationStyle(UIImageView *image, UIView *container,
                           BSAnimationStyle style, double duration);
