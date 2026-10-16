#ifndef JBBW_DARWIN_H
#define JBBW_DARWIN_H
#include "core.h"
typedef struct {double pct;int external,charging,available;} Battery;
int platform_init(void);
int platform_check_register(void (*handler)(int));
uint64_t platform_check_nonce(void);
void platform_check_cancel(void);
time_t platform_wall(void);
void platform_sleep(unsigned);
void platform_wait(unsigned,const volatile int *,const volatile int *);
void platform_capabilities(FILE *f),platform_system(FILE *f);
const char *platform_jbroot(void);
double platform_continuous(void),platform_awake_clock(void);
uint64_t platform_boot_id(void);
int platform_processes(Process *,int,int *,int *,int *);
void platform_plist_record(FILE *,const char *,int);
void *platform_load_filter(const char *);
void platform_release_filter(void *);
int platform_filter_match(void *,const char *,const char *);
Battery platform_battery(FILE *);
void platform_display(FILE *),platform_assertions(FILE *);
#endif
