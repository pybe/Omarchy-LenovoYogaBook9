#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>

// Multi-finger touchscreen gestures, in the monitor's normalised logical space.
// Observes touches; the caller decides when claimed() takes them from the app.
//   3-finger short stationary tap, or 8-10 fingers   -> OpenPanel
//   3-finger swipe                                   -> Swipe{Left,Right,Up,Down}
//   4-6 finger pinch (fingers drawn together)        -> Overview
enum class Gesture { None, OpenPanel, SwipeLeft, SwipeRight, SwipeUp, SwipeDown, Overview };

class TouchGestures {
    struct Finger { double x0, y0, x, y; };
    std::unordered_map<int, Finger> fingers, lifted;
    uint32_t started = 0;
    unsigned peak = 0;
    bool moved = false;
    double spread0 = 0, spreadMin = 0;

    static constexpr double TAP_SLOP = 0.025;
    static constexpr double SWIPE_MIN = 0.08;     // mean travel along the axis
    static constexpr double SWIPE_EACH = 0.03;    // every finger must agree, so one stray finger is not a swipe
    static constexpr double PINCH_RATIO = 0.6;    // spread shrinks to 60% of where it started

    double spread() const {
        double cx=0, cy=0, sum=0;
        for (auto& [id,f] : fingers) { cx+=f.x; cy+=f.y; }
        cx/=fingers.size(); cy/=fingers.size();
        for (auto& [id,f] : fingers) sum+=std::hypot(f.x-cx,f.y-cy);
        return sum/fingers.size();
    }
    Gesture swipe() const {
        if (peak!=3 || lifted.size()!=3) return Gesture::None;
        double dx=0, dy=0;
        for (auto& [id,f] : lifted) { dx+=f.x-f.x0; dy+=f.y-f.y0; }
        dx/=3; dy/=3;
        bool horizontal=std::abs(dx)>=SWIPE_MIN && std::abs(dx)>std::abs(dy)*1.5;
        bool vertical=std::abs(dy)>=SWIPE_MIN && std::abs(dy)>std::abs(dx)*1.5;
        if (!horizontal && !vertical) return Gesture::None;
        for (auto& [id,f] : lifted) {
            double d=horizontal ? f.x-f.x0 : f.y-f.y0;
            if (d*(horizontal ? dx : dy)<=0 || std::abs(d)<SWIPE_EACH) return Gesture::None;
        }
        if (horizontal) return dx>0 ? Gesture::SwipeRight : Gesture::SwipeLeft;
        return dy>0 ? Gesture::SwipeDown : Gesture::SwipeUp;
    }
public:
    // The last completed contact, for `hyprctl yoga-gesture-last` when a gesture is missed.
    struct Summary { unsigned peak; bool moved; uint32_t age; double pinch; } last{};
    void reset() { fingers.clear(); lifted.clear(); peak=0; moved=false; spread0=spreadMin=0; }
    void down(int id, uint32_t time, double x, double y) {
        if (fingers.empty()) { reset(); started=time; }
        fingers[id]={x,y,x,y}; peak=std::max(peak,unsigned(fingers.size()));
        // Spread is measured from the moment the last finger lands.
        if (fingers.size()==peak && peak>=4) spread0=spreadMin=spread();
    }
    void motion(int id, double x, double y) {
        auto p=fingers.find(id);
        if (p==fingers.end()) return;
        p->second.x=x; p->second.y=y;
        if (std::hypot(x-p->second.x0,y-p->second.y0)>TAP_SLOP) moved=true;
        if (fingers.size()==peak && peak>=4) spreadMin=std::min(spreadMin,spread());
    }
    // A moving 3-finger or 4+ finger contact is a gesture, not app input.
    bool claimed() const { return (peak==3 && moved) || (peak>=4 && peak<=6); }
    bool tracking(int id) const { return fingers.count(id); }
    bool idle() const { return fingers.empty(); }
    Gesture up(int id, uint32_t time) {
        auto p=fingers.find(id);
        if (p==fingers.end()) return Gesture::None;
        lifted[id]=p->second; fingers.erase(p);
        if (!fingers.empty()) return Gesture::None;
        Gesture result=Gesture::None;
        bool many=peak>=8 && peak<=10;
        uint32_t age=time-started;
        last={peak,moved,age,spread0>0 ? spreadMin/spread0 : 0};
        if ((peak==3 || many) && !moved && age<=(many ? 800u : 500u)) result=Gesture::OpenPanel;
        else if (peak==3 && moved && age<=1500) result=swipe();
        else if (peak>=4 && peak<=6 && spread0>0 && spreadMin<=spread0*PINCH_RATIO && age<=2000) result=Gesture::Overview;
        reset(); return result;
    }
};
