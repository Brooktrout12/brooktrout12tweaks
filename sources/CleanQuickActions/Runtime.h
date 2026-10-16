#pragma once
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <string.h>

static inline BOOL CQAMethodMatches(Class cls, SEL selector, char result, const char *arguments) {
    Method method = class_getInstanceMethod(cls, selector);
    size_t count = strlen(arguments);
    if (!method || method_getNumberOfArguments(method) != count + 2) return NO;
    char type[64] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != result) return NO;
    for (size_t i = 0; i < count; i++) {
        method_getArgumentType(method, (unsigned int)i + 2, type, sizeof(type));
        if (arguments[i] == 'b') {
            if (type[0] != 'B' && type[0] != 'c') return NO;
        } else if (type[0] != arguments[i]) return NO;
    }
    return YES;
}

static inline id CQAGetObject(id object, SEL selector) {
    if (!CQAMethodMatches(object_getClass(object), selector, '@', "")) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}
