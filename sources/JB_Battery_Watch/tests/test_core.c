#include "../src/core.h"
#include <assert.h>
int main(void) {
    assert(ticks_to_nanoseconds(24,125,3)==1000);
    assert(ticks_to_nanoseconds(1,125,3)==41);
    assert(ticks_to_nanoseconds(987654321,1,1)==987654321);
    assert(ticks_to_nanoseconds(1,1,0)==0);
    assert(ticks_to_nanoseconds(24000000000ULL,125,3)==1000000000000ULL);

    Process a={0},b={0};a.pid=b.pid=8;a.r.start_abs=b.r.start_abs=11;
    copystr(a.name,NAME_LEN,"SpringBoard");copystr(a.path,PATH_LEN,"/System/Library/CoreServices/SpringBoard.app/SpringBoard");b=a;
    a.r.user_ns=100;b.r.user_ns=400;b.r.system_ns=10;b.r.idle_wakeups=7;b.r.interrupt_wakeups=9;b.r.read_bytes=80;b.r.written_bytes=90;
    Delta d=counter_delta(&a,&b);assert(d.valid&&d.cpu_ns==310&&d.idle==7&&d.interrupts==9&&d.read_bytes==80&&d.written_bytes==90);
    assert(!counter_delta(0,&b).valid);
    b.pid++;assert(!counter_delta(&a,&b).valid);b.pid--;
    b.r.start_abs++;assert(!counter_delta(&a,&b).valid);b.r.start_abs--;
    b.r.uuid[5]=1;assert(!counter_delta(&a,&b).valid);b.r.uuid[5]=0;
    b.r.user_ns=10;assert(!counter_delta(&a,&b).valid);b.r.user_ns=400;
    a.r.idle_wakeups=8;assert(!counter_delta(&a,&b).valid);a.r.idle_wakeups=0;
    a.r.written_bytes=100;assert(!counter_delta(&a,&b).valid);a.r.written_bytes=0;
    copystr(b.path,PATH_LEN,"different");assert(!counter_delta(&a,&b).valid);copystr(b.path,PATH_LEN,a.path);
    char path[PATH_LEN];assert(canonical_path("/private/var/jb/usr/lib/a.dylib",0,path,sizeof(path)));
    assert(!strcmp(path,"/var/jb/usr/lib/a.dylib"));
    canonical_path("/private/preboot/abc/jb/usr/bin/x","/private/preboot/abc/jb",path,sizeof(path));assert(!strcmp(path,"/var/jb/usr/bin/x"));
    canonical_path("/private/preboot/abc/jb-other/x","/private/preboot/abc/jb",path,sizeof(path));assert(!strcmp(path,"/private/preboot/abc/jb-other/x"));
    canonical_path("/System/a",0,path,sizeof(path));assert(!strcmp(path,"/System/a"));
    char tiny[3];copystr(tiny,sizeof(tiny),"abcdef");assert(!strcmp(tiny,"ab"));
    char text[]="a\nb\tc\rd";cleantext(text);assert(!strcmp(text,"a b c d"));
    assert(!deadline_reached(1000,900,2000));assert(deadline_reached(2000,900,2000));assert(deadline_reached(4000,900,2000));assert(deadline_reached(4000,0,2000));
    Total *totals=calloc(MAX_TOTALS,sizeof(*totals));int n=0;
    assert(append_total(totals,&n,&b,d,1)&&n==1);assert(totals[0].cpu_ns==310&&totals[0].identities==1);
    assert(append_total(totals,&n,&b,d,0)&&n==1&&totals[0].cpu_ns==620);
    n=MAX_TOTALS;copystr(b.name,NAME_LEN,"new");assert(!append_total(totals,&n,&b,d,0));
    free(totals);puts("PASS: core identity/reset, delta arithmetic, grouping, limits, deadline and path tests");return 0;
}
