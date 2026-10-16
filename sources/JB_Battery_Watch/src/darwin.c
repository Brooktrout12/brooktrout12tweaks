#include "darwin.h"
/* Runtime lookup makes unavailable device APIs an explicit report result rather
 * than a dyld launch failure. Every handle/value is released after its use. */
typedef const void *CFRef;
typedef unsigned long CFTypeID;
static struct {
    void *cf,*io,*proc;
    void (*release)(CFRef);
    CFTypeID (*type)(CFRef),(*numberType)(void),(*boolType)(void),(*dictType)(void),(*stringType)(void),(*arrayType)(void);
    CFRef (*str)(CFRef,const char *,uint32_t);
    unsigned char (*strGet)(CFRef,char *,long,uint32_t);
    unsigned char (*numberGet)(CFRef,int,void *),(*boolGet)(CFRef);
    CFRef (*dictGet)(CFRef,const void *);
    long (*dictCount)(CFRef),(*arrayCount)(CFRef),(*dataLength)(CFRef);
    void (*dictKeysValues)(CFRef,const void **,const void **);
    CFRef (*arrayGet)(CFRef,long),(*dataCreate)(CFRef,const uint8_t *,long);
    const uint8_t *(*dataBytes)(CFRef);
    CFRef (*plistParse)(CFRef,CFRef,unsigned long,long *,CFRef *);
    CFRef (*plistData)(CFRef,CFRef,long,unsigned long,CFRef *);
    CFRef (*serviceMatching)(const char *);
    uint32_t (*serviceGet)(uint32_t,CFRef);
    int (*props)(uint32_t,CFRef *,CFRef,uint32_t),(*objectRelease)(uint32_t);
    int (*list)(void *,int),(*rusage)(int,int,void *),(*path)(int,void *,uint32_t),(*name)(int,void *,uint32_t);
    int (*assertions)(CFRef *);
    int (*notifyRegister)(const char *,int *),(*notifyGet)(int,uint64_t *),(*notifyCancel)(int);
} api;
static int cf_ok,proc_ok,io_ok;
static int display_token=-1,lock_token=-1;
static char actual_jbroot[PATH_LEN];
static int init_done;
static uint32_t time_numer=1,time_denom=1;
static uint64_t cpu_to_ns(uint64_t ticks) {
    /* proc_pid_rusage uses Mach absolute-time units, including on A13.
     * Avoid loss of precision and avoid a compiler 128-bit division helper. */
    return ticks_to_nanoseconds(ticks,time_numer,time_denom);
}
#define SYM(handle,field,name) do { *(void **)(&api.field)=dlsym(handle,name); } while(0)

