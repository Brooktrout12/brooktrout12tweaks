#pragma once
#import <UIKit/UIKit.h>
__attribute__((visibility("hidden"))) UIImage *PISharedImage(NSString *identifier,
    CGSize size, CGFloat scale, CGFloat radius, BOOL masked);
__attribute__((visibility("hidden"))) UIImage *PISharedImageMatching(NSString *identifier, UIImage *native);
