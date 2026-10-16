#include "export_io.h"
#ifndef JBBW_HOST_TEST
extern char *strerror(int);
#endif
int jbbw_append_diagnostic(FILE *out,const char *directory,const char *name,long cap){
    const char *allowed[]={"JB-Battery-Report.txt","HEALTH.plist","STATUS.txt","PROBE.txt","INSTALL.txt","LAUNCH.txt"};
    int known=0;for(unsigned i=0;i<sizeof(allowed)/sizeof(allowed[0]);i++)if(!strcmp(name,allowed[i]))known=1;
    if(!known || cap<0 || cap>40L*1024*1024){fputs("\nEXPORT_ERROR: rejected diagnostic filename or limit\n",out);return 0;}
    char path[1024];snprintf(path,sizeof(path),"%s/%s",directory,name);fprintf(out,"\n\n===== %s =====\n",name);FILE*in=fopen(path,"rb");if(!in){fprintf(out,"UNAVAILABLE: %s (errno %d)\n",strerror(errno),errno);return 0;}
    if(fseek(in,0,SEEK_END)){fputs("ERROR: could not measure source file\n",out);fclose(in);return 0;}long length=ftell(in);if(length<0 || fseek(in,0,SEEK_SET)){fputs("ERROR: could not read source file\n",out);fclose(in);return 0;}
    long left=length<cap?length:cap;char buf[16384];int ok=1;while(left>0){size_t chunk=left<(long)sizeof(buf)?(size_t)left:sizeof(buf);size_t n=fread(buf,1,chunk,in);if(!n){ok=0;break;}if(fwrite(buf,1,n,out)!=n){ok=0;break;}left-=(long)n;}
    if(ferror(in))ok=0;fclose(in);if(!ok)fputs("\nEXPORT_WARNING: source read was incomplete\n",out);if(length>cap)fputs("\nEXPORT_WARNING: source was truncated at the documented size cap\n",out);return ok;
}
