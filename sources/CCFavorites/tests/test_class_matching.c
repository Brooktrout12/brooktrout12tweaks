// Exercise the production ownership predicate with a small runtime fixture.
// In particular, expose demangled names while resolving mangled lookup aliases.
#include "../BTRuntimeClassMatch.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

struct BTTestClass {
    const char *exportedName;
    const char *displayName;
    Class superclass;
    bool loaded;
};
struct BTTestObject { Class cls; };

static struct BTTestClass classes[] = {
    {"NSObject", "NSObject", NULL, true},
    {"SBFolderView", "SBFolderView", &classes[0], true},
    {"SBRootFolderView", "SBRootFolderView", &classes[1], true},
    {"_TtC15ControlCenterUI18IconListFolderView", "ControlCenterUI.IconListFolderView", &classes[1], true},
    {"_TtC15ControlCenterUI22IconListRootFolderView", "ControlCenterUI.IconListRootFolderView", &classes[2], true},
    {"CCRuntimeSubclass", "CCRuntimeSubclass", &classes[4], true},
    {"SBFolderController", "SBFolderController", &classes[0], true},
    {"_TtC15ControlCenterUI24IconListFolderController", "ControlCenterUI.IconListFolderController", &classes[6], true},
    {"_TtC15ControlCenterUI28IconListRootFolderController", "ControlCenterUI.IconListRootFolderController", &classes[6], true},
    {"GalleryFolder", "ControlCenterUIServices.GalleryFolder", &classes[1], true},
    {"OtherModuleFolder", "OtherModule.IconListRootFolderView", &classes[2], true},
};

Class objc_getClass(const char *name) {
    if (!name) return NULL;
    for (size_t i = 0; i < sizeof(classes) / sizeof(classes[0]); ++i) {
        Class cls = &classes[i];
        if (cls->loaded && (!strcmp(name, cls->exportedName) || !strcmp(name, cls->displayName))) return cls;
    }
    return NULL;
}
Class object_getClass(id object) { return object ? object->cls : NULL; }
Class class_getSuperclass(Class cls) { return cls ? cls->superclass : NULL; }

// Reproduce the original bug to ensure the fixture actually exercises it.
static bool oldNameComparison(id object, const char *first, const char *second) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        if (!strcmp(cls->displayName, first) || (second && !strcmp(cls->displayName, second))) return true;
    }
    return false;
}

int main(void) {
    const char *folder = classes[3].exportedName, *root = classes[4].exportedName;
    const char *controller = classes[7].exportedName, *rootController = classes[8].exportedName;
    struct BTTestObject objects[sizeof(classes) / sizeof(classes[0])];
    for (size_t i = 0; i < sizeof(objects) / sizeof(objects[0]); ++i) objects[i].cls = &classes[i];

    assert(!oldNameComparison(&objects[3], folder, root));
    assert(!oldNameComparison(&objects[4], folder, root));
    assert(!oldNameComparison(&objects[7], controller, rootController));
    assert(!oldNameComparison(&objects[8], controller, rootController));
    assert(BTNamedKind(&objects[3], folder, root));
    assert(BTNamedKind(&objects[4], folder, root));
    assert(BTNamedKind(&objects[7], controller, rootController));
    assert(BTNamedKind(&objects[8], controller, rootController));
    assert(BTNamedKind(&objects[5], folder, root));
    assert(BTNamedKind(&objects[5], classes[4].displayName, NULL));
    assert(BTNamedKind(&objects[3], "SBFolderView", NULL));

    // Ordinary Home Screen and gallery views must not acquire CC restrictions.
    assert(!BTNamedKind(&objects[1], folder, root));
    assert(!BTNamedKind(&objects[2], folder, root));
    assert(!BTNamedKind(&objects[6], controller, rootController));
    assert(!BTNamedKind(&objects[9], folder, root));
    assert(!BTNamedKind(&objects[10], folder, root));
    assert(!BTNamedKind(NULL, folder, root));
    assert(!BTNamedKind(&objects[0], NULL, root));
    assert(!BTNamedKind(&objects[0], "MissingClass", NULL));

    // A failed pre-load lookup must not poison subsequent matching.
    classes[4].loaded = false;
    assert(!BTNamedKind(&objects[4], folder, root));
    classes[4].loaded = true;
    assert(BTNamedKind(&objects[4], folder, root));
    assert(BTNamedKind(&objects[4], "MissingClass", root));

    puts("{\"result\":\"PASS\",\"regression\":\"Swift class ownership\",\"original_bug_reproduced\":true,\"scope_negatives_passed\":true,\"lazy_load_retry_passed\":true,\"device_runtime_tested\":false}");
    return 0;
}