int platform_init(void) {
    if(init_done) return proc_ok; init_done=1;
    int timebase_ok=0;
    struct jbbw_timebase timebase={1,1};
    if(!mach_timebase_info(&timebase) && timebase.numer && timebase.denom) {
        time_numer=timebase.numer;time_denom=timebase.denom;timebase_ok=1;
    }
    api.proc=dlopen("/usr/lib/libproc.dylib",RTLD_LAZY);
    if(!api.proc) api.proc=dlopen("/usr/lib/libSystem.B.dylib",RTLD_LAZY);
    if(api.proc) {
        SYM(api.proc,list,"proc_listallpids"); SYM(api.proc,rusage,"proc_pid_rusage");
        SYM(api.proc,path,"proc_pidpath"); SYM(api.proc,name,"proc_name");
        proc_ok=timebase_ok && api.list && api.rusage && api.path && api.name;
    }
    api.cf=dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",RTLD_LAZY);
    if(api.cf) {
        SYM(api.cf,release,"CFRelease");SYM(api.cf,type,"CFGetTypeID");
        SYM(api.cf,numberType,"CFNumberGetTypeID");SYM(api.cf,boolType,"CFBooleanGetTypeID");
        SYM(api.cf,dictType,"CFDictionaryGetTypeID");SYM(api.cf,stringType,"CFStringGetTypeID");SYM(api.cf,arrayType,"CFArrayGetTypeID");
        SYM(api.cf,str,"CFStringCreateWithCString");SYM(api.cf,strGet,"CFStringGetCString");
        SYM(api.cf,numberGet,"CFNumberGetValue");SYM(api.cf,boolGet,"CFBooleanGetValue");
        SYM(api.cf,dictGet,"CFDictionaryGetValue");SYM(api.cf,dictCount,"CFDictionaryGetCount");
        SYM(api.cf,dictKeysValues,"CFDictionaryGetKeysAndValues");
        SYM(api.cf,arrayCount,"CFArrayGetCount");SYM(api.cf,arrayGet,"CFArrayGetValueAtIndex");
        SYM(api.cf,dataCreate,"CFDataCreate");SYM(api.cf,dataLength,"CFDataGetLength");SYM(api.cf,dataBytes,"CFDataGetBytePtr");
        SYM(api.cf,plistParse,"CFPropertyListCreateWithData");SYM(api.cf,plistData,"CFPropertyListCreateData");
        cf_ok=api.release && api.type && api.numberType && api.boolType && api.dictType && api.stringType && api.arrayType &&
              api.str && api.strGet && api.numberGet && api.boolGet && api.dictGet && api.dictCount && api.dictKeysValues &&
              api.arrayCount && api.arrayGet && api.dataCreate && api.dataLength && api.dataBytes && api.plistParse && api.plistData;
    }
    api.io=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_LAZY);
    if(api.io) {
        SYM(api.io,serviceMatching,"IOServiceMatching");SYM(api.io,serviceGet,"IOServiceGetMatchingService");
        SYM(api.io,props,"IORegistryEntryCreateCFProperties");SYM(api.io,objectRelease,"IOObjectRelease");
        SYM(api.io,assertions,"IOPMCopyAssertionsByProcess");
        io_ok=cf_ok && api.serviceMatching && api.serviceGet && api.props && api.objectRelease;
    }
    void *notify=dlopen("/usr/lib/system/libsystem_notify.dylib",RTLD_LAZY);
    if(!notify) notify=dlopen("/usr/lib/libSystem.B.dylib",RTLD_LAZY);
    if(notify) {
        SYM(notify,notifyRegister,"notify_register_check");SYM(notify,notifyGet,"notify_get_state");SYM(notify,notifyCancel,"notify_cancel");
        if(api.notifyRegister && api.notifyGet && api.notifyCancel) {
            if(api.notifyRegister("com.apple.iokit.hid.displayStatus",&display_token)) display_token=-1;
            if(api.notifyRegister("com.apple.springboard.lockstate",&lock_token)) lock_token=-1;
        }
    }
    /* readlink avoids exporting the randomized preboot location in the report. */
    extern long readlink(const char *,char *,size_t);
    long n=readlink("/var/jb",actual_jbroot,sizeof(actual_jbroot)-1);
    if(n>0) {actual_jbroot[n]=0;
        if(!strncmp(actual_jbroot,"/private/var/",13)) memmove(actual_jbroot,actual_jbroot+8,(size_t)n-7);
    } else actual_jbroot[0]=0;
    return proc_ok;
}
void platform_capabilities(FILE *f) {
    fprintf(f,"CPU_TIMEBASE\tnumer=%u\tdenom=%u\trusage_cpu_fields_converted_from_Mach_ticks_to_ns=1\n",time_numer,time_denom);
    fprintf(f,"CAPABILITIES\tproc_rusage_v2=%s\tplist_decoder=%s\tbattery_IOKit=%s\tassertions_API=%s\teuid=%d\n",
      proc_ok?"present":"UNAVAILABLE",cf_ok?"present":"UNAVAILABLE",io_ok?"present":"UNAVAILABLE",
      api.assertions?"present,access_unverified":"UNAVAILABLE",geteuid());
}
void platform_system(FILE *f) {
    const char *keys[]={"hw.machine","kern.osrelease","kern.osversion","kern.osproductversion",0};
    for(int i=0;keys[i];i++) {
        char value[256]={0};size_t n=sizeof(value)-1;
        if(!sysctlbyname(keys[i],value,&n,0,0)) {cleantext(value);fprintf(f,"SYSTEM\t%s\t%s\n",keys[i],value);}
    }
    int cpus=0;size_t n=sizeof(cpus);
    if(!sysctlbyname("hw.ncpu",&cpus,&n,0,0)) fprintf(f,"SYSTEM\thw.ncpu\t%d\n",cpus);
    fprintf(f,"SYSTEM\tbuild_target\tiOS arm64 standalone executable; minimum OS 15.0; rootless /var/jb\n");
}
const char *platform_jbroot(void) {return actual_jbroot;}
static double ticks_seconds(uint64_t t) {
    static double scale=0;
    if(!scale) {struct jbbw_timebase b={1,1};mach_timebase_info(&b);scale=(double)b.numer/(double)b.denom/1e9;}
    return t*scale;
}
double platform_continuous(void) {return ticks_seconds(mach_continuous_time());}
double platform_awake_clock(void) {return ticks_seconds(mach_absolute_time());}
uint64_t platform_boot_id(void) {
    struct {long sec;int usec;} v={0};size_t n=sizeof(v);
    if(sysctlbyname("kern.boottime",&v,&n,0,0)) return 0;
    return (uint64_t)v.sec;
}
int platform_processes(Process *p,int cap,int *denied,int *gone,int *other) {
    *denied=*gone=*other=0;
    if(!proc_ok) return -1;
    int *ids=calloc((size_t)cap,sizeof(int));if(!ids) return -1;
    int count=api.list(ids,cap*(int)sizeof(int));
    if(count<0) {free(ids);return -1;}
    if(count>cap) count=cap;
    int n=0;
    for(int i=0;i<count;i++) {
        if(ids[i]<=0) continue;
        Process s={0};s.pid=ids[i];
        if(api.rusage(s.pid,2,&s.r)) {
            int e=errno;if(e==1 || e==13) (*denied)++;else if(e==3) (*gone)++;else (*other)++;
            continue;
        }
        s.r.user_ns=cpu_to_ns(s.r.user_ns);
        s.r.system_ns=cpu_to_ns(s.r.system_ns);
        s.r.child_user_ns=cpu_to_ns(s.r.child_user_ns);
        s.r.child_system_ns=cpu_to_ns(s.r.child_system_ns);
        char path[4096]={0};
        if(api.path(s.pid,path,sizeof(path))>0) canonical_path(path,actual_jbroot,s.path,sizeof(s.path));
        api.name(s.pid,s.name,sizeof(s.name)); s.name[sizeof(s.name)-1]=0;
        if(!s.name[0]) copystr(s.name,sizeof(s.name),base_name(s.path));
        if(!s.name[0]) copystr(s.name,sizeof(s.name),"unknown");
        if(!s.path[0]) snprintf(s.path,sizeof(s.path),"[unavailable]/%s",s.name);
        cleantext(s.name);cleantext(s.path);p[n++]=s;
    }
    free(ids);return n;
}
static CFRef dict_value(CFRef d,const char *name) {
    if(!d || !cf_ok || api.type(d)!=api.dictType()) return 0;
    CFRef k=api.str(0,name,0x08000100);if(!k) return 0;
    CFRef v=api.dictGet(d,k);api.release(k);return v;
}
static int number_value(CFRef v,int64_t *n) {
    if(!v) return 0;
    if(api.type(v)==api.numberType()) return api.numberGet(v,4,n); /* kCFNumberSInt64Type */
    if(api.type(v)==api.boolType()) {*n=api.boolGet(v)?1:0;return 1;}return 0;
}
static int number_key(CFRef d,const char *key,int64_t *v) {return number_value(dict_value(d,key),v);}
static CFRef load_plist(const char *path) {
    if(!cf_ok) return 0;
    FILE *f=fopen(path,"rb");if(!f) return 0;
    if(fseek(f,0,SEEK_END)) {fclose(f);return 0;}
    long len=ftell(f);if(len<=0 || len>1024*1024) {fclose(f);return 0;}fseek(f,0,SEEK_SET);
    uint8_t *b=malloc((size_t)len);if(!b) {fclose(f);return 0;}
    size_t n=fread(b,1,(size_t)len,f);fclose(f);
    CFRef result=0;
    if(n==(size_t)len) {CFRef data=api.dataCreate(0,b,len);if(data) {result=api.plistParse(0,data,0,0,0);api.release(data);}}
    free(b);return result;
}
static void scalar(FILE *f,CFRef v) {
    int64_t n;
    if(!v) {fputs("UNAVAILABLE",f);return;}
    if(number_value(v,&n)) {fprintf(f,"%lld",(long long)n);return;}
    if(api.type(v)==api.stringType()) {char s[2048]={0};if(api.strGet(v,s,sizeof(s),0x08000100)) {cleantext(s);fputs(s,f);return;}}
    fputs("[non-scalar]",f);
}
void platform_plist_record(FILE *f,const char *path,int filter) {
    CFRef p=load_plist(path);
    if(!p) {fputs("PLIST_UNREADABLE_OR_UNSUPPORTED\n",f);return;}
    if(filter) {
        CFRef v=dict_value(p,"Filter");
        if(v) {
            CFRef data=api.plistData(0,v,100,0,0); /* XML format; no user preferences. */
            if(data) {long n=api.dataLength(data);
                if(n>0 && n<=65536) fwrite(api.dataBytes(data),1,(size_t)n,f);
                else fputs("FILTER_TOO_LARGE\n",f);
                api.release(data);
            } else fputs("FILTER_SERIALIZATION_FAILED\n",f);
        } else fputs("NO_FILTER_KEY\n",f);
    } else {
        fputs("Label=",f);scalar(f,dict_value(p,"Label"));
        CFRef prog=dict_value(p,"Program");
        if(!prog) {CFRef args=dict_value(p,"ProgramArguments");
            if(args && api.type(args)==api.arrayType() && api.arrayCount(args)>0) prog=api.arrayGet(args,0);}
        fputs("\tExecutable=",f);scalar(f,prog);
        fputs("\tRunAtLoad=",f);scalar(f,dict_value(p,"RunAtLoad"));
        fputs("\tKeepAlive=",f);scalar(f,dict_value(p,"KeepAlive"));
        fputc('\n',f);
    }
    api.release(p);
}
static int array_has(CFRef arr,const char *value) {
    if(!arr || !value || !value[0] || api.type(arr)!=api.arrayType()) return 0;
    long n=api.arrayCount(arr);if(n>1024) n=1024;
    for(long i=0;i<n;i++) {CFRef v=api.arrayGet(arr,i);char s[1024]={0};
        if(api.type(v)==api.stringType() && api.strGet(v,s,sizeof(s),0x08000100) && !strcmp(s,value)) return 1;}
    return 0;
}
/* Caller caches this retained filter once, not on each five-minute sample. */
void *platform_load_filter(const char *path) {return (void *)load_plist(path);}
void platform_release_filter(void *p) {if(p && cf_ok) api.release(p);}
int platform_filter_match(void *opaque,const char *name,const char *path) {
    CFRef f=dict_value(opaque,"Filter");if(!f) return 0;
    if(array_has(dict_value(f,"Executables"),name) || array_has(dict_value(f,"Executables"),base_name(path))) return 1;
    if((!strcmp(name,"SpringBoard") || !strcmp(base_name(path),"SpringBoard")) &&
        array_has(dict_value(f,"Bundles"),"com.apple.springboard")) return 2;
    /* Framework/Class filters cannot prove which process actually loaded a tweak. */
    return 0;
}
Battery platform_battery(FILE *f) {
    Battery b={.pct=-1,.external=-1,.charging=-1,.available=0};
    if(!io_ok) {fputs("BATTERY\tUNAVAILABLE: IOKit/CF symbols not available\n",f);return b;}
    const char *classes[]={"AppleSmartBattery","IOPMPowerSource",0};
    CFRef props=0;const char *used="";
    for(int i=0;classes[i];i++) {
        CFRef match=api.serviceMatching(classes[i]);if(!match) continue;
        uint32_t s=api.serviceGet(0,match); /* consumes matching dictionary */
        if(!s) continue;
        int e=api.props(s,&props,0,0);api.objectRelease(s);
        if(!e && props) {used=classes[i];break;}if(props) {api.release(props);props=0;}
    }
    if(!props) {fputs("BATTERY\tUNAVAILABLE: registry access failed or no power-source service\n",f);return b;}
    const char *keys[]={"CurrentCapacity","MaxCapacity","AppleRawCurrentCapacity","AppleRawMaxCapacity", "DesignCapacity",
                       "Voltage","Amperage","InstantAmperage","Temperature","CycleCount","ExternalConnected","IsCharging",0};
    fprintf(f,"BATTERY\tsource=%s",used);
    for(int i=0;keys[i];i++) {int64_t n;if(number_key(props,keys[i],&n)) fprintf(f,"\t%s=%lld",keys[i],(long long)n);}
    int64_t current=0,max=0,v;
    if(number_key(props,"CurrentCapacity",&current) && number_key(props,"MaxCapacity",&max) && max>0 && current>=0 && current<=max) {
        b.pct=100.0*(double)current/(double)max;b.available=1;
    }
    if(number_key(props,"ExternalConnected",&v)) b.external=(v!=0);
    if(number_key(props,"IsCharging",&v)) b.charging=(v!=0);
    fprintf(f,"\tcalculated_pct=%.3f\tnegative_pct_means_unavailable=1\n",b.pct);api.release(props);return b;
}
void platform_display(FILE *f) {
    uint64_t v=0;
    fputs("DISPLAY_HINT\t",f);
    if(display_token>=0 && !api.notifyGet(display_token,&v)) fprintf(f,"displayStatus_raw=%llu",(unsigned long long)v);else fputs("displayStatus_raw=UNAVAILABLE",f);
    if(lock_token>=0 && !api.notifyGet(lock_token,&v)) fprintf(f,"\tlockstate_raw=%llu",(unsigned long long)v);else fputs("\tlockstate_raw=UNAVAILABLE",f);
    fputs("\tprivate_notifications_not_proof_of_screen_off_entire_interval=1\n",f);
}
void platform_assertions(FILE *f) {
    if(!cf_ok || !api.assertions) {fputs("ASSERTIONS\tUNAVAILABLE_ON_THIS_BUILD\n",f);return;}
    CFRef dict=0;int e=api.assertions(&dict);
    if(e || !dict || api.type(dict)!=api.dictType()) {fprintf(f,"ASSERTIONS\tUNAVAILABLE_OR_DENIED\tcode=%d\n",e);if(dict) api.release(dict);return;}
    long n=api.dictCount(dict);if(n<0 || n>4096) {api.release(dict);return;}
    const void **keys=calloc((size_t)n+1,sizeof(void *)),**values=calloc((size_t)n+1,sizeof(void *));
    if(!keys || !values) {free(keys);free(values);api.release(dict);return;}
    api.dictKeysValues(dict,keys,values);
    fprintf(f,"ASSERTIONS\tprocess_entries=%ld\tnames_and_descriptions_omitted=1\n",n);
    for(long i=0;i<n;i++) {
        if(api.type(values[i])!=api.arrayType()) continue;
        long m=api.arrayCount(values[i]);if(m>1024) m=1024;
        for(long j=0;j<m;j++) {
            CFRef a=api.arrayGet(values[i],j);
            fputs("ASSERTION\tpid=",f);scalar(f,keys[i]);fputs("\ttype=",f);scalar(f,dict_value(a,"AssertionType"));
            fputs("\tlevel=",f);scalar(f,dict_value(a,"AssertionLevel"));fputc('\n',f);
        }
    }
    free(keys);free(values);api.release(dict);
}
time_t platform_wall(void) {return time(0);}
void platform_sleep(unsigned seconds) {
    struct timespec t={(long)seconds,0};
    /* No assertion is held. A suspend may delay this timer; that gap is logged. */
    nanosleep(&t,0);
}

