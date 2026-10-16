#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static inline id SPGet(id object, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    return [object respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(object, sel) : nil;
}
static inline BOOL SPBool(id object, NSString *selector, BOOL fallback) {
    SEL sel = NSSelectorFromString(selector);
    return [object respondsToSelector:sel] ? ((BOOL (*)(id, SEL))objc_msgSend)(object, sel) : fallback;
}
static inline void SPVoid(id object, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if ([object respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(object, sel);
}
static inline id SPShared(NSString *name) { return SPGet(NSClassFromString(name), @"sharedInstance"); }

void SPSetStatus(NSString *status);
void SPDispatchAction(NSString *action, NSString *bundleID, BOOL requireUnlock, BOOL haptic);
void SPCancelPendingAction(void);
