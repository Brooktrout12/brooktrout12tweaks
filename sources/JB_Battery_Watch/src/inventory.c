#include "inventory.h"
typedef struct {char path[PATH_LEN],package[192];} OwnedFile;
typedef struct {char file[PATH_LEN],package[192];void *filter;} Tweak;
static OwnedFile *files;static int nfiles;
static Tweak *tweaks;static int ntweaks;
static char info_dir[PATH_LEN];
static const char *injectdirs[]={"/var/jb/Library/MobileSubstrate/DynamicLibraries","/var/jb/usr/lib/TweakInject",0};
static const char *daemondirs[]={"/var/jb/Library/LaunchDaemons","/var/jb/Library/LaunchAgents",0};
#ifdef JBBW_HOST_TEST
static const char *testpath(const char *path) {static char p[2048];snprintf(p,sizeof(p),"%s%s",getenv("JBBW_FIXTURE_ROOT"),path);return p;}
#else
static const char *testpath(const char *path) {return path;}
#endif
const char *file_owner(const char *path) {
    for(int i=0;i<nfiles;i++) if(!strcmp(files[i].path,path)) return files[i].package;
    return "unmapped (Apple/app/unpackaged/limit)";
}
static int interesting_path(const char *p) {
    return endswith(p,".dylib") || strstr(p,"/LaunchDaemons/") || strstr(p,"/LaunchAgents/") ||
           strstr(p,"/bin/") || strstr(p,"/sbin/") || strstr(p,"/libexec/") || strstr(p,"/DynamicLibraries/") || strstr(p,"/TweakInject/");
}
static void build_file_map(FILE *report) {
    files=calloc(MAX_FILES,sizeof(*files));tweaks=calloc(1024,sizeof(*tweaks));
    if(!files || !tweaks) {fputs("META_WARNING\tFile ownership/candidate allocation failed\n",report);return;}
    DIR *d=opendir(testpath(info_dir));if(!d) {fputs("META_WARNING\tPackage file ownership database unavailable\n",report);return;}
    struct dirent *ent;
    while((ent=readdir(d))) {
        if(!endswith(ent->d_name,".list")) continue;
        char p[PATH_LEN],pkg[192];snprintf(p,sizeof(p),"%s/%s",info_dir,ent->d_name);
        copystr(pkg,sizeof(pkg),ent->d_name);char *dot=strrchr(pkg,'.');if(dot) *dot=0;char *colon=strchr(pkg,':');if(colon) *colon=0;
        FILE *f=fopen(testpath(p),"r");if(!f) continue;
        char line[4096];
        while(fgets(line,sizeof(line),f)) {
            char *nl=strchr(line,'\n');if(nl)*nl=0;else if(!endswith(line,"/" ) && strlen(line)>=sizeof(line)-1) continue;
            if(!interesting_path(line) || nfiles>=MAX_FILES) continue;
            char normal[PATH_LEN];canonical_path(line,platform_jbroot(),normal,sizeof(normal));
            if(strncmp(normal,"/var/jb/",8)) {
                if(normal[0]!='/') continue;
                char temp[PATH_LEN];copystr(temp,sizeof(temp),normal);snprintf(normal,sizeof(normal),"/var/jb%s",temp);
            }
            copystr(files[nfiles].path,PATH_LEN,normal);copystr(files[nfiles].package,192,pkg);nfiles++;
        }
        fclose(f);
    }
    closedir(d);if(nfiles>=MAX_FILES) fputs("META_WARNING\tOwnership map limit reached; some owners will be unmapped\n",report);
}
static void package_records(FILE *out) {
    const char *candidates[]={"/var/jb/var/lib/dpkg/status","/var/jb/Library/dpkg/status",0};
    FILE *f=0;int used=-1;
    for(int i=0;candidates[i];i++) if((f=fopen(testpath(candidates[i]),"r"))) {used=i;break;}
    if(!f) {fputs("PACKAGES\tUNAVAILABLE: neither rootless dpkg status location readable\n",out);return;}
    copystr(info_dir,sizeof(info_dir),used==0?"/var/jb/var/lib/dpkg/info":"/var/jb/Library/dpkg/info");
    char line[8192],pkg[192]="",version[192]="",name[256]="",status[128]="";int count=0;
    fputs("PACKAGES\tpackage\tversion\tdisplay_name\tdpkg_status\n",out);
    for(;;) {
        int has=fgets(line,sizeof(line),f)!=0;
        if(!has || line[0]=='\n' || line[0]=='\r') {
            if(pkg[0]) {
                cleantext(pkg);cleantext(version);cleantext(name);cleantext(status);
                fprintf(out,"PKG\t%s\t%s\t%s\t%s\n",pkg,version,name,status);count++;
            }
            pkg[0]=version[0]=name[0]=status[0]=0;
            if(!has || count>=MAX_PACKAGES) break;continue;
        }
        char *nl=strchr(line,'\n');if(nl)*nl=0;
        if(!strncmp(line,"Package: ",9)) copystr(pkg,sizeof(pkg),line+9);
        else if(!strncmp(line,"Version: ",9)) copystr(version,sizeof(version),line+9);
        else if(!strncmp(line,"Name: ",6)) copystr(name,sizeof(name),line+6);
        else if(!strncmp(line,"Status: ",8)) copystr(status,sizeof(status),line+8);
    }
    fclose(f);fprintf(out,"PACKAGE_COUNT\t%d\n",count);
    if(count>=MAX_PACKAGES) fputs("META_WARNING\tPackage inventory limit reached\n",out);
}
static void inventory_dir(FILE *out,const char *dir,int filter,int initialize) {
    DIR *d=opendir(testpath(dir));if(!d) return;
    struct dirent *e;int count=0;
    while((e=readdir(d)) && count<2048 && ftell(out)<REPORT_LIMIT) {
        if(e->d_name[0]=='.') continue;
        char name[1024];copystr(name,sizeof(name),e->d_name);cleantext(name);
        if(!endswith(name,".plist")) continue;
        char p[PATH_LEN];snprintf(p,sizeof(p),"%s/%s",dir,e->d_name);cleantext(p);
        const char *owner=file_owner(p);
        int library_present=0;
        if(filter) {char lib[PATH_LEN];copystr(lib,sizeof(lib),p);lib[strlen(lib)-6]=0;
            char full[PATH_LEN];snprintf(full,sizeof(full),"%s.dylib",lib);library_present=!access(testpath(full),F_OK);
            fprintf(out,"TWEAK_FILTER\t%s\towner=%s\tpaired_dylib_present=%d\tNOT_PROOF_OF_LOADED_INJECTION=1\n",p,owner,library_present);
        } else fprintf(out,"JB_LAUNCH_JOB\t%s\towner=%s\n",p,owner);
        platform_plist_record(out,testpath(p),filter);
        if(initialize && filter && library_present && tweaks && ntweaks<1024) {
            /* Avoid duplicate candidate rows for aliased injection directories. */
            int duplicate=0;for(int j=0;j<ntweaks;j++) if(!strcmp(base_name(tweaks[j].file),name) && !strcmp(tweaks[j].package,owner)) duplicate=1;
            if(!duplicate) {Tweak *t=&tweaks[ntweaks++];copystr(t->file,sizeof(t->file),p);copystr(t->package,sizeof(t->package),owner);
                t->filter=platform_load_filter(testpath(p));}
        }
        count++;
    }
    closedir(d);if(count>=2048) fputs("META_WARNING\tDirectory inventory limit reached\n",out);
}
void inventory(FILE *f,int initialize) {
    fputs("\n=== PACKAGE AND DECLARED INJECTION INVENTORY ===\n",f);package_records(f);
    if(initialize && !files) build_file_map(f);
    for(int i=0;injectdirs[i];i++) inventory_dir(f,injectdirs[i],1,initialize);
    for(int i=0;daemondirs[i];i++) inventory_dir(f,daemondirs[i],0,0);
    fputs("=== END INVENTORY ===\n\n",f);
}
void report_candidates(FILE *f,const Total *t) {
    int matches=0;
    for(int i=0;i<ntweaks;i++) if(tweaks[i].filter && platform_filter_match(tweaks[i].filter,t->name,t->path)) {
        fprintf(f,"DECLARED_TARGET_CANDIDATE\tprocess=%s\tpackage=%s\tfilter=%s\tcausality=UNPROVEN\n",t->name,tweaks[i].package,tweaks[i].file);matches++;
    }
    if(!matches) fputs("CANDIDATES_NOTE\tNo exact executable/SpringBoard-bundle filter match. Broad framework/class filters may still apply; inspect inventory.\n",f);
}
void inventory_free(void) {for(int i=0;i<ntweaks;i++) platform_release_filter(tweaks[i].filter);free(tweaks);free(files);tweaks=0;files=0;ntweaks=nfiles=0;}