/* Signal delivery, not a periodic poller. Only an explicit Settings check wakes
 * the normal sleep early. No extra resident worker or keep-awake assertion. */
static int check_token=-1;
static int (*check_get_state)(int,uint64_t *);
static int (*check_cancel_token)(int);
int platform_check_register(void (*handler)(int)) {
    void *lib=dlopen("/usr/lib/system/libsystem_notify.dylib",RTLD_LAZY);
    if(!lib)lib=dlopen("/usr/lib/libSystem.B.dylib",RTLD_LAZY);
    if(!lib)return 0;
    int (*reg)(const char *,int,int *)=0;
    *(void **)(&reg)=dlsym(lib,"notify_register_signal");
    *(void **)(&check_get_state)=dlsym(lib,"notify_get_state");
    *(void **)(&check_cancel_token)=dlsym(lib,"notify_cancel");
    if(!reg || !check_get_state || !check_cancel_token)return 0;
    if(signal(SIGUSR1,handler)==(void (*)(int))-1)return 0;
    if(reg("com.chatgpt.jbbatterywatch.check",SIGUSR1,&check_token)) {check_token=-1;return 0;}
    return 1;
}
uint64_t platform_check_nonce(void) {
    uint64_t value=0;
    if(check_token<0 || !check_get_state || check_get_state(check_token,&value))return 0;
    return value;
}
void platform_check_cancel(void) {
    if(check_token>=0 && check_cancel_token)check_cancel_token(check_token);
    check_token=-1;
}

void platform_wait(unsigned seconds,const volatile int *stop,const volatile int *request) {
    /* Darwin sigset_t is a 32-bit mask. Block before inspecting flags, and use
     * pselect's atomic mask change to avoid losing a signal just before sleep. */
    extern int sigprocmask(int,const uint32_t *,uint32_t *);
    extern int pselect(int,void *,void *,void *,const struct timespec *,const uint32_t *);
    uint32_t mask=(1U<<(SIGUSR1-1))|(1U<<(SIGTERM-1))|(1U<<(SIGINT-1))|(1U<<(SIGHUP-1)),old=0;
    if(sigprocmask(1,&mask,&old)) {if(!*stop && !*request)platform_sleep(seconds);return;}
    if(!*stop && !*request){struct timespec t={(long)seconds,0};pselect(0,0,0,0,&t,&old);}
    sigprocmask(3,&old,0);
}
