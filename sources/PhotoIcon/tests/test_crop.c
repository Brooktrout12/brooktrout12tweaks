#include <assert.h>
#include <stdio.h>
#include "../PICropGeometry.h"

static void near(double actual, double expected) { assert(fabs(actual-expected)<0.00001); }
static void rect(PICropRect r, double x, double y, double edge) {
    near(r.x,x); near(r.y,y); near(r.width,edge); near(r.height,edge);
}
int main(void) {
    // Known photo dimensions and manually calculated visible regions.
    near(PIFillScale(4000,3000,300),0.1);
    near(PIFillScale(3000,4000,300),0.1);
    rect(PICropForViewport(4000,3000,300,0.1,50,0),500,0,3000);
    rect(PICropForViewport(3000,4000,300,0.1,0,50),0,500,3000);
    rect(PICropForViewport(4000,3000,300,0.2,250,150),1250,750,1500);
    rect(PICropForViewport(4000,3000,300,0.2,500,300),2500,1500,1500);
    rect(PICropForViewport(4000,3000,300,0.1,-25,20),0,0,3000);
    rect(PICropForViewport(600,600,300,0.5,0,0),0,0,600);
    // A 2:1 panoramic photo at 8x zoom, scrolled all the way to the bottom right.
    rect(PICropForViewport(2048,1024,256,2,3840,1792),1920,896,128);
    // Rotating/resizing the editor should retain the same source crop.
    rect(PICropForViewport(4000,3000,380,380.0/1500,1250*380.0/1500,750*380.0/1500),1250,750,1500);
    // Boundary sweep: even bounce/transient offsets must stay inside the photo.
    int checked=0;
    for(int w=1;w<=4096;w+=83) for(int h=1;h<=4096;h+=97)
        for(int zoom=1;zoom<=8;zoom++) {
            double scale=PIFillScale(w,h,300)*zoom;
            PICropRect r=PICropForViewport(w,h,300,scale,w*scale+20,-20);
            assert(isfinite(r.x) && isfinite(r.y) && isfinite(r.width));
            assert(r.x>=0 && r.y>=0 && r.width>0);
            assert(r.x+r.width<=w+1e-8 && r.y+r.height<=h+1e-8);
            checked++;
        }
    printf("PASS: 8 golden crop cases and %d boundary cases\n",checked);
}
