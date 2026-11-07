// Copyright (c) 2026 brooktrout12. MIT license.
#ifndef BT_RUNTIME_CLASS_MATCH_H
#define BT_RUNTIME_CLASS_MATCH_H

#include <objc/runtime.h>
#include <stdbool.h>

// objc_getClass resolves the exported name to a class identity. In contrast,
// class_getName returns demangled Swift names (e.g. ControlCenterUI.Foo), which
// cannot be compared to the _TtC... spellings in a framework's export list.
// Match identities through the superclass chain, including runtime subclasses.
// Do not cache misses: Control Center's classes may be loaded after this dylib.
static inline bool BTNamedKind(id object, const char *first, const char *second) {
    if (!object || !first) return false;
    Class firstClass = objc_getClass(first);
    Class secondClass = second ? objc_getClass(second) : (Class)0;
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        if (cls == firstClass || cls == secondClass) return true;
    }
    return false;
}

#endif
