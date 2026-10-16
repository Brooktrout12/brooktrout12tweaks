#pragma once
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <string.h>

static inline BOOL BC18TypeMatches(char actual, char expected) {
    if (expected == 'b') return actual == 'B' || actual == 'c';
    if (expected == 'i') return actual == 'Q' || actual == 'q';
    return actual == expected;
}

static inline BOOL BC18MethodMatches(Class cls, SEL selector, char result, const char *arguments) {
    Method method = class_getInstanceMethod(cls, selector);
    size_t count = strlen(arguments);
    if (!method || method_getNumberOfArguments(method) != count + 2) return NO;
    char type[64] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (!BC18TypeMatches(type[0], result)) return NO;
    for (size_t i = 0; i < count; i++) {
        method_getArgumentType(method, (unsigned int)i + 2, type, sizeof(type));
        if (!BC18TypeMatches(type[0], arguments[i])) return NO;
    }
    return YES;
}

static inline id BC18GetObject(id object, SEL selector) {
    if (!BC18MethodMatches(object_getClass(object), selector, '@', "")) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static inline BOOL BC18GetBool(id object, SEL selector) {
    if (!BC18MethodMatches(object_getClass(object), selector, 'b', "")) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}

static inline BOOL BC18SetObject(id object, SEL selector, id value) {
    if (!BC18MethodMatches(object_getClass(object), selector, 'v', "@")) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(object, selector, value);
    return YES;
}
