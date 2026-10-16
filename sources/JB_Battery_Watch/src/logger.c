#include "inventory.h"
#ifndef JBBW_REPORT_DIR
#define JBBW_REPORT_DIR "/var/mobile/Documents/JBBatteryReport-v2"
#endif
#ifndef JBBW_STATE_DIR
#define JBBW_STATE_DIR "/var/jb/var/lib/jb-battery-watch"
#endif
#define REPORT JBBW_REPORT_DIR "/JB-Battery-Report.txt"
#define STATUS JBBW_REPORT_DIR "/STATUS.txt"
#define HEALTH JBBW_REPORT_DIR "/HEALTH.plist"
#define STATE JBBW_STATE_DIR "/session.bin"
#define DONE JBBW_STATE_DIR "/completed"
#define LOCK JBBW_STATE_DIR "/collector.lock"
#define INTERVAL 300
#define DURATION 86400
static volatile int stopping,check_requested;
static int check_supported,report_write_ok,state_write_ok;
static uint64_t last_check_nonce;
static long last_report_bytes;
static void check_handler(int signal_number) {(void)signal_number;check_requested=1;}
static void stop_handler(int s) {(void)s;stopping=1;}
typedef struct {
    char magic[8];uint32_t version,samples,runs,charged_samples;
    int64_t start,deadline,last;uint64_t boot;
    double start_cont,first_pct,last_pct;
    uint32_t battery_samples,reserved;
} State;
static int save_state(State *s) {
    FILE *f=fopen(STATE ".tmp","wb");if(!f)return 0;
    int ok=fwrite(s,sizeof(*s),1,f)==1;if(fclose(f))ok=0;
    if(ok && !rename(STATE ".tmp",STATE)) {chmod(STATE,0600);return 1;}return 0;
}
static int load_state(State *s) {
    FILE *f=fopen(STATE,"rb");if(!f)return 0;
    int ok=fread(s,sizeof(*s),1,f)==1;fclose(f);
    return ok && !memcmp(s->magic,"JBBW20\0",8) && s->version==2 && s->start>0 &&
           s->deadline==s->start+DURATION && s->samples<=MAX_SESSION_SAMPLES && s->runs<=MAX_SESSION_SAMPLES;
}
static double remaining(const State *s,time_t now,double cont,uint64_t boot) {
    if(boot && s->boot==boot && cont>=s->start_cont && s->start_cont>=0) return DURATION-(cont-s->start_cont);
    return (double)(s->deadline-now);
}
static void xml_text(FILE *f,const char *s) {
    while(*s){switch(*s){case '&':fputs("&amp;",f);break;case '<':fputs("&lt;",f);break;case '>':fputs("&gt;",f);break;case '"':fputs("&quot;",f);break;default:fputc(*s,f);break;}s++;}
}
static void health_string(FILE *f,const char *key,const char *value){fprintf(f,"<key>%s</key><string>",key);xml_text(f,value);fputs("</string>\n",f);}
static void health_int(FILE *f,const char *key,int64_t v){fprintf(f,"<key>%s</key><integer>%lld</integer>\n",key,(long long)v);}
static void make_health(const State *s,const char *message,int process_count,int denied) {
    FILE *f=fopen(HEALTH ".tmp","w");if(!f){printf("HEALTH_WRITE_ERROR: could not create status file\n");return;}
    fputs("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>\n",f);
    char state[32]={0};unsigned i=0;while(message[i] && message[i]!=' ' && message[i]!=':' && i<sizeof(state)-1){state[i]=message[i];i++;}
    health_int(f,"Schema",1);health_string(f,"Version",JBBW_VERSION);health_string(f,"State",state);health_string(f,"Message",message);
    health_int(f,"PID",getpid());health_int(f,"SessionStart",s->start);health_int(f,"Deadline",s->deadline);health_int(f,"LastSample",s->last);
    health_int(f,"SampleCount",s->samples);health_int(f,"ProcessCount",process_count);health_int(f,"DeniedCount",denied);
    health_int(f,"ReportBytes",last_report_bytes);health_int(f,"BatterySamples",s->battery_samples);health_int(f,"ChargedSamples",s->charged_samples);
    health_int(f,"CheckSupported",check_supported);health_int(f,"LastCheckNonce",(int64_t)last_check_nonce);
    health_int(f,"ReportWriteOK",report_write_ok);health_int(f,"StateWriteOK",state_write_ok);
    fprintf(f,"<key>BatteryPercent</key><real>%.3f</real>\n<key>FirstBatteryPercent</key><real>%.3f</real>\n",s->last_pct,s->first_pct);
    fputs("</dict></plist>\n",f);int ok=!ferror(f);if(fclose(f))ok=0;
    if(ok && !chmod(HEALTH ".tmp",0640) && !chown(HEALTH ".tmp",0,501)) {
        if(rename(HEALTH ".tmp",HEALTH))printf("HEALTH_WRITE_ERROR: could not commit status file\n");
    } else printf("HEALTH_WRITE_ERROR: write or permissions failed\n");
}
static void make_status(const State *s,const char *message,int process_count,int denied,const Total *top) {
    make_health(s,message,process_count,denied);
    FILE *f=fopen(STATUS ".tmp","w");if(!f)return;
    time_t last=(time_t)s->last;
    fprintf(f,"JB Battery Watch %s\n%s\n\nSamples recorded: %u\nLast sample: %s",JBBW_VERSION,message,s->samples,ctime(&last));
    fprintf(f,"Readable processes in last sample: %d\nPermission-denied processes: %d\n",process_count,denied);
    if(s->last_pct>=0) fprintf(f,"Last battery reading: %.1f%%\n",s->last_pct);else fputs("Battery reading: UNAVAILABLE (see report)\n",f);
    if(top) fprintf(f,"Largest measured CPU total in this logger run: %s (%.3f CPU seconds)\nThis is a process, NOT a confirmed guilty tweak.\n",top->name,(double)top->cpu_ns/1e9);
    fputs("\nShare this one file, even before the test ends:\n" REPORT "\n\nNo manual compression is necessary.\n",f);
    int ok=!ferror(f);if(fclose(f))ok=0;
    if(ok && !chmod(STATUS ".tmp",0640) && !chown(STATUS ".tmp",0,501)) rename(STATUS ".tmp",STATUS);
}
static int compare_pid(const void *a,const void *b) {int x=((const Process *)a)->pid,y=((const Process *)b)->pid;return (x>y)-(x<y);}
static const Process *find_pid(const Process *list,int n,int pid) {
    int lo=0,hi=n;
    while(lo<hi) {int mid=lo+(hi-lo)/2;if(list[mid].pid<pid)lo=mid+1;else hi=mid;}
    return lo<n && list[lo].pid==pid?&list[lo]:0;
}
static int cpu_desc(const void *a,const void *b) {
    const Total *x=a,*y=b;return (x->cpu_ns<y->cpu_ns)-(x->cpu_ns>y->cpu_ns);
}
static int wakes_desc(const void *a,const void *b) {
    const Total *x=a,*y=b;return (x->idle<y->idle)-(x->idle>y->idle);
}
static void summary(FILE *f,Total *t,int n,unsigned run) {
    fprintf(f,"\n=== PROCESS RANKINGS, LOGGER RUN %u ONLY ===\n",run);
    fputs("Earlier runs remain in the raw report; their totals are not merged in this on-device summary.\nCPU and wakeups are separate indicators, NOT per-tweak energy attribution.\n",f);
    for(int mode=0;mode<2;mode++) {
        qsort(t,(size_t)n,sizeof(*t),mode?wakes_desc:cpu_desc);
        fprintf(f,"\nTOP_BY_%s\n",mode?"KERNEL_IDLE_WAKEUPS":"CPU_TIME");
        fputs("process\tcpu_seconds\tidle_wakeups\tinterrupt_wakeups\tread_bytes\twritten_bytes\tobserved_intervals\tpackage_owner\texecutable\n",f);
        for(int i=0;i<n && i<20;i++) {
            if(!(mode?t[i].idle:t[i].cpu_ns))continue;
            fprintf(f,"RANK\t%s\t%.6f\t%llu\t%llu\t%llu\t%llu\t%u\t%s\t%s\n",t[i].name,(double)t[i].cpu_ns/1e9,
             (unsigned long long)t[i].idle,(unsigned long long)t[i].interrupts,(unsigned long long)t[i].read_bytes,
             (unsigned long long)t[i].written_bytes,t[i].intervals,file_owner(t[i].path),t[i].path);
            if(!mode && i<8)report_candidates(f,&t[i]);
        }
    }
}
static void report_header(FILE *f) {
    fputs("JB BATTERY WATCH 2.1 - LOCAL DIAGNOSTIC REPORT\n",f);
    fputs("Target: iPhone SE (2020), iOS 17.6, Dopamine rootless. Actual device/build appear below.\n",f);
    fputs("READ THIS FIRST\nThis is an experimental passive process logger, not a proven per-tweak energy meter.\n"
          "Counter deltas cover processes present at consecutive samples; short-lived processes between samples can be missed.\n"
          "CPU columns convert cumulative proc_pid_rusage user/system Mach ticks to nanoseconds with mach_timebase_info. PID/start/UUID changes begin a new baseline.\n"
          "Kernel package-idle and interrupt wakeups are accounting counters, not a count of full-device sleep exits.\n"
          "A listed injection filter declares a possible target; it does not prove that dylib is loaded or causing drain.\n"
          "No hooks, stack sampling, task suspension, keep-awake assertions, network upload, tweak removal or settings changes.\n"
          "Radio/GPU work and brief assertions are not fully accounted for. Missing API data is marked unavailable.\n"
          "Sampling adds some unmeasured observer overhead; use the same logger for any later controlled comparison.\n"
          "Privacy: contains installed package/app/process names, executable paths, timestamps and whitelisted diagnostics.\n"
          "No message contents, app arguments, passwords, network names, device serials/UDIDs, preference dumps or crash reports collected. Executable paths may include app-container UUIDs.\n"
          "Battery/lock hints are snapshots, not proof of uninterrupted standby. Prefer an unplugged, screen-off test.\n"
          "Requested sampling: 300 s. Ends at first permitted sample at/after 24 h; does not force the phone awake.\n"
          "Report cap: 32 MiB (plus final sample/summary). This report is already shareable while recording.\n\n",f);
}
int main(int argc,char **argv) {
    if(argc>1 && !strcmp(argv[1],"--probe")) {
        FILE *f=fopen(JBBW_REPORT_DIR "/PROBE.txt","w");if(!f)return 20;
        int ok=platform_init();platform_capabilities(f);platform_system(f);
        Process *p=calloc(MAX_PROCESSES,sizeof(*p));int denied=0,gone=0,other=0;
        int n=p?platform_processes(p,MAX_PROCESSES,&denied,&gone,&other):-1;
        fprintf(f,"PROBE\treadable=%d\tdenied=%d\tgone=%d\tother=%d\n",n,denied,gone,other);
        platform_battery(f);free(p);fclose(f);chmod(JBBW_REPORT_DIR "/PROBE.txt",0640);chown(JBBW_REPORT_DIR "/PROBE.txt",0,501);
        return ok && n>1?0:21;
    }
    if(argc>1 && !strcmp(argv[1],"--version")) {printf("JB Battery Watch %s\n",JBBW_VERSION);return 0;}
    if(argc>1) return 22;
    if(geteuid()!=0) return 23;
    FILE *lock=fopen(LOCK,"a+");if(!lock)return 24;
    if(flock(fileno(lock),LOCK_EX|LOCK_NB)) {fclose(lock);return 0;} /* Kernel lock cannot become stale. */
    if(!access(DONE,F_OK)) {
        State completed={0};
        if(load_state(&completed)) {
            char message[512]="COMPLETE: Previously finished session; report preserved.";
            FILE *done=fopen(DONE,"r");if(done){if(!fgets(message,sizeof(message),done))copystr(message,sizeof(message),"COMPLETE: Previously finished session; report preserved.");fclose(done);}
            char *nl=strchr(message,'\n');if(nl)*nl=0;
            make_status(&completed,message,0,0,0);
        }
        fclose(lock);return 0;
    }
    signal(SIGTERM,stop_handler);signal(SIGINT,stop_handler);signal(SIGHUP,stop_handler);
    State s={0};int resumed=load_state(&s);
    if(!resumed && !access(STATE,F_OK)) {
        copystr(s.magic,8,"JBBW20");s.last=platform_wall();s.last_pct=-1;
        make_status(&s,"ERROR: Saved state is corrupt. No data was overwritten; reinstall this package to start a fresh test.",0,0,0);
        fclose(lock);return 0;
    }
    FILE *f=fopen(REPORT,"a");if(!f){fclose(lock);return 25;}
    chmod(REPORT,0640);chown(REPORT,0,501);
    if(!resumed) {
        report_header(f);memcpy(s.magic,"JBBW20\0",8);s.version=2;
        s.first_pct=s.last_pct=-1;s.start=platform_wall();s.deadline=s.start+DURATION;
        s.start_cont=platform_continuous();s.boot=platform_boot_id();
    }
    s.runs++;s.last=platform_wall();
    fprintf(f,"\nLOGGER_RUN\t%u\t%s\tepoch=%lld\n",s.runs,resumed?"RESUME_NEW_COUNTER_BASELINE":"START",(long long)s.last);
    if(!platform_init()) {fputs("FATAL\tRequired process APIs not available\n",f);make_status(&s,"ERROR: Process APIs unavailable. Share this report and PROBE.txt.",0,0,0);fclose(f);fclose(lock);return 0;}
    check_supported=platform_check_register(check_handler);
    fprintf(f,"LIVE_CHECK\tsupported=%d\tmethod=Darwin_notification_signal\tmanual_samples_explicitly_marked=1\n",check_supported);
    platform_capabilities(f);platform_system(f);inventory(f,1);
    Process *current=calloc(MAX_PROCESSES,sizeof(*current)),*prev=calloc(MAX_PROCESSES,sizeof(*prev));
    Total *totals=calloc(MAX_TOTALS,sizeof(*totals));
    int np=0,nt=0,last_n=0,last_denied=0;double last_cont=0,last_awake=0;
    const char *reason="COMPLETE: Requested 24-hour window ended.";
    if(!current || !prev || !totals) {reason="ERROR: Memory allocation failed.";goto finish;}
    for(;;) {
        uint64_t request_nonce=0;
        if(check_requested) {check_requested=0;request_nonce=platform_check_nonce();}
        time_t now=platform_wall();double cont=platform_continuous(),awake=platform_awake_clock();
        double dt=last_cont?cont-last_cont:0;int denied=0,gone=0,other=0;
        int n=platform_processes(current,MAX_PROCESSES,&denied,&gone,&other);
        last_n=n;last_denied=denied;s.last=now;s.samples++;
        fprintf(f,"\nSAMPLE\t%u\tepoch=%lld\tcontinuous_s=%.6f\tawake_clock_s=%.6f\tinterval_s=%.6f\treadable=%d\tdenied=%d\tgone=%d\tother_errors=%d\n",
          s.samples,(long long)now,cont,awake,dt,n,denied,gone,other);
        if(request_nonce)fprintf(f,"MANUAL_CHECK\tnonce=%llu\tuser_requested_extra_sample=1\n",(unsigned long long)request_nonce);
        if(last_cont && dt>0) fprintf(f,"CLOCK_DIFFERENCE\tcontinuous_minus_awake_delta_s=%.6f\tclock_hint_only=1\n",dt-(awake-last_awake));
        if(dt>INTERVAL*2) fputs("GAP\tSampling was delayed (sleep/scheduling). Counters may still cover surviving processes; no claim of full-time observation.\n",f);
        Battery b=platform_battery(f);platform_display(f);
        if(b.available) {if(s.first_pct<0)s.first_pct=b.pct;s.last_pct=b.pct;s.battery_samples++;}
        if(b.external==1 || b.charging==1) s.charged_samples++;
        if((s.samples-1)%6==0)platform_assertions(f);
        if(n<=1) {reason="ERROR: Insufficient process access; stopped rather than collecting a misleading 24-hour report.";break;}
        if(n>=MAX_PROCESSES)fputs("WARNING\tProcess list may be truncated at 4096 entries\n",f);
        qsort(current,(size_t)n,sizeof(*current),compare_pid);
        fputs("P_COLUMNS\tpid\tstart_abstime\tname\tuser_ns_total\tsystem_ns_total\tidle_total\tinterrupt_total\tread_bytes_total\twritten_bytes_total\tvalid_delta\tdelta_cpu_ns\tdelta_idle\tdelta_interrupts\tdelta_read_bytes\tdelta_written_bytes\tcpu_pct_one_core\texecutable\n",f);
        int new_count=0,valid_count=0;
        for(int i=0;i<n;i++) {
            const Process *old=find_pid(prev,np,current[i].pid);Delta d=counter_delta(old,&current[i]);
            if(dt<=0)d.valid=0;
            if(!d.valid)new_count++;else valid_count++;
            Process *p=&current[i];RUsageV2 *r=&p->r;
            fprintf(f,"P\t%d\t%llu\t%s\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%d\t%llu\t%llu\t%llu\t%llu\t%llu\t%.6f\t%s\n",
              p->pid,(unsigned long long)r->start_abs,p->name,(unsigned long long)r->user_ns,(unsigned long long)r->system_ns,
              (unsigned long long)r->idle_wakeups,(unsigned long long)r->interrupt_wakeups,(unsigned long long)r->read_bytes,
              (unsigned long long)r->written_bytes,d.valid,(unsigned long long)d.cpu_ns,(unsigned long long)d.idle,
              (unsigned long long)d.interrupts,(unsigned long long)d.read_bytes,(unsigned long long)d.written_bytes,
              d.valid&&dt>0?(double)d.cpu_ns/1e9/dt*100.0:-1.0,p->path);
            if(!append_total(totals,&nt,p,d,!d.valid)) fputs("WARNING\tTotals table full; raw process rows remain usable\n",f);
        }
        fprintf(f,"SAMPLE_END\tvalid_process_intervals=%d\tnew_or_reset_baselines=%d\n",valid_count,new_count);
        Process *swap=prev;prev=current;current=swap;np=n;last_cont=cont;last_awake=awake;
        report_write_ok=!(fflush(f) || ferror(f));
        state_write_ok=save_state(&s);
        last_report_bytes=ftell(f);
        if(!report_write_ok || !state_write_ok) {reason="ERROR: Report or state write failed. Recording stopped.";break;}
        if(request_nonce)last_check_nonce=request_nonce;
        int top=-1;for(int i=0;i<nt;i++)if(top<0 || totals[i].cpu_ns>totals[top].cpu_ns)top=i;
        make_status(&s,denied?"RECORDING - Some processes are inaccessible; coverage is partial.":"RECORDING - Share the report at any time.",n,denied,top>=0?&totals[top]:0);
        if(ftell(f)>=REPORT_LIMIT) {reason="STOPPED: Report size limit reached; data is still usable.";break;}
        if(stopping){reason="PAUSED: Collector stopped. The existing session can resume on the next jailbreak launch.";break;}
        double left=remaining(&s,now,cont,platform_boot_id());
        if(left<=0)break;
        if(s.samples>=MAX_SESSION_SAMPLES) {reason="STOPPED: Safety sample limit reached.";break;}
        unsigned wait=left<INTERVAL?(unsigned)left:INTERVAL;if(!wait)wait=1;
        /* Repeated UI taps cannot become an unbounded sampling loop. A check
         * flag set before sleep is handled promptly on the next iteration. */
        platform_wait(wait,&stopping,&check_requested);
        if(stopping){reason="PAUSED: Collector stopped. The existing session can resume on the next jailbreak launch.";break;}
    }
finish:
    fprintf(f,"\nRESULT\t%s\n",reason);
    fprintf(f,"SESSION\tsamples=%u\tlogger_runs=%u\tbattery_first_pct=%.3f\tbattery_last_pct=%.3f\tbattery_samples=%u\tcharging_or_external_power_samples=%u\n",
            s.samples,s.runs,s.first_pct,s.last_pct,s.battery_samples,s.charged_samples);
    if(s.first_pct>=0 && s.last_pct>=0) fprintf(f,"BATTERY_CHANGE\tnet_percentage_points=%.3f\tNOT_AN_ENERGY_MEASUREMENT=1\n",s.first_pct-s.last_pct);
    if(totals)summary(f,totals,nt,s.runs);
    fputs("\nCONFIDENCE\tNo automatic exact-tweak verdict. Package ownership and declared injection targets are evidence for a targeted follow-up, not proof.\n",f);
    int final_write_ok=!(fflush(f) || ferror(f));
    last_report_bytes=ftell(f);if(fclose(f))final_write_ok=0;
    int final_state_ok=save_state(&s);
    if((!final_write_ok || !final_state_ok) && !stopping)reason="ERROR: Final report or state write failed.";
    platform_check_cancel();
    make_status(&s,reason,last_n,last_denied,0);
    if(!stopping) {FILE *d=fopen(DONE,"w");if(d){fprintf(d,"%s\n",reason);fclose(d);}}
    free(current);free(prev);free(totals);inventory_free();fclose(lock);
    return 0;
}
