#include "../src/darwin.h"
static void (*mock_check_handler)(int);
static double elapsed=0;static int inited=0,steps=0;
static void initclock(void){if(!inited){const char *s=getenv("MOCK_START_SECONDS");elapsed=s?strtod(s,0):0;inited=1;}}
int platform_init(void){initclock();return !getenv("MOCK_API_FAIL");}
time_t platform_wall(void){initclock();return 1800000000+(time_t)elapsed;}
void platform_sleep(unsigned n){elapsed+=n;steps++;if(getenv("MOCK_CHECK") && steps==1 && mock_check_handler)mock_check_handler(SIGUSR1);if(getenv("MOCK_DELAY"))elapsed+=900;
    const char *pause=getenv("MOCK_PAUSE_STEP");if(pause&&steps>=atoi(pause))raise(SIGTERM);
    if(getenv("MOCK_REAL_SLEEP"))sleep(1);
}
double platform_continuous(void){initclock();return 100000+elapsed;}
double platform_awake_clock(void){initclock();return 90000+elapsed*0.05;}
uint64_t platform_boot_id(void){return getenv("MOCK_REBOOT")?1235:1234;}
const char *platform_jbroot(void){return "/private/preboot/test/jb";}
void platform_capabilities(FILE *f){fputs("CAPABILITIES\tHOST_SIMULATION_NOT_DEVICE_TEST\n",f);}
void platform_system(FILE *f){fputs("SYSTEM\tMOCK\tNOT_A_REAL_IPHONE_REPORT\n",f);}
int platform_processes(Process *p,int cap,int *denied,int *gone,int *other){
    (void)cap;*denied=getenv("MOCK_DENIED")?100:0;*gone=*other=0;
    int n=getenv("MOCK_DENIED")?1:3;const char *names[]={"launchd","SpringBoard","test-daemon"};
    const char *paths[]={"/sbin/launchd","/System/Library/CoreServices/SpringBoard.app/SpringBoard","/var/jb/usr/libexec/test-daemon"};
    for(int i=0;i<n;i++){memset(&p[i],0,sizeof(p[i]));p[i].pid=i+1;p[i].r.start_abs=i+100;
        p[i].r.user_ns=(uint64_t)(elapsed*1000000*(i+1));p[i].r.system_ns=(uint64_t)elapsed*500000;
        p[i].r.idle_wakeups=(uint64_t)elapsed*(i+1);p[i].r.interrupt_wakeups=(uint64_t)elapsed;
        copystr(p[i].name,NAME_LEN,names[i]);copystr(p[i].path,PATH_LEN,paths[i]);}
    return n;
}
Battery platform_battery(FILE *f){Battery b={.pct=100-elapsed/86400*30,.available=1,.external=0,.charging=0};
    if(getenv("MOCK_NO_BATTERY")){b.pct=-1;b.available=0;fputs("BATTERY\tUNAVAILABLE\n",f);}else fprintf(f,"BATTERY\tMOCK_pct=%.2f\n",b.pct);return b;}
void platform_display(FILE *f){fputs("DISPLAY_HINT\tMOCK_OFF\n",f);}
void platform_assertions(FILE *f){fputs("ASSERTIONS\tUNAVAILABLE\n",f);}
void platform_plist_record(FILE *f,const char *p,int filter){fprintf(f,"PLIST_MOCK\t%s\t%d\n",p,filter);}
void *platform_load_filter(const char *p){return strdup(p);}
void platform_release_filter(void *p){free(p);}
int platform_filter_match(void *p,const char *name,const char *path){(void)p;(void)path;return !strcmp(name,"SpringBoard");}

int platform_check_register(void (*handler)(int)){mock_check_handler=handler;return !getenv("MOCK_NO_CHECK");}
uint64_t platform_check_nonce(void){return getenv("MOCK_CHECK")?1234567:0;}
void platform_check_cancel(void){}

void platform_wait(unsigned n,const volatile int *stop,const volatile int *request){if(!*stop&&! *request)platform_sleep(n);}
