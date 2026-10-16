/* Exercise the actual production refresh helper with a minimal host-only
 * Objective-C dispatch shim. This is not Apple's runtime or UIKit. */
#include "../prefs/ui_refresh.h"
#include <assert.h>
#include <setjmp.h>

#if !defined(__x86_64__)
#error "The host dispatch shim is for Linux x86_64 only."
#endif

typedef struct Mock {
    bool list_method, table_method, view_method, table_kind, reload_method;
    struct Mock *table_result, *view_result;
    unsigned list_calls, table_calls, view_calls, reload_calls;
} Mock;
static Mock controller, table, other;
static const char table_class;
static unsigned checked, unknown_messages;
static const char *unknown_selector;
static bool catch_exception;
static jmp_buf exception_env;

SEL sel_registerName(const char *name) { return (SEL)name; }
Class objc_getClass(const char *name) {
    assert(!strcmp(name, "UITableView"));
    return (Class)&table_class;
}
static bool supports(Mock *m, const char *name) {
    if (!strcmp(name, "respondsToSelector:") || !strcmp(name, "isKindOfClass:")) return true;
    if (!strcmp(name, "reloadSpecifiers")) return m->list_method;
    if (!strcmp(name, "table")) return m->table_method;
    if (!strcmp(name, "viewIfLoaded")) return m->view_method;
    if (!strcmp(name, "reloadData")) return m->reload_method;
    /* Crucially, tableView is NOT implemented, just like the crash target. */
    return false;
}
static bool mock_responds(id o, SEL cmd, SEL name) {
    (void)cmd;
    return supports(o, (const char *)name);
}
static bool mock_is_kind(id o, SEL cmd, Class cls) {
    (void)cmd;
    return cls == (Class)&table_class && ((Mock *)o)->table_kind;
}
static void mock_reload_list(id o, SEL cmd) {
    (void)cmd;
    ((Mock *)o)->list_calls++;
}
static void mock_reload_data(id o, SEL cmd) {
    (void)cmd;
    ((Mock *)o)->reload_calls++;
}
static id mock_get_table(id o, SEL cmd) {
    (void)cmd;
    Mock *m=o;
    m->table_calls++;
    return m->table_result;
}
static id mock_get_view(id o, SEL cmd) {
    (void)cmd;
    Mock *m=o;
    m->view_calls++;
    return m->view_result;
}
IMP mock_lookup(id object, SEL cmd) {
    Mock *m=object;
    const char *name=cmd;
    if (!m || !supports(m,name)) {
        unknown_selector=name;
        unknown_messages++;
        if (catch_exception) longjmp(exception_env,1);
        fprintf(stderr,"Unexpected unsupported selector: %s\n",name);
        abort();
    }
    if (!strcmp(name,"respondsToSelector:")) return (IMP)mock_responds;
    if (!strcmp(name,"isKindOfClass:")) return (IMP)mock_is_kind;
    if (!strcmp(name,"reloadSpecifiers")) return (IMP)mock_reload_list;
    if (!strcmp(name,"reloadData")) return (IMP)mock_reload_data;
    if (!strcmp(name,"table")) return (IMP)mock_get_table;
    if (!strcmp(name,"viewIfLoaded")) return (IMP)mock_get_view;
    abort();
}
/* Preserve the receiver, selector and one method argument, resolve the typed
 * target, then tail-call it. These are the only signatures used by this helper.
 * Unlike an untyped C varargs substitute, the bool/id/void returns use their real
 * ABI. This shim tests branch/selector choices, not Apple's Objective-C runtime. */
__asm__(".text\n"
        ".globl objc_msgSend\n"
        ".type objc_msgSend,@function\n"
        "objc_msgSend:\n"
        "push %rdx\n"
        "push %rsi\n"
        "push %rdi\n"
        "call mock_lookup\n"
        "pop %rdi\n"
        "pop %rsi\n"
        "pop %rdx\n"
        "jmp *%rax\n"
        ".size objc_msgSend, .-objc_msgSend\n");

/* Exact faulty operation from v2.1.0's redraw(). Retained ONLY for regression. */
static void old_redraw(id self) {
    id t=M0(self,"tableView");
    if(t)V0(t,"reloadData");
}
static void reset(void) {
    controller=(Mock){0};
    table=(Mock){.table_kind=true,.reload_method=true};
    other=(Mock){0};
    unknown_messages=0;
    unknown_selector=0;
    catch_exception=false;
}
static void check(const char *name, bool ok) {
    assert(ok);
    printf("PASS: %s\n",name);
    checked++;
}
int main(void) {
    reset();controller.list_method=true;catch_exception=true;
    if (!setjmp(exception_env)) {
        old_redraw(&controller);
        assert(!"Old redraw should have sent the unsupported tableView selector");
    }
    catch_exception=false;
    check("2.1.0 reproduces missing-tableView failure in dispatch model",
          unknown_messages==1 && !strcmp(unknown_selector,"tableView"));

    reset();controller.list_method=true;
    check("fixed helper refreshes without any tableView method",
          jbbw_refresh_list(&controller)==1 && controller.list_calls==1 && !unknown_messages);
    reset();controller.list_method=true;controller.table_method=true;controller.view_method=true;
    controller.table_result=&table;controller.view_result=&table;
    check("list-controller refresh is preferred; no getters queried",
          jbbw_refresh_list(&controller)==1 && !controller.table_calls && !controller.view_calls && !table.reload_calls);
    reset();controller.table_method=true;controller.table_result=&table;
    check("verified table getter fallback refreshes only a table",
          jbbw_refresh_list(&controller)==2 && table.reload_calls==1 && !unknown_messages);
    reset();controller.view_method=true;controller.view_result=&table;
    check("already-loaded public table view fallback works",
          jbbw_refresh_list(&controller)==3 && table.reload_calls==1 && !unknown_messages);
    reset();
    check("nil controller is a safe unsupported result",jbbw_refresh_list(0)==0 && !unknown_messages);
    reset();
    check("absent optional selectors are never sent",jbbw_refresh_list(&controller)==0 && !unknown_messages);
    reset();controller.table_method=true;controller.view_method=true;controller.view_result=&table;
    check("nil table getter falls back to the loaded view",
          jbbw_refresh_list(&controller)==3 && controller.table_calls==1 && table.reload_calls==1);
    reset();controller.table_method=true;controller.table_result=&other;controller.view_method=true;controller.view_result=&table;
    check("non-table getter is rejected before public-view fallback",
          jbbw_refresh_list(&controller)==3 && !other.reload_calls && !unknown_messages);
    reset();controller.table_method=true;controller.table_result=&other;
    check("non-table object does not receive reloadData",jbbw_refresh_list(&controller)==0 && !unknown_messages);
    reset();controller.table_method=true;controller.table_result=&table;table.reload_method=false;
    check("table with missing reloadData is handled without dispatching it",
          jbbw_refresh_list(&controller)==0 && !unknown_messages);
    reset();controller.view_method=true;
    check("nil viewIfLoaded does not force view loading",jbbw_refresh_list(&controller)==0 && !unknown_messages);
    reset();controller.view_method=true;controller.view_result=&other;
    check("non-table root view is safely rejected",jbbw_refresh_list(&controller)==0 && !unknown_messages);
    reset();controller.list_method=true;
    for(unsigned i=0;i<10000;i++)assert(jbbw_refresh_list(&controller)==1);
    check("repeated refreshes do not fall through to unsupported selectors",
          controller.list_calls==10000 && !unknown_messages);
    printf("\n%u refresh checks passed. Host dispatch model only; no iPhone/UI execution.\n",checked);
    return 0;
}
