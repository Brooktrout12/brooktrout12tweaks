#import "Compatibility.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <stdlib.h>
#include <string.h>

static void (*originalTouch)(id, SEL, id);
static void (*originalPrimary)(id, SEL, id);
static char clearingKey;

static BOOL Signature(Class cls, SEL selector, unsigned count, const char *result) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != count) return NO;
    char *type = method_copyReturnType(method);
    BOOL valid = type && strcmp(type, result) == 0;
    free(type);
    if (valid && count == 3) {
        type = method_copyArgumentType(method, 2);
        valid = type && strcmp(type, "@") == 0;
        free(type);
    }
    return valid;
}
static void Clear(id header, SEL command, id sender, void (*fallback)(id, SEL, id)) {
    SEL getter = NSSelectorFromString(@"clearButton");
    id button = ((id (*)(id, SEL))objc_msgSend)(header, getter);
    // Only the header's own clear control is eligible. Never replace generic
    // UIControl behavior or clear a global list through a private data server.
    if (!button || (sender && sender != button) || !NSThread.isMainThread) {
        fallback(header, command, sender);
        return;
    }
    if ([objc_getAssociatedObject(header, &clearingKey) boolValue]) return;
    objc_setAssociatedObject(header, &clearingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Schedule guard cleanup first; the native action may remove its header.
    // libdispatch makes a C-runtime copy of this block (legacy arm64e safe).
    dispatch_async(dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(header, &clearingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
    ((void (*)(id, SEL, id))objc_msgSend)(header, NSSelectorFromString(@"_handleClearAll:"), button);
}
static void Touch(id self, SEL cmd, id sender) { Clear(self, cmd, sender, originalTouch); }
static void Primary(id self, SEL cmd, id sender) { Clear(self, cmd, sender, originalPrimary); }
static void Install(void) {
    Class cls = NSClassFromString(@"NCNotificationListSectionHeaderView");
    if (!cls || !Signature(cls, NSSelectorFromString(@"clearButton"), 2, "@") ||
        !Signature(cls, NSSelectorFromString(@"_handleClearAll:"), 3, "v")) {
        NSLog(@"[InstantClear18] Compatible notification header not found; leaving native behavior intact.");
        return;
    }
    SEL touch = NSSelectorFromString(@"_handleClearButtonTouchUpInside:");
    SEL primary = NSSelectorFromString(@"_handleClearButtonPrimaryActionTriggered:");
    if (Signature(cls, touch, 3, "v"))
        MSHookMessageEx(cls, touch, (IMP)Touch, (IMP *)&originalTouch);
    if (Signature(cls, primary, 3, "v"))
        MSHookMessageEx(cls, primary, (IMP)Primary, (IMP *)&originalPrimary);
}
__attribute__((constructor)) static void Initialize(void) {
    @autoreleasepool {
        if (!BTSupportsIOS17And18()) return;
        dispatch_async(dispatch_get_main_queue(), ^{ Install(); });
    }
}
