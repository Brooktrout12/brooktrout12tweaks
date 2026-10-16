#ifndef JBBW_PLATFORM_H
#define JBBW_PLATFORM_H
/* Narrow Darwin ABI declarations, not an SDK. No private entitlement, task port,
 * code injection or kernel write is used. See SOURCES.md for interface references.
 * The portable core is also compiled against the Linux libc for unit tests. */
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>
#ifdef JBBW_HOST_TEST
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <signal.h>
#include <dlfcn.h>
#else
typedef struct JBBW_FILE FILE;
typedef struct JBBW_DIR DIR;
typedef long time_t;
typedef unsigned short mode_t;
struct timespec { long tv_sec; long tv_nsec; };
struct dirent { uint64_t d_ino, d_seekoff; uint16_t d_reclen, d_namlen; uint8_t d_type; char d_name[1024]; };
extern FILE *fopen(const char *, const char *);
extern int fclose(FILE *), fflush(FILE *), ferror(FILE *), fileno(FILE *);
extern size_t fread(void *, size_t, size_t, FILE *), fwrite(const void *, size_t, size_t, FILE *);
extern int fprintf(FILE *, const char *, ...) __attribute__((format(printf,2,3)));
extern int printf(const char *, ...) __attribute__((format(printf,1,2)));
extern int snprintf(char *, size_t, const char *, ...) __attribute__((format(printf,3,4)));
extern int fputs(const char *, FILE *), fputc(int, FILE *), fseek(FILE *, long, int);
extern char *fgets(char *, int, FILE *);
extern long ftell(FILE *);
extern int rename(const char *, const char *), remove(const char *);
extern void *malloc(size_t), *calloc(size_t, size_t), *realloc(void *, size_t);
extern void free(void *);
extern size_t strlen(const char *);
extern int strcmp(const char *,const char *), strncmp(const char *,const char *,size_t), memcmp(const void *,const void *,size_t);
extern char *strchr(const char *,int), *strrchr(const char *,int), *strstr(const char *,const char *), *strdup(const char *);
extern void *memmove(void *,const void *,size_t);
extern void *memcpy(void *,const void *,size_t), *memset(void *,int,size_t);
extern unsigned long long strtoull(const char *,char **,int);
extern long strtol(const char *,char **,int);
extern double strtod(const char *,char **);
extern void qsort(void *,size_t,size_t,int (*)(const void *,const void *));
extern time_t time(time_t *);
extern char *ctime(const time_t *);
extern int nanosleep(const struct timespec *,struct timespec *);
extern unsigned sleep(unsigned);
extern int mkdir(const char *,mode_t), chmod(const char *,mode_t), chown(const char *,unsigned,unsigned);
extern int getpid(void), geteuid(void), flock(int,int), access(const char *,int);
extern int * __error(void);
#define errno (*__error())
extern void (*signal(int,void (*)(int)))(int);
extern DIR *opendir(const char *);
extern struct dirent *readdir(DIR *);
extern int closedir(DIR *);
extern void *dlopen(const char *,int), *dlsym(void *,const char *);
extern int sysctlbyname(const char *,void *,size_t *,void *,size_t);
extern uint64_t mach_absolute_time(void), mach_continuous_time(void);
struct jbbw_timebase { uint32_t numer,denom; };
extern int mach_timebase_info(struct jbbw_timebase *);
#define SEEK_SET 0
#define SEEK_END 2
#define LOCK_EX 2
#define LOCK_NB 4
#define SIGUSR1 30
#define SIGTERM 15
#define SIGINT 2
#define SIGHUP 1
#define RTLD_LAZY 1
#define F_OK 0
#endif
#define JBBW_VERSION "2.1.0"
#define NS_PER_SEC 1000000000ULL
#endif
