#pragma once
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <string.h>

// Check the actual runtime ABI before calling a private interface. 'i' accepts
// NSInteger/NSUInteger; 'b' accepts either Objective-C BOOL encoding on arm64.
static inline BOOL D18TypeMatches(char actual, char expected) {
    if (expected == 'i') return actual == 'q' || actual == 'Q';
    if (expected == 'b') return actual == 'B' || actual == 'c';
    return actual == expected;
}

static inline BOOL D18MethodMatches(Class cls, SEL selector, char result, const char *arguments) {
    Method method = class_getInstanceMethod(cls, selector);
    size_t count = strlen(arguments);
    if (!method || method_getNumberOfArguments(method) != count + 2) return NO;
    char type[64] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (!D18TypeMatches(type[0], result)) return NO;
    for (size_t i = 0; i < count; i++) {
        method_getArgumentType(method, (unsigned int)i + 2, type, sizeof(type));
        if (!D18TypeMatches(type[0], arguments[i])) return NO;
    }
    return YES;
}

static inline id D18GetObject(id object, SEL selector) {
    if (!D18MethodMatches(object_getClass(object), selector, '@', "")) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static inline BOOL D18SetObject(id object, SEL selector, id value) {
    if (!D18MethodMatches(object_getClass(object), selector, 'v', "@")) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(object, selector, value);
    return YES;
}
