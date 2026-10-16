#include "ui_refresh.h"
/* PSListController is a private class. A declaration in a community header is
 * not a runtime guarantee: the SE crash supplied for 2.1.0 shows that sending
 * -tableView directly fails on its iOS 17.6.1 Settings controller.
 * Never send that selector. Prefer the list controller's own refresh method,
 * then use checked fallbacks without forcing a view to load. */
static bool responds(id object, const char *name) {
    return object && ((bool (*)(id, SEL, SEL))objc_msgSend)(
        object, S("respondsToSelector:"), S(name));
}
static bool refresh_table(id table) {
    if (!iskind(table, "UITableView") || !responds(table, "reloadData"))
        return false;
    V0(table, "reloadData");
    return true;
}
int jbbw_refresh_list(id controller) {
    if (!controller) return 0;
    if (responds(controller, "reloadSpecifiers")) {
        V0(controller, "reloadSpecifiers");
        return 1;
    }
    if (responds(controller, "table") && refresh_table(M0(controller, "table")))
        return 2;
    if (responds(controller, "viewIfLoaded") &&
        refresh_table(M0(controller, "viewIfLoaded")))
        return 3;
    return 0;
}
