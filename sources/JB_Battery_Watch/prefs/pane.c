#include "objc_min.h"
#include "health_model.h"
#include "export_io.h"
#include "ui_refresh.h"
#define REPORT_DIR "/var/mobile/Documents/JBBatteryReport-v2"
#define REPORT_FILE REPORT_DIR "/JB-Battery-Report.txt"
#define CHECK_NAME "com.chatgpt.jbbatterywatch.check"
static const char ContextKey;
static Class PaneClass;
static id context(id self){id d=objc_getAssociatedObject(self,&ContextKey);if(!d){d=M0(C("NSMutableDictionary"),"dictionary");objc_setAssociatedObject(self,&ContextKey,d,1);}return d;}
static void textcopy(char *out,size_t cap,const char *in){snprintf(out,cap,"%s",in?in:"");}
static long long dint(id d,const char *key){id v=get(d,key);return iskind(v,"NSNumber")?I(v):0;}
static double dreal(id d,const char *key,double fallback){id v=get(d,key);return iskind(v,"NSNumber")?F(v):fallback;}
static const char *dstr(id d,const char *key){id v=get(d,key);return iskind(v,"NSString")?U(v):"";}
static int readable(const char *path){FILE*f=fopen(path,"rb");if(!f)return 0;fclose(f);return 1;}
static JBBWHealth read_health(void){
    JBBWHealth h={.battery=-1,.first_battery=-1,.now=time(0)};
    id d=M1(C("NSDictionary"),"dictionaryWithContentsOfFile:",N(REPORT_DIR "/HEALTH.plist"));
    if(iskind(d,"NSDictionary")){
        h.health_readable=1;h.schema=(int)dint(d,"Schema");h.pid=dint(d,"PID");h.start=dint(d,"SessionStart");h.deadline=dint(d,"Deadline");h.last=dint(d,"LastSample");
        h.samples=(unsigned)dint(d,"SampleCount");h.readable=(int)dint(d,"ProcessCount");h.denied=(int)dint(d,"DeniedCount");h.write_ok=(int)dint(d,"ReportWriteOK");h.state_ok=(int)dint(d,"StateWriteOK");
        h.battery_samples=(unsigned)dint(d,"BatterySamples");h.charged_samples=(unsigned)dint(d,"ChargedSamples");h.check_supported=(int)dint(d,"CheckSupported");h.nonce=(uint64_t)dint(d,"LastCheckNonce");
        h.battery=dreal(d,"BatteryPercent",-1);h.first_battery=dreal(d,"FirstBatteryPercent",-1);textcopy(h.state,sizeof(h.state),dstr(d,"State"));textcopy(h.message,sizeof(h.message),dstr(d,"Message"));
    }
    FILE*f=fopen(REPORT_FILE,"rb");if(f){char header[128]={0};h.report_readable=1;if(fgets(header,sizeof(header),f))h.report_valid=!strncmp(header,"JB BATTERY WATCH ",17);fclose(f);}
    h.probe_readable=readable(REPORT_DIR "/PROBE.txt");h.install_readable=readable(REPORT_DIR "/INSTALL.txt");return h;
}
static id spec(id self,const char *name,const char *key,long cell,const char *action){
    id p=((id(*)(id,SEL,id,id,SEL,SEL,Class,long,Class))objc_msgSend)(C("PSSpecifier"),S("preferenceSpecifierNamed:target:set:get:detail:cell:edit:"),N(name),self,0,key?S("jbbwValue:"):0,0,cell,0);
    if(key)V2(p,"setProperty:forKey:",N(key),N("id"));
    if(action)((void(*)(id,SEL,SEL))objc_msgSend)(p,S("setButtonAction:"),S(action));
    return p;
}
static id group(id a,const char *title,const char *footer){id p=M1(C("PSSpecifier"),"groupSpecifierWithName:",N(title));if(footer)V2(p,"setProperty:forKey:",N(footer),N("footerText"));V1(a,"addObject:",p);return p;}
static id pane_specifiers(id self,SEL cmd){
    (void)cmd;id d=context(self),a=get(d,"specifiers");if(a)return a;
    a=M0(C("NSMutableArray"),"array");put(d,"specifiers",a);
    /* reloadSpecifiers may clear the superclass' private cache. Rebuild via
     * this same first-load path, retaining the current live status/footer. */
    bool exporting=B(get(d,"exportBusy"));
    const char *title=dstr(d,"assessmentTitle"),*detail=dstr(d,"assessmentDetail");
    id g=group(a,exporting?"Preparing export…":(*title?title:"JB Battery Watch 2.1.1"),
        exporting?"Creating a shareable snapshot, including available error diagnostics. Recording continues.":
        (*detail?detail:"Checking the recorder's saved status…"));put(d,"statusGroup",g);
    V1(a,"addObject:",spec(self,"Check Now",0,13,"jbbwCheck"));
    V1(a,"addObject:",spec(self,"Export Full Report",0,13,"jbbwExport"));
    V1(a,"addObject:",spec(self,"Diagnostic Details",0,13,"jbbwDetails"));
    group(a,"Recording",0);
    const char *labels[]={"Samples recorded","Last sample","Readable processes","Unavailable processes","Latest battery","Battery change","Report","Live check","Build"};
    const char *keys[]={"samples","last","processes","denied","battery","change","report","check","version"};
    for(int i=0;i<9;i++)V1(a,"addObject:",spec(self,labels[i],keys[i],4,0));
    group(a,"How to use","Leave the phone unplugged with your usual tweaks and connections. Close Settings for the standby test. Sampling is requested every five minutes for 24 hours. Opening this pane requests one live check; repeated checks add extra samples and are marked in the log.");
    group(a,"Before sharing","Export contains package versions, process names and executable paths, battery/counter samples, status, and available startup errors. Nothing is uploaded until you choose a destination in the share sheet. Several tweaks may share one process: a working recorder does not guarantee exact-tweak attribution.");
    group(a,"Experimental device-test build","Target: iPhone SE (2020), iOS 17.6.x, Dopamine rootless. Built and statically checked; not tested on a physical iPhone. Missing measurements and failed live checks are reported, not treated as success.");
    V1(self,"setSpecifiers:",a);return a;
}
static id pane_value(id self,SEL cmd,id p){(void)cmd;id key=M1(p,"propertyForKey:",N("id"));return M1(context(self),"objectForKey:",key)?:N("—");}
static bool app_active(void);
static void alert(id self,const char *title,const char *body);
static void redraw(id self){
    id d=context(self);
    if(B(get(d,"redrawBusy")))return;
    put(d,"redrawBusy",number(1));
    /* Do not return a stale cached list after PSListController clears its own
     * _specifiers. Our getter rebuilds and reinstalls the list through the
     * same setter used on the successfully loaded 2.1.0 first-load path. */
    V1(d,"removeObjectForKey:",N("specifiers"));
    int route=jbbw_refresh_list(self);
    put(d,"uiRefreshRoute",number(route));
    put(d,"redrawBusy",number(0));
    if(!route && !B(get(d,"uiWarningShown")) && B(get(d,"visible")) && app_active()){
        put(d,"uiWarningShown",number(1));
        alert(self,"Settings refresh unavailable","This Settings controller has no supported refresh method. The recorder has not been changed or stopped. Export Full Report includes this compatibility result for diagnosis.");
    }
}
static bool app_active(void){id app=M0(C("UIApplication"),"sharedApplication");return ((long(*)(id,SEL))objc_msgSend)(app,S("applicationState"))==0;}
static void refresh(id self,SEL cmd){
    (void)cmd;id d=context(self);JBBWHealth h=read_health();uint64_t request=(uint64_t)I(get(d,"requested"));
    bool pending=B(get(d,"pending"));if(pending && request && h.nonce==request && h.last>=I(get(d,"requestWall"))) {put(d,"pending",number(0));put(d,"timeout",number(0));pending=false;}
    if(pending && time(0)-I(get(d,"requestWall"))>=20){put(d,"pending",number(0));put(d,"timeout",number(1));pending=false;}
    JBBWAssessment a=jbbw_assess(h,pending,B(get(d,"timeout")),request);
    if(I(get(d,"notifyError"))){a.severity=2;textcopy(a.title,sizeof(a.title),"ERROR — Check request failed");snprintf(a.detail,sizeof(a.detail),"The notification service rejected the live check (code %lld). Saved data may still be available; export the diagnostics.",I(get(d,"notifyError")));}
    if(I(get(d,"sandyError")) && !h.health_readable){a.severity=2;textcopy(a.title,sizeof(a.title),"ERROR — Report access denied");snprintf(a.detail,sizeof(a.detail),"Settings could not obtain read access through libSandy (code %lld). Check that libSandy is installed and active, then reopen Settings. Export still creates a file explaining the access failure.",I(get(d,"sandyError")));}
    put(d,"assessmentTitle",N(a.title));put(d,"assessmentDetail",N(a.detail));
    id g=get(d,"statusGroup");V1(g,"setName:",N(a.title));V2(g,"setProperty:forKey:",N(a.detail),N("footerText"));
    char v[512];snprintf(v,sizeof(v),"%u",h.samples);put(d,"samples",N(v));
    if(h.last>0){long long age=h.now-h.last;if(age<0)age=0;snprintf(v,sizeof(v),"%lld min ago",age/60);}else textcopy(v,sizeof(v),"Not yet");put(d,"last",N(v));
    snprintf(v,sizeof(v),"%d",h.readable);put(d,"processes",N(v));snprintf(v,sizeof(v),"%d",h.denied);put(d,"denied",N(v));
    if(h.battery>=0 && h.battery<=100)snprintf(v,sizeof(v),"%.1f%%",h.battery);else textcopy(v,sizeof(v),"Unavailable");put(d,"battery",N(v));
    if(h.first_battery>=0 && h.battery>=0)snprintf(v,sizeof(v),"%.1f points%s",h.first_battery-h.battery,h.charged_samples?" (charged)":"");else textcopy(v,sizeof(v),"Unavailable");put(d,"change",N(v));
    put(d,"report",N(h.report_valid?"Readable":"Unavailable"));put(d,"version",N("2.1.1 rootless"));
    put(d,"check",N(pending?"Checking…":(request && h.nonce==request && !B(get(d,"timeout")))?"Replied":B(get(d,"timeout"))?"No reply":h.check_supported?"Ready":"Not active"));redraw(self);
}
static void invalidate_timer(id self){id d=context(self),t=get(d,"timer");if(t){V0(t,"invalidate");V1(d,"removeObjectForKey:",N("timer"));}}
static void tick(id self,SEL cmd,id timer){(void)cmd;(void)timer;id d=context(self);if(!B(get(d,"visible"))||!app_active()){invalidate_timer(self);return;}refresh(self,0);}
static void start_timer(id self){id d=context(self);invalidate_timer(self);id t=((id(*)(id,SEL,double,id,SEL,id,bool))objc_msgSend)(C("NSTimer"),S("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),2.0,self,S("jbbwTick:"),0,true);put(d,"timer",t);}
static void check(id self,SEL cmd){
    (void)cmd;id d=context(self);if(B(get(d,"pending")))return;
    int sandy=libSandy_applyProfile("JBBatteryWatch_ReadReports");put(d,"sandyError",number(sandy));JBBWHealth h=read_health();
    put(d,"notifyError",number(0));put(d,"timeout",number(0));
    if(!h.health_readable || !h.check_supported || strcmp(h.state,"RECORDING")){refresh(self,0);return;}
    /* Explicit user checks are rate limited in this UI. The recorder also has
     * its existing 1024-sample and 32 MiB safety caps. */
    if(time(0)-I(get(d,"requestWall"))<10){refresh(self,0);return;}
    uint64_t nonce=(((uint64_t)(arc4random()&0x7fffffffU))<<32)|arc4random();if(!nonce)nonce=1;
    int token=-1,e=notify_register_check(CHECK_NAME,&token);if(!e)e=notify_set_state(token,nonce);if(!e)e=notify_post(CHECK_NAME);if(token>=0)notify_cancel(token);
    put(d,"notifyError",number(e));put(d,"requested",number((long long)nonce));put(d,"requestWall",number(time(0)));put(d,"pending",number(!e));
    refresh(self,0);if(B(get(d,"visible"))&&app_active())start_timer(self);
}
static void app_background(id self,SEL cmd,id notification){(void)cmd;(void)notification;invalidate_timer(self);}
static void app_foreground(id self,SEL cmd,id notification){(void)cmd;(void)notification;if(B(get(context(self),"visible"))){refresh(self,0);start_timer(self);}}
static void super_bool(id self,const char *name,bool animated){struct objc_super s={self,PaneClass};((void(*)(struct objc_super*,SEL,bool))objc_msgSendSuper2)(&s,S(name),animated);}
static void appeared(id self,SEL cmd,bool animated){(void)cmd;super_bool(self,"viewDidAppear:",animated);id d=context(self);put(d,"visible",number(1));V1(self,"setTitle:",N("JB Battery Watch"));
    id nc=M0(C("NSNotificationCenter"),"defaultCenter");
    ((void(*)(id,SEL,id,SEL,id,id))objc_msgSend)(nc,S("addObserver:selector:name:object:"),self,S("jbbwBackground:"),N("UIApplicationDidEnterBackgroundNotification"),0);
    ((void(*)(id,SEL,id,SEL,id,id))objc_msgSend)(nc,S("addObserver:selector:name:object:"),self,S("jbbwForeground:"),N("UIApplicationDidBecomeActiveNotification"),0);
    check(self,0);start_timer(self);
}
static void disappearing(id self,SEL cmd,bool animated){(void)cmd;put(context(self),"visible",number(0));invalidate_timer(self);id nc=M0(C("NSNotificationCenter"),"defaultCenter");
    ((void(*)(id,SEL,id,id,id))objc_msgSend)(nc,S("removeObserver:name:object:"),self,N("UIApplicationDidEnterBackgroundNotification"),0);
    ((void(*)(id,SEL,id,id,id))objc_msgSend)(nc,S("removeObserver:name:object:"),self,N("UIApplicationDidBecomeActiveNotification"),0);
    super_bool(self,"viewWillDisappear:",animated);
}
static void alert(id self,const char *title,const char *body){if(M0(self,"presentedViewController"))return;
    id a=((id(*)(id,SEL,id,id,long))objc_msgSend)(C("UIAlertController"),S("alertControllerWithTitle:message:preferredStyle:"),N(title),N(body),1);
    id ok=((id(*)(id,SEL,id,long,id))objc_msgSend)(C("UIAlertAction"),S("actionWithTitle:style:handler:"),N("OK"),0,0);V1(a,"addAction:",ok);
    ((void(*)(id,SEL,id,bool,id))objc_msgSend)(self,S("presentViewController:animated:completion:"),a,true,0);
}
static void details(id self,SEL cmd){(void)cmd;refresh(self,0);id d=context(self);char buf[12288]={0};snprintf(buf,sizeof(buf),"%s\n\n%s\n\nPane 2.1.1\nlibSandy result: %lld\nNotification result: %lld\nUI refresh route: %lld (1=list, 2=table, 3=loaded view, 0=unsupported)\n\n",U(get(d,"assessmentTitle")),U(get(d,"assessmentDetail")),I(get(d,"sandyError")),I(get(d,"notifyError")),I(get(d,"uiRefreshRoute")));
    FILE*f=fopen(REPORT_DIR "/STATUS.txt","r");if(f){size_t n=strlen(buf);fread(buf+n,1,sizeof(buf)-n-1,f);fclose(f);}
    id vc=M0(M0(C("UIViewController"),"alloc"),"init");V1(vc,"setTitle:",N("Diagnostic Details"));
    id tv=M0(M0(C("UITextView"),"alloc"),"init");V1(tv,"setText:",N(buf));
    ((void(*)(id,SEL,bool))objc_msgSend)(tv,S("setEditable:"),false);((void(*)(id,SEL,bool))objc_msgSend)(tv,S("setSelectable:"),true);
    id font=((id(*)(id,SEL,double,double))objc_msgSend)(C("UIFont"),S("monospacedSystemFontOfSize:weight:"),13.0,0.0);V1(tv,"setFont:",font);V1(tv,"setBackgroundColor:",M0(C("UIColor"),"systemBackgroundColor"));
    V1(vc,"setView:",tv);((void(*)(id,SEL,id,bool))objc_msgSend)(M0(self,"navigationController"),S("pushViewController:animated:"),vc,true);V0(tv,"release");V0(vc,"release");
}
/* Export streams a finite snapshot of each allowlisted file. It never modifies
 * recorder data and never runs shell commands. Errors are part of the export. */

static void export_complete(id self,SEL cmd,id result){(void)cmd;id d=context(self);put(d,"exportBusy",number(0));refresh(self,0);const char *err=dstr(result,"error");if(*err){alert(self,"Export failed",err);return;}
    id path=get(result,"path");put(d,"lastExport",path);if(!B(get(d,"visible"))||!app_active())return;
    if(M0(self,"presentedViewController"))return;
    id url=M1(C("NSURL"),"fileURLWithPath:",path);id items=M1(C("NSArray"),"arrayWithObject:",url);
    id sheet=M2(M0(C("UIActivityViewController"),"alloc"),"initWithActivityItems:applicationActivities:",items,0);
    id pop=M0(sheet,"popoverPresentationController");if(pop){id v=M0(self,"view");V1(pop,"setSourceView:",v);CGRect bounds=((CGRect(*)(id,SEL))objc_msgSend)(v,S("bounds"));CGRect r={{bounds.size.width/2,bounds.size.height/2},{1,1}};((void(*)(id,SEL,CGRect))objc_msgSend)(pop,S("setSourceRect:"),r);}
    ((void(*)(id,SEL,id,bool,id))objc_msgSend)(self,S("presentViewController:animated:completion:"),sheet,true,0);V0(sheet,"release");
}
static void build_export(id self,SEL cmd,id info){
    (void)cmd;void *pool=objc_autoreleasePoolPush();id result=M0(C("NSMutableDictionary"),"dictionary");char dir[2048],path[2304],error[512]={0};
    const char *temp=U(NSTemporaryDirectory());if(!temp||!temp[0])textcopy(error,sizeof(error),"Settings did not provide a writable temporary directory.");
    else {snprintf(dir,sizeof(dir),"%s/JB-Battery-Watch-Exports",temp);mkdir(dir,0700);snprintf(path,sizeof(path),"%s/JB-Battery-Report-%lld-%08x.txt",dir,(long long)time(0),arc4random());FILE*f=fopen(path,"wb");
        if(!f)snprintf(error,sizeof(error),"Could not create the export: %s (errno %d).",strerror(errno),errno);
        else {
            chmod(path,0600);fprintf(f,"JB BATTERY WATCH — SETTINGS EXPORT 2.1.1\nExport time (Unix): %lld\nTarget: iPhone SE 2020 / iOS 17.6.x / Dopamine rootless\n\n",(long long)time(0));
            fprintf(f,"PANE CHECK RESULT\n%s\n%s\nlibSandy result: %lld\nNotification result: %lld\nUI refresh route: %lld (1=list, 2=table, 3=loaded view, 0=unsupported)\n\n",dstr(info,"title"),dstr(info,"detail"),dint(info,"sandy"),dint(info,"notify"),dint(info,"uiRefreshRoute"));
            fputs("Export is a local, finite snapshot. The last sample may have been in progress while exported. Missing files and partial measurements are marked below. It does not prove exact-tweak energy attribution. Sharing is user initiated.\n",f);
            jbbw_append_diagnostic(f,REPORT_DIR,"JB-Battery-Report.txt",40L*1024*1024);jbbw_append_diagnostic(f,REPORT_DIR,"HEALTH.plist",65536);jbbw_append_diagnostic(f,REPORT_DIR,"STATUS.txt",65536);jbbw_append_diagnostic(f,REPORT_DIR,"PROBE.txt",262144);jbbw_append_diagnostic(f,REPORT_DIR,"INSTALL.txt",262144);jbbw_append_diagnostic(f,REPORT_DIR,"LAUNCH.txt",262144);
            int failed=fflush(f)||ferror(f);if(fclose(f))failed=1;
            if(failed){textcopy(error,sizeof(error),"The export could not be written completely. Check free storage and try again.");remove(path);}else put(result,"path",N(path));
        }
    }
    if(*error)put(result,"error",N(error));
    ((void(*)(id,SEL,SEL,id,bool))objc_msgSend)(self,S("performSelectorOnMainThread:withObject:waitUntilDone:"),S("jbbwExportComplete:"),result,false);
    objc_autoreleasePoolPop(pool);
}
static void export_log(id self,SEL cmd){
    (void)cmd;id d=context(self);if(B(get(d,"exportBusy")) || M0(self,"presentedViewController"))return;
    refresh(self,0);put(d,"exportBusy",number(1));id info=M0(C("NSMutableDictionary"),"dictionary");put(info,"title",get(d,"assessmentTitle"));put(info,"detail",get(d,"assessmentDetail"));put(info,"sandy",get(d,"sandyError"));put(info,"notify",get(d,"notifyError"));put(info,"uiRefreshRoute",get(d,"uiRefreshRoute"));
    id g=get(d,"statusGroup");V1(g,"setName:",N("Preparing export…"));V2(g,"setProperty:forKey:",N("Creating a shareable snapshot, including available error diagnostics. Recording continues."),N("footerText"));redraw(self);
    ((void(*)(id,SEL,SEL,id,id))objc_msgSend)(C("NSThread"),S("detachNewThreadSelector:toTarget:withObject:"),S("jbbwBuildExport:"),self,info);
}
#define ADD(name,fn,encoding) class_addMethod(PaneClass,S(name),(IMP)fn,encoding)
__attribute__((constructor)) static void register_pane(void){
    Class base=objc_getClass("PSListController");if(!base)return;
    PaneClass=objc_allocateClassPair(base,"JBBWPreferencesController",0);if(!PaneClass)return;
    ADD("specifiers",pane_specifiers,"@@:");ADD("jbbwValue:",pane_value,"@@:@");ADD("jbbwRefresh",refresh,"v@:");
    ADD("jbbwCheck",check,"v@:");ADD("jbbwExport",export_log,"v@:");ADD("jbbwDetails",details,"v@:");ADD("jbbwTick:",tick,"v@:@");
    ADD("jbbwBackground:",app_background,"v@:@");ADD("jbbwForeground:",app_foreground,"v@:@");
    ADD("viewDidAppear:",appeared,"v@:B");ADD("viewWillDisappear:",disappearing,"v@:B");
    ADD("jbbwBuildExport:",build_export,"v@:@");ADD("jbbwExportComplete:",export_complete,"v@:@");objc_registerClassPair(PaneClass);
}
