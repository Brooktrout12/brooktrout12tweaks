#ifndef JBBW_CORE_H
#define JBBW_CORE_H
#include "platform.h"
#define MAX_PROCESSES 4096
#define MAX_TOTALS 2048
#define NAME_LEN 128
#define PATH_LEN 1024
#define MAX_FILES 4096
#define MAX_PACKAGES 4096
#define REPORT_LIMIT (32L*1024L*1024L)
#define MAX_SESSION_SAMPLES 1024

typedef struct {
    uint8_t uuid[16];
    uint64_t user_ns, system_ns, idle_wakeups, interrupt_wakeups;
    uint64_t pageins, wired_size, resident_size, footprint;
    uint64_t start_abs, exit_abs;
    uint64_t child_user_ns, child_system_ns, child_idle_wakeups;
    uint64_t child_interrupt_wakeups, child_pageins, child_elapsed_abs;
    uint64_t read_bytes, written_bytes;
} RUsageV2;
_Static_assert(sizeof(RUsageV2)==160, "Darwin rusage_info_v2 layout");
_Static_assert(offsetof(RUsageV2,start_abs)==80, "process start offset");
_Static_assert(offsetof(RUsageV2,read_bytes)==144, "disk IO offset");

typedef struct { int pid; RUsageV2 r; char name[NAME_LEN]; char path[PATH_LEN]; } Process;
typedef struct {
    int valid; uint64_t cpu_ns,idle,interrupts,read_bytes,written_bytes;
} Delta;
typedef struct {
    char name[NAME_LEN], path[PATH_LEN];
    uint64_t cpu_ns,idle,interrupts,read_bytes,written_bytes;
    unsigned intervals,identities;
} Total;
uint64_t ticks_to_nanoseconds(uint64_t ticks,uint32_t numer,uint32_t denom);
void copystr(char *dst,size_t cap,const char *src);
void cleantext(char *s);
Delta counter_delta(const Process *old,const Process *cur);
int deadline_reached(time_t now,time_t start,time_t deadline);
int canonical_path(const char *src,const char *jbroot,char *out,size_t cap);
int append_total(Total *totals,int *count,const Process *p,Delta d,int newly_seen);
const char *base_name(const char *s);
int endswith(const char *s,const char *end);
#endif
