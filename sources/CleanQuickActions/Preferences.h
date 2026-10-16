#pragma once
#import <Foundation/Foundation.h>

#define CQA_DOMAIN CFSTR("com.brooktrout12.cleanquickactions")
#define CQA_NOTIFY CFSTR("com.brooktrout12.cleanquickactions/preferences.changed")
typedef void (*CQAPreferenceCallback)(BOOL enabled);
void CQAObservePreference(CQAPreferenceCallback callback);
