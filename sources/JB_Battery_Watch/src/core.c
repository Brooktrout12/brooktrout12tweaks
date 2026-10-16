#include "core.h"
uint64_t ticks_to_nanoseconds(uint64_t ticks,uint32_t numer,uint32_t denom) {
    if(!numer || !denom) return 0;
    return (ticks/denom)*numer + ((ticks%denom)*numer)/denom;
}
void copystr(char *d,size_t n,const char *s) {
    if (!n) return;
    if (!s) s="";
    size_t k=strlen(s); if(k>=n) k=n-1;
    memcpy(d,s,k); d[k]=0;
}
void cleantext(char *s) {
    for(;*s;s++) if((unsigned char)*s<32 || (unsigned char)*s==127) *s=' ';
}
const char *base_name(const char *s) { const char *p=strrchr(s,'/'); return p?p+1:s; }
int endswith(const char *s,const char *e) {
    size_t n=strlen(s),m=strlen(e); return n>=m && !strcmp(s+n-m,e);
}
Delta counter_delta(const Process *a,const Process *b) {
    Delta d={0};
    if(!a || a->pid!=b->pid || a->r.start_abs!=b->r.start_abs ||
       memcmp(a->r.uuid,b->r.uuid,16) || strcmp(a->path,b->path)) return d;
    /* A reset, PID reuse, exec or backwards counter is not a huge drain. */
    if(b->r.user_ns<a->r.user_ns || b->r.system_ns<a->r.system_ns ||
       b->r.idle_wakeups<a->r.idle_wakeups ||
       b->r.interrupt_wakeups<a->r.interrupt_wakeups ||
       b->r.read_bytes<a->r.read_bytes || b->r.written_bytes<a->r.written_bytes) return d;
    d.valid=1;
    d.cpu_ns=(b->r.user_ns-a->r.user_ns)+(b->r.system_ns-a->r.system_ns);
    d.idle=b->r.idle_wakeups-a->r.idle_wakeups;
    d.interrupts=b->r.interrupt_wakeups-a->r.interrupt_wakeups;
    d.read_bytes=b->r.read_bytes-a->r.read_bytes;
    d.written_bytes=b->r.written_bytes-a->r.written_bytes;
    return d;
}
int deadline_reached(time_t now,time_t start,time_t end) {
    return start<=0 || end<=start || now>=end;
}
int canonical_path(const char *src,const char *root,char *out,size_t cap) {
    if(!src || src[0]!='/') {copystr(out,cap,src);return 0;}
    if(!strncmp(src,"/private/var/",13)) src+=8;
    size_t k=root?strlen(root):0;
    if(k && !strncmp(src,root,k) && (src[k]=='/' || src[k]==0))
        snprintf(out,cap,"/var/jb%s",src+k);
    else copystr(out,cap,src);
    return 1;
}
int append_total(Total *t,int *n,const Process *p,Delta d,int fresh) {
    int i;
    for(i=0;i<*n;i++) if(!strcmp(t[i].path,p->path) && !strcmp(t[i].name,p->name)) break;
    if(i==*n) {
        if(*n>=MAX_TOTALS) return 0;
        memset(&t[i],0,sizeof(t[i]));copystr(t[i].name,NAME_LEN,p->name);copystr(t[i].path,PATH_LEN,p->path);(*n)++;
    }
    if(fresh) t[i].identities++;
    if(d.valid) {t[i].cpu_ns+=d.cpu_ns;t[i].idle+=d.idle;t[i].interrupts+=d.interrupts;
        t[i].read_bytes+=d.read_bytes;t[i].written_bytes+=d.written_bytes;t[i].intervals++;}
    return 1;
}
