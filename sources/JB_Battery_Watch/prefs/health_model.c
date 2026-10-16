#include "health_model.h"
#include "../src/platform.h"
static JBBWAssessment result(int severity,const char *title,const char *detail){
    JBBWAssessment a={.severity=severity};snprintf(a.title,sizeof(a.title),"%s",title);snprintf(a.detail,sizeof(a.detail),"%s",detail);return a;
}
JBBWAssessment jbbw_assess(JBBWHealth h,int pending,int timed_out,uint64_t requested){
    if(!h.health_readable)return result(2,"ERROR — Status unavailable","The recorder's live-status file cannot be read. Open Diagnostic Details and export the report; startup or sandbox access may have failed. Installation alone is not proof of recording.");
    if(h.schema!=1 || !h.state[0] || h.samples>1024 || h.last<0 || h.start<0 || h.last>h.now+300)
        return result(2,"ERROR — Invalid status","The status file is malformed, unsupported, or has an implausible timestamp. The clock may have changed. Export the diagnostic report.");
    if(!strcmp(h.state,"ERROR"))return result(2,"ERROR — Recorder stopped",h.message[0]?h.message:"The recorder reported an error. Export includes its available startup and access diagnostics.");
    if(!strcmp(h.state,"STARTING"))return result(1,"STARTING — Not verified yet","The installation/startup check has not confirmed a sample. Tap Check Now after installation finishes.");
    if(!h.report_readable || !h.report_valid)return result(2,"ERROR — Report unavailable","The report is missing, unreadable, empty, or does not have the expected report header. Export still gathers any available diagnostic files.");
    if(!strcmp(h.state,"COMPLETE"))return result(0,"COMPLETE — Report ready","The recording window has ended. The report is readable. The recorder is expected to be stopped; no live reply is required. Export the log to share it.");
    if(!strcmp(h.state,"PAUSED") || !strcmp(h.state,"STOPPED"))return result(1,"STOPPED — Partial report ready",h.message[0]?h.message:"Recording is stopped. Existing data is preserved and can be exported.");
    if(strcmp(h.state,"RECORDING"))return result(2,"ERROR — Unknown recorder state","The recorder status is not recognized. Export the diagnostics rather than assuming recording is active.");
    if(h.samples<1 || h.readable<=1 || !h.write_ok || !h.state_ok)
        return result(2,"ERROR — Collection not verified","No successful full process sample and saved report/state could be verified. Export the diagnostics for the specific failure.");
    if(pending)return result(1,"CHECKING — Waiting for recorder","A one-off live check was requested. Confirmation requires the recorder to collect and save a new sample carrying this request's unique token.");
    if(timed_out || (requested && h.nonce!=requested))return result(1,"WARNING — No live confirmation","The recorder did not return this check's token in time. It may be stopped, delayed, or unable to receive the notification. Previous samples remain usable; this is NOT a successful live check. Tap Check Now once more while the phone is unlocked, or export diagnostics.");
    if(h.now-h.last>900)return result(1,"WARNING — Last sample is old","No recent sample is visible. Deep sleep or scheduling can delay samples, so this alone does not prove a crash. Tap Check Now while the phone is awake to request a fresh saved sample.");
    if(!h.check_supported)return result(1,"RECORDING — Live check unavailable","Recent saved samples exist, but the recorder could not register its live-check notification. Export the report for details.");
    if(!requested)return result(1,"RECORDING — Recent sample found","Recent saved data is available. Tap Check Now to verify the recorder is responding right now.");
    if(h.denied>0 || !h.battery_samples)return result(1,"WORKING — Limited measurements",h.denied>0?"The recorder answered this check and saved a new sample, but some processes are inaccessible. This is partial coverage, not proof that unmeasured processes are idle.":"The recorder answered this check and saved a new sample. Battery readings are unavailable; process measurements are still being collected.");
    return result(0,"WORKING — Live check passed","The recorder answered this check, collected readable process counters, and saved a new report sample and session state. This confirms logging, not the accuracy of an exact-tweak battery attribution.");
}
