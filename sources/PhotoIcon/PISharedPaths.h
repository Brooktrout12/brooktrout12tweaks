#pragma once
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
__attribute__((visibility("hidden"))) NSString *PISharedIconDirectory(void);
#ifdef __cplusplus
}
#endif
#define PI_SHARED_ICON_NOTIFICATION "com.brooktrout12.photoicon.sharedIconsChanged"
