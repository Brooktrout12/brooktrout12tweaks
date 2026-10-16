#pragma once
#import <Foundation/Foundation.h>
// Called only by SpringBoard's serial store queue. Exports cropped PNGs only.
BOOL PIPublishIcons(NSDictionary *manifest, NSString *privateDirectory, NSError **error);
