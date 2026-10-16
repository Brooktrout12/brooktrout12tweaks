#pragma once
#import <Foundation/Foundation.h>
#import "Rules.h"

#define D18_DOMAIN CFSTR("com.brooktrout12.dawn18")
#define D18_NOTIFY "com.brooktrout12.dawn18/preferences-changed"

NSArray<NSString *> *D18PreferenceKeys(void);
D18Configuration D18ReadConfiguration(void);
BOOL D18WriteConfiguration(D18Configuration configuration);
typedef void (*D18ConfigurationCallback)(D18Configuration configuration, void *context);
void D18ObserveConfiguration(D18ConfigurationCallback callback, void *context);
