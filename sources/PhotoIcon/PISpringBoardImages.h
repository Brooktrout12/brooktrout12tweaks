#pragma once
#import "PIPrivate.h"
typedef UIImage *(*PIIconRenderer)(SBIcon *, SBIconImageInfo, BOOL);
#ifdef __cplusplus
extern "C" {
#endif
void PIInstallAdditionalSpringBoardImages(PIIconRenderer renderer);
void PIRefreshAdditionalSpringBoardImages(void);
#ifdef __cplusplus
}
#endif
