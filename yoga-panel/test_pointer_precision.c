#define main yoga_pointer_main
#include "pointer.c"
#undef main
#include <assert.h>
int main(void) {
    for (int sign=-1;sign<=1;sign+=2) {
        double remainder=0, emitted=0;
        for (int i=0;i<1000;i++) emitted+=wl_fixed_to_double(scroll_fixed(sign*0.0009,&remainder));
        assert(fabs(emitted-sign*0.9)<1.0/256);
        assert(fabs(emitted+remainder-sign*0.9)<1e-10);
    }
    puts("PASS: low-speed subpixel scrolling accumulates without loss in either direction");
    return 0;
}
