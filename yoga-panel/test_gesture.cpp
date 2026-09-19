#include "gesture.hpp"
#include <cassert>
int main() {
    TouchGestures g; using G=Gesture;
    g.down(0,100,0.2,0.2);g.down(1,110,0.3,0.2);g.down(2,120,0.4,0.2);
    assert(g.up(0,150)==G::None);assert(g.up(1,160)==G::None);assert(g.up(2,170)==G::OpenPanel);
    g.down(0,200,0.2,0.2);assert(g.up(0,230)==G::None);
    g.down(0,300,0.2,0.2);g.down(1,310,0.3,0.2);assert(g.up(0,330)==G::None);assert(g.up(1,340)==G::None);
    g.down(0,400,0.2,0.2);g.down(1,410,0.3,0.2);g.down(2,420,0.4,0.2);
    g.motion(0,0.6,0.2);g.up(0,450);g.up(1,460);assert(g.up(2,470)==G::None);
    g.down(0,500,0.2,0.2);g.down(1,510,0.3,0.2);g.down(2,520,0.4,0.2);
    g.up(0,1100);g.up(1,1100);assert(g.up(2,1100)==G::None);
    g.down(0,1200,0.2,0.2);g.down(1,1210,0.3,0.2);g.down(2,1220,0.4,0.2);
    g.reset();assert(g.up(2,1240)==G::None);

    // Eight to ten simultaneous contacts tolerate staggered landing/lifting.
    for (int count : {8, 9, 10}) {
        for (int i=0;i<count;i++) g.down(i,2000+i*20,0.1+i*0.06,0.5);
        for (int i=0;i<count;i++) assert(g.up(i,2300+i*20)==(i==count-1 ? G::OpenPanel : G::None));
    }
    for (int count : {4, 5, 6, 7, 11}) {
        for (int i=0;i<count;i++) g.down(i,3000+i*10,0.1+i*0.05,0.5);
        for (int i=0;i<count;i++) assert(g.up(i,3200+i*10)==G::None);
    }
    for (int i=0;i<10;i++) g.down(i,4000+i*10,0.1+i*0.05,0.5);
    g.motion(5,0.9,0.8);
    for (int i=0;i<10;i++) assert(g.up(i,4300+i*10)==G::None);
    for (int i=0;i<8;i++) g.down(i,5000+i*10,0.1+i*0.05,0.5);
    for (int i=0;i<8;i++) assert(g.up(i,5900+i*10)==G::None);
    // Late extra contacts must not reset the age of an already-held gesture.
    g.down(0,7000,0.2,0.5);
    for (int i=1;i<4;i++) g.down(i,7800+i*10,0.2+i*0.05,0.5);
    for (int i=0;i<4;i++) assert(g.up(i,7900+i*10)==G::None);

    // Three-finger swipes, in each direction; one stray finger is not a swipe.
    auto swipe=[&](double dx,double dy){
        for (int i=0;i<3;i++) g.down(i,9000,0.3+i*0.1,0.5);
        for (int i=0;i<3;i++) g.motion(i,0.3+i*0.1+dx,0.5+dy);
        assert(g.claimed());
        G r=G::None; for (int i=0;i<3;i++) r=g.up(i,9400); return r;
    };
    assert(swipe(0.15,0)==G::SwipeRight); assert(swipe(-0.15,0)==G::SwipeLeft);
    assert(swipe(0,0.15)==G::SwipeDown); assert(swipe(0,-0.15)==G::SwipeUp);
    assert(swipe(0.05,0)==G::None); assert(swipe(0.12,0.12)==G::None);
    for (int i=0;i<3;i++) g.down(i,9500,0.3+i*0.1,0.5);
    g.motion(0,0.8,0.5); for (int i=0;i<3;i++) g.up(i,9700);  // mean 0.17 but two fingers still
    for (int i=0;i<3;i++) g.down(i,9800,0.3+i*0.1,0.5);
    g.motion(0,0.8,0.5); G stray=G::None; for (int i=0;i<3;i++) stray=g.up(i,9900); assert(stray==G::None);
    // Slow swipe is a drag, not a gesture.
    assert([&]{ for (int i=0;i<3;i++) g.down(i,10000,0.3+i*0.1,0.5); for (int i=0;i<3;i++) g.motion(i,0.5+i*0.1,0.5); G r=G::None; for (int i=0;i<3;i++) r=g.up(i,12000); return r; }()==G::None);

    // Five-finger pinch opens the overview; spreading or holding still does not.
    auto pinch=[&](int n,double scale){
        const double cx=0.5, cy=0.5;
        for (int i=0;i<n;i++) g.down(i,20000+i*10,cx+0.2*std::cos(i*6.283/n),cy+0.2*std::sin(i*6.283/n));
        assert(g.claimed()==(n<=6));
        for (int i=0;i<n;i++) g.motion(i,cx+0.2*scale*std::cos(i*6.283/n),cy+0.2*scale*std::sin(i*6.283/n));
        G r=G::None; for (int i=0;i<n;i++) r=g.up(i,20600+i*10); return r;
    };
    assert(pinch(5,0.4)==G::Overview); assert(pinch(4,0.5)==G::Overview);
    assert(pinch(5,0.8)==G::None); assert(pinch(5,1.5)==G::None); assert(pinch(8,0.3)==G::None);
    g.down(0,30000,0.2,0.2); assert(!g.claimed()); g.up(0,30010);
}
