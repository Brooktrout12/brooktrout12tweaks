#include "../FGMenuScope.h"
#include <assert.h>
#include <stdio.h>

static void *otherThread(void *unused) {
    (void)unused;
    assert(!FGMenuActive());
    uintptr_t previous;
    assert(FGEnterMenu(&previous));
    assert(previous == 0 && FGMenuActive());
    FGLeaveMenu(previous);
    assert(!FGMenuActive());
    return NULL;
}

int main(void) {
    assert(pthread_key_create(&FGMenuDepthKey, NULL) == 0);
    assert(!FGMenuActive());
    uintptr_t first, second;
    assert(FGEnterMenu(&first));
    assert(first == 0 && FGMenuActive());
    assert(FGEnterMenu(&second));
    assert(second == 1 && FGMenuActive());
    FGLeaveMenu(second);
    assert(FGMenuActive());
    pthread_t thread;
    assert(pthread_create(&thread, NULL, otherThread, NULL) == 0);
    assert(pthread_join(thread, NULL) == 0);
    assert(FGMenuActive());
    FGLeaveMenu(first);
    assert(!FGMenuActive());
    for (unsigned i = 0; i < 100000; ++i) {
        assert(FGEnterMenu(&first));
        assert(FGMenuActive());
        FGLeaveMenu(first);
        assert(!FGMenuActive());
    }
    assert(pthread_setspecific(FGMenuDepthKey, (void *)UINTPTR_MAX) == 0);
    assert(!FGEnterMenu(&first));
    assert(first == UINTPTR_MAX);
    FGLeaveMenu(0);
    assert(!FGMenuActive());
    assert(pthread_key_delete(FGMenuDepthKey) == 0);
    puts("{\"result\":\"PASS\",\"nested_scope_restored\":true,\"other_thread_isolated\":true,\"repeat_cycles\":100000,\"overflow_rejected\":true,\"device_runtime_tested\":false}");
}
