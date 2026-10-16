#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// Only call private methods after checking their actual runtime ABI.
static inline const char *YSUnqualified(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) ++type;
    return type;
}

static inline BOOL YSMatches(Class cls, SEL sel, char result, unsigned arguments,
                             char argumentType) {
    Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!method || method_getNumberOfArguments(method) != arguments) return NO;
    char type[64] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (*YSUnqualified(type) != result) return NO;
    if (arguments > 2 && argumentType) {
        method_getArgumentType(method, 2, type, sizeof(type));
        const char actual = *YSUnqualified(type);
        if (argumentType == 'B') return actual == 'B' || actual == 'c';
        return actual == argumentType;
    }
    return YES;
}

static inline id YSObject(id object, SEL selector) {
    if (!object || !YSMatches(object_getClass(object), selector, '@', 2, 0)) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static inline BOOL YSInteger(id object, SEL selector, long long *value) {
    Method method = object ? class_getInstanceMethod(object_getClass(object), selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char type[64] = {0};
    method_getReturnType(method, type, sizeof(type));
    switch (*YSUnqualified(type)) {
        case 'i': *value = ((int (*)(id, SEL))objc_msgSend)(object, selector); return YES;
        case 'I': *value = ((unsigned (*)(id, SEL))objc_msgSend)(object, selector); return YES;
        case 'q': *value = ((long long (*)(id, SEL))objc_msgSend)(object, selector); return YES;
        case 'Q': *value = (long long)((unsigned long long (*)(id, SEL))objc_msgSend)(object, selector); return YES;
        default: return NO;
    }
}

static inline BOOL YSVoid(id object, SEL selector) {
    if (!object || !YSMatches(object_getClass(object), selector, 'v', 2, 0)) return NO;
    ((void (*)(id, SEL))objc_msgSend)(object, selector);
    return YES;
}

// One small, local, bounded log. Never records video IDs, titles, URLs or accounts.
static void YSLog(NSString *component, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
static void YSLog(NSString *component, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("local.ytshorts.log", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        @autoreleasepool {
            NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
            if (!documents) return;
            NSString *directory = [documents stringByAppendingPathComponent:@"YTShortsAddons"];
            NSFileManager *fm = NSFileManager.defaultManager;
            [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
            NSString *path = [directory stringByAppendingPathComponent:[component stringByAppendingPathExtension:@"log"]];
            NSData *data = [[NSString stringWithFormat:@"%@ %@\n", NSDate.date, message] dataUsingEncoding:NSUTF8StringEncoding];
            unsigned long long size = [[fm attributesOfItemAtPath:path error:NULL] fileSize];
            if (![fm fileExistsAtPath:path] || size + data.length > 65536) {
                [data writeToFile:path atomically:YES];
            } else {
                NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
                @try { [file seekToEndOfFile]; [file writeData:data]; }
                @catch (__unused NSException *exception) {}
                @finally { [file closeFile]; }
            }
        }
    });
}

static inline BOOL YSIsYouTube(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}
