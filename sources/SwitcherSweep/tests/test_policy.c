#include <assert.h>
#include <stdio.h>
#include "../BTSweepPolicy.h"
#include "../BTSweepPresentation.h"

int main(void) {
    assert(!BTSweepCanCloseBundle(NULL));
    assert(!BTSweepCanCloseBundle(""));
    assert(!BTSweepCanCloseBundle("com.apple.springboard"));
    assert(!BTSweepCanCloseBundle("com.apple.SpringBoard"));
    assert(!BTSweepCanCloseBundle("com.apple.backboardd"));
    assert(!BTSweepCanCloseBundle("com.apple.runningboardd"));
    assert(BTSweepCanCloseBundle("com.apple.mobilemail"));
    assert(BTSweepCanCloseBundle("com.apple.Music"));
    assert(BTSweepCanCloseBundle("com.openai.chat"));
    assert(BTSweepCanCloseBundle("com.example.player"));
    char huge[514]; memset(huge,'x',513); huge[513]=0;
    assert(!BTSweepCanCloseBundle(huge));
    struct { double w,h,l,r,b; } devices[] = {
        {375,812,0,0,34}, {390,844,0,0,34}, {430,932,0,0,34},
        {320,568,0,0,0}, {812,375,44,44,21}
    };
    for (size_t i=0;i<sizeof(devices)/sizeof(devices[0]);++i) {
        BTSweepRect r=BTSweepButtonFrame(devices[i].w,devices[i].h,devices[i].l,devices[i].r,devices[i].b);
        assert(r.width>=64 && r.height>=44);
        assert(r.x>=devices[i].l && r.x+r.width<=devices[i].w-devices[i].r);
        assert(r.y>=0 && r.y+r.height<=devices[i].h-devices[i].b);
    }
    BTSweepRect target=BTSweepButtonFrame(375,812,0,0,34);
    assert(target.x==118.5 && target.y==704 && target.width==138 && target.height==46);
    assert(BTSweepButtonFrame(NAN,812,0,0,34).width==0);
    assert(BTSweepButtonFrame(375,812,0,0,1000).width==0);
    assert(BTSweepButtonFrame(50,812,0,0,34).width==0);
    for (size_t i=0;i<1000;++i) assert(BTSweepCardDelay(i)+0.24<0.38);
    assert(BTSweepCardDelay(1)>BTSweepCardDelay(0));
    // Regressions from 1.0.0 (material over Home) and 1.0.1 (late entry).
    // Follow the native opening/settling/cancelling paths, including stale
    // visibility flags. Expected results describe when the user sees a button.
    struct { bool window,visible,transition,toSwitcher,disappearing,expected; } presentation[] = {
        {true,false,false,false,false,false}, // Home/app idle
        {true,false,true,true,false,true},    // Entry starts, old flag still false
        {true,true,true,true,false,true},     // Entry progressing: do not restart fade
        {true,true,false,false,false,true},   // Entry ends: keep the existing button
        {true,true,true,false,false,false},   // Launch app: old flag still true
        {true,true,true,false,true,false},    // Switcher view starts disappearing
        {true,false,false,false,true,false}, // Native Home/app transition finished
        {true,false,true,true,false,true},    // A new entry after returning Home
        {true,true,true,false,false,false},   // Entry cancelled back to Home
        {true,true,true,false,false,false},   // Unknown transition: remain detached
        {false,false,true,true,false,false}, // View/window not attached yet
        {true,true,false,false,true,false}   // Disappearance wins over stale visibility
    };
    for (size_t i=0;i<sizeof(presentation)/sizeof(presentation[0]);++i) {
        assert(BTSweepButtonCanAppear(presentation[i].window,presentation[i].visible,
            presentation[i].transition,presentation[i].toSwitcher,presentation[i].disappearing)
            ==presentation[i].expected);
    }
    // Fast tap before visibility catches up; repeated taps are consumed.
    assert(BTSweepClassifyTap(true,false,true,true,false,false,false)==BTSweepTapQueue);
    assert(BTSweepClassifyTap(true,false,true,true,false,false,true)==BTSweepTapIgnore);
    // At matching entry completion the pending flag is consumed before dispatch.
    assert(BTSweepClassifyTap(true,true,false,false,false,false,false)==BTSweepTapRun);
    assert(BTSweepClassifyTap(true,true,false,false,false,true,false)==BTSweepTapIgnore);
    // Cancelled entry, outgoing transition, disappearance, absent window.
    assert(BTSweepClassifyTap(true,false,false,false,false,false,false)==BTSweepTapIgnore);
    assert(BTSweepClassifyTap(true,true,true,false,false,false,false)==BTSweepTapIgnore);
    assert(BTSweepClassifyTap(true,true,true,true,true,false,false)==BTSweepTapIgnore);
    assert(BTSweepClassifyTap(false,false,true,true,false,false,false)==BTSweepTapIgnore);
    puts("{\"result\":\"PASS\",\"system_components_excluded\":true,\"music_apps_included\":true,\"screen_geometries_checked\":5,\"presentation_scenarios_checked\":12,\"tap_scenarios_checked\":8,\"animation_finishes_before_commit\":true,\"device_runtime_tested\":false}");
    return 0;
}
