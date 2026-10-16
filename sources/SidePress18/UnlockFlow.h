#import <Foundation/Foundation.h>

// The action callback is a C function, not an Objective-C block. Keeping the
// selected values here avoids passing legacy arm64e stack blocks into UIKit.
typedef void (*SPUnlockedAction)(NSString *action, NSString *bundle, BOOL haptic);

// Invoke only on the main thread. This requests Apple's own unlock UI and only
// calls the action after real authentication and dismissal of the Cover Sheet.
void SPRequestNativeUnlock(NSString *action, NSString *bundle, BOOL haptic,
                           SPUnlockedAction performAction);
void SPCancelNativeUnlock(void);
