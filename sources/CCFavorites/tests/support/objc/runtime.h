// Minimal host-only Objective-C runtime declarations for the regression test.
// The tweak itself uses Apple's real SDK headers; this directory is never in
// the tweak's include path or package.
#ifndef BT_TEST_OBJC_RUNTIME_H
#define BT_TEST_OBJC_RUNTIME_H

typedef struct BTTestClass *Class;
typedef struct BTTestObject *id;

Class objc_getClass(const char *name);
Class object_getClass(id object);
Class class_getSuperclass(Class cls);

#endif
