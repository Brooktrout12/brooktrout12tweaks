#include "../prefs/health_model.h"
#include "../prefs/export_io.h"
#include <assert.h>
static int count;
static void check(const char *name,int pass){assert(pass);printf("PASS: %s\n",name);count++;}
static JBBWHealth good(void){JBBWHealth h={.health_readable=1,.report_readable=1,.report_valid=1,.schema=1,.readable=120,.write_ok=1,.state_ok=1,.check_supported=1,.samples=3,.battery_samples=3,.now=100000,.last=99999,.start=99000,.nonce=123,.battery=97,.first_battery=100};snprintf(h.state,sizeof(h.state),"RECORDING");return h;}
int main(void){
    JBBWHealth h=good();JBBWAssessment a=jbbw_assess(h,0,0,123);check("matching live nonce and saved sample confirms working",a.severity==0&&strstr(a.title,"WORKING"));
    a=jbbw_assess(h,1,0,124);check("pending request is not called success",a.severity==1&&strstr(a.title,"CHECKING"));
    a=jbbw_assess(h,0,1,124);check("timeout produces a warning, not a false crash claim",a.severity==1&&strstr(a.title,"No live"));
    a=jbbw_assess(h,0,0,124);check("a previous request token cannot confirm a new check",a.severity==1);
    a=jbbw_assess(h,0,0,0);check("recent file alone is not a live confirmation",a.severity==1);
    h.health_readable=0;check("missing status is an error",jbbw_assess(h,0,0,0).severity==2);
    h=good();h.schema=99;check("unsupported schema rejected",jbbw_assess(h,0,0,123).severity==2);
    h=good();h.last=h.now+1000;check("future timestamp is not trusted",jbbw_assess(h,0,0,123).severity==2);
    h=good();h.samples=100000;check("implausible sample count rejected",jbbw_assess(h,0,0,123).severity==2);
    h=good();h.last=h.now-3600;check("sleep-delayed sample warns without claiming a crash",jbbw_assess(h,0,0,123).severity==1);
    h=good();h.report_readable=0;check("missing report is an error",jbbw_assess(h,0,0,123).severity==2);
    h=good();h.report_valid=0;check("wrong report header rejected",jbbw_assess(h,0,0,123).severity==2);
    h=good();h.write_ok=0;check("failed report write cannot pass live check",jbbw_assess(h,0,0,123).severity==2);
    h=good();h.state_ok=0;check("failed session save cannot pass live check",jbbw_assess(h,0,0,123).severity==2);
    h=good();h.readable=1;check("insufficient process access is an error",jbbw_assess(h,0,0,123).severity==2);
    h=good();h.denied=20;check("partial process coverage remains qualified",jbbw_assess(h,0,0,123).severity==1);
    h=good();h.battery_samples=0;check("missing battery measurements remain qualified",jbbw_assess(h,0,0,123).severity==1);
    h=good();h.check_supported=0;check("unavailable notification channel is not success",jbbw_assess(h,0,0,123).severity==1);
    h=good();snprintf(h.state,sizeof(h.state),"COMPLETE");h.last=1;h.readable=0;check("completed recording needs no running daemon",jbbw_assess(h,0,0,0).severity==0);
    h=good();snprintf(h.state,sizeof(h.state),"ERROR");snprintf(h.message,sizeof(h.message),"Detailed fixture failure");a=jbbw_assess(h,0,0,0);check("recorder's precise error is retained",a.severity==2&&strstr(a.detail,"Detailed fixture"));
    h=good();snprintf(h.state,sizeof(h.state),"PAUSED");check("paused report is exportable but not called working",jbbw_assess(h,0,0,0).severity==1);
    h=good();snprintf(h.state,sizeof(h.state),"MYSTERY");check("unrecognized state rejected",jbbw_assess(h,0,0,0).severity==2);
    char temp[]="/tmp/jbbw-export-test-XXXXXX";assert(mkdtemp(temp));char path[1024];snprintf(path,sizeof(path),"%s/STATUS.txt",temp);
    FILE*f=fopen(path,"w");assert(f);fputs("fixture-data",f);fclose(f);FILE*out=tmpfile();assert(out);
    check("export copies readable allowlisted diagnostic",jbbw_append_diagnostic(out,temp,"STATUS.txt",65536)==1);
    check("missing source is captured as unavailable",jbbw_append_diagnostic(out,temp,"PROBE.txt",65536)==0);
    check("path traversal is rejected",jbbw_append_diagnostic(out,temp,"../STATUS.txt",65536)==0);
    check("oversized export request is rejected",jbbw_append_diagnostic(out,temp,"STATUS.txt",50L*1024*1024)==0);
    check("bounded export handles truncation",jbbw_append_diagnostic(out,temp,"STATUS.txt",3)==1);
    fflush(out);rewind(out);char text[8192]={0};fread(text,1,sizeof(text)-1,out);fclose(out);remove(path);rmdir(temp);
    check("export includes source contents",strstr(text,"fixture-data")!=0);
    check("export includes file-read error information",strstr(text,"UNAVAILABLE:")!=0);
    check("truncation is explicitly reported",strstr(text,"source was truncated")!=0);
    printf("\n%d health/export checks passed. Native Settings UI and Apple notification delivery were NOT executed.\n",count);return 0;
}
