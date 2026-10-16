#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <string.h>

// Refuse a hook if the actual runtime ABI differs from the checked declaration.
static inline BOOL PITypeMatches(const char *actual, const char *expected) {
    while (*actual && strchr("rnNoORV", *actual)) actual++;
    if (expected[0] == '@') return actual[0] == '@';
    if (expected[0] == 'B') return actual[0] == 'B' || actual[0] == 'c';
    if (expected[0] == '^') return actual[0] == '^' && actual[1] == expected[1];
    return strcmp(actual, expected) == 0;
}
static inline BOOL PIHookMethod(Class cls, SEL selector, IMP replacement, IMP *original,
    const char *returnType, NSArray<NSString *> *arguments) {
    if (!cls || *original) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != arguments.count + 2 ||
        !PITypeMatches(signature.methodReturnType, returnType)) return NO;
    for (NSUInteger index = 0; index < arguments.count; index++) {
        if (!PITypeMatches([signature getArgumentTypeAtIndex:index+2], arguments[index].UTF8String)) return NO;
    }
    MSHookMessageEx(cls, selector, replacement, original);
    return *original != NULL;
}
