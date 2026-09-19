#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/devices/ITouch.hpp>
#include <hyprland/src/version.h>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <spawn.h>
#include <cstdlib>
#include <stdexcept>
#include <format>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include "gesture.hpp"

extern char **environ;
static TouchGestures recognizer;
static bool claimed = false;
static std::unordered_map<int32_t, PHLLSREF> panelTouches;

// Deliver panel touches without Hyprland's normal touchscreen refocus. Pointer
// focus must stay at the virtual mouse position, not follow the user's finger.
static void consume(Event::SCallbackInfo& info) {
    info.cancelled = true;
    g_pInputManager->m_lastInputTouch = false;
}
// Fixed executable and arguments; no shell or input-derived command text.
static void runPanel(const char* verb) {
    const char* home = std::getenv("HOME");
    if (!home) return;
    std::string executable = std::string(home) + "/.local/bin/yoga-panel";
    std::string argument = verb;
    char* args[]={executable.data(),argument.data(),nullptr};
    pid_t child;
    posix_spawn(&child,executable.c_str(),nullptr,nullptr,args,environ);
}

static void resetGesture() { recognizer.reset(); claimed = false; }
// Once several fingers are clearly a gesture, take the contact away from the app
// under them, so a swipe does not also scroll or draw there.
static void claim(Event::SCallbackInfo& info) {
    if (!claimed && recognizer.claimed()) {
        claimed = true;
        g_pSeatManager->sendTouchCancel();
        g_pSeatManager->sendTouchFrame();
    }
    if (claimed) consume(info);
}
static void down(ITouch::SDownEvent event, Event::SCallbackInfo& info) {
    const std::string output = event.device ? event.device->m_boundOutput : "";
    if (g_pSessionLockManager->isSessionLocked() || (output != "eDP-1" && output != "eDP-2")) { resetGesture(); return; }
    {
        auto monitor = State::monitorState()->query().name(output).run();
        if (monitor) {
            const auto global = monitor->m_position + event.pos * monitor->m_size;
            for (const auto& weak : monitor->m_layerSurfaceLayers[3]) {
                auto layer = weak.lock();
                if (!layer || !layer->m_mapped || layer->m_namespace != "yoga-input-panel" ||
                    !layer->m_geometry.containsPoint(global) || !layer->resource()) continue;
                panelTouches[event.touchID] = layer;
                resetGesture();
                consume(info);
                g_pSeatManager->sendTouchDown(layer->resource(), event.timeMs, event.touchID, global - layer->m_geometry.pos());
                return;
            }
        }
    }
    recognizer.down(event.touchID,event.timeMs,event.pos.x,event.pos.y);
    claim(info);
}
static void motion(ITouch::SMotionEvent event, Event::SCallbackInfo& info) {
    if (auto it = panelTouches.find(event.touchID); it != panelTouches.end()) {
        consume(info);
        auto layer = it->second.lock();
        if (layer && layer->m_mapped && !g_pSessionLockManager->isSessionLocked()) {
            auto monitor = layer->m_monitor.lock();
            if (monitor)
                g_pSeatManager->sendTouchMotion(event.timeMs, event.touchID,
                    monitor->m_position + event.pos * monitor->m_size - layer->m_geometry.pos());
        }
        return;
    }
    if (!recognizer.tracking(event.touchID)) return;
    recognizer.motion(event.touchID,event.pos.x,event.pos.y);
    claim(info);
}
static void up(ITouch::SUpEvent event, Event::SCallbackInfo& info) {
    if (panelTouches.erase(event.touchID)) {
        consume(info);
        g_pSeatManager->sendTouchUp(event.timeMs, event.touchID);
        return;
    }
    if (g_pSessionLockManager->isSessionLocked()) { resetGesture(); return; }
    if (!recognizer.tracking(event.touchID)) return;
    if (claimed) consume(info);
    const Gesture gesture = recognizer.up(event.touchID,event.timeMs);
    if (recognizer.idle()) claimed = false;
    const char* name = nullptr;
    switch (gesture) {
        case Gesture::OpenPanel: name = "show"; break;
        case Gesture::SwipeLeft: name = "previous"; break;
        case Gesture::SwipeRight: name = "next"; break;
        case Gesture::SwipeDown: name = "minimize"; break;
        case Gesture::SwipeUp: name = "restore"; break;
        case Gesture::Overview: name = "overview"; break;
        case Gesture::None: return;
    }
    if (gesture == Gesture::OpenPanel) { runPanel("show"); return; }
    const char* home = std::getenv("HOME");
    if (!home) return;
    std::string executable = std::string(home) + "/.local/bin/yoga-panel";
    std::string verb = "gesture";
    std::string argument = name;
    char* args[]={executable.data(),verb.data(),argument.data(),nullptr};
    pid_t child;
    posix_spawn(&child,executable.c_str(),nullptr,nullptr,args,environ);
}
static void cancel(ITouch::SCancelEvent event, Event::SCallbackInfo&) {
    panelTouches.erase(event.touchID);
    resetGesture();
}
// Tablet mode has no keyboard panel below, so bring the on-screen keyboard up on
// the upper panel while an app has a text field active, and put it away after.
// Hyprland has no event for text-input enable, hence a light poll; it acts only
// with eDP-2 off, and only ever hides a keyboard it showed itself.
static SP<CEventLoopTimer> textInputTimer;
static bool autoShown = false;
static int idlePolls = 0;
static void pollTextInput(SP<CEventLoopTimer> self, void*) {
    bool lowerOn = false;
    for (const auto& monitor : State::monitorState()->monitors())
        if (monitor->m_name == "eDP-2" && monitor->m_enabled) lowerOn = true;
    const auto input = g_pInputManager->m_relay.getFocusedTextInput();
    const bool wanted = !lowerOn && !g_pSessionLockManager->isSessionLocked() && input && input->isEnabled();
    if (wanted) {
        idlePolls = 0;
        if (!autoShown) { autoShown = true; runPanel("show"); }
    } else if (autoShown && ++idlePolls >= 3) {
        // A field briefly disabled while a page re-renders must not flicker the keyboard.
        autoShown = false; idlePolls = 0;
        if (!lowerOn) runPanel("hide");
    }
    self->updateTimeout(std::chrono::milliseconds(200));
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("Yoga gesture: Hyprland version mismatch; rebuild first");
    static auto a=Event::bus()->m_events.input.touch.down.listen(down);
    static auto b=Event::bus()->m_events.input.touch.motion.listen(motion);
    static auto c=Event::bus()->m_events.input.touch.up.listen(up);
    static auto d=Event::bus()->m_events.input.touch.cancel.listen(cancel);
    textInputTimer = makeShared<CEventLoopTimer>(std::chrono::milliseconds(200), pollTextInput, nullptr);
    g_pEventLoopManager->addTimer(textInputTimer);
    // Changing the touch route mid-session must not leave Qt tracking fingers
    // from the previous route (it can otherwise ignore new touch updates).
    if (auto monitor = State::monitorState()->query().name("eDP-2").run()) {
        for (const auto& weak : monitor->m_layerSurfaceLayers[3]) {
            auto layer = weak.lock();
            if (layer && layer->m_mapped && layer->m_namespace == "yoga-input-panel") {
                g_pSeatManager->sendTouchCancel();
                g_pSeatManager->sendTouchFrame();
                break;
            }
        }
    }
    HyprlandAPI::registerHyprCtlCommand(handle, {"yoga-gesture-last", true, [](eHyprCtlOutputFormat, std::string) -> std::string {
        const auto& l = recognizer.last;
        return std::format("fingers={} moved={} ms={} pinch_ratio={:.2f}", l.peak, l.moved, l.age, l.pinch);
    }});
#ifdef YOGA_PANEL_TESTING
    HyprlandAPI::registerHyprCtlCommand(handle, {"yoga-panel-test-touch", false, [](eHyprCtlOutputFormat, std::string request) -> std::string {
        const auto action = request.substr(request.find(' ') + 1);
        // Bounded integration probe: one synthetic finger in the pad centre.
        constexpr int id = 4095;
        if (action == "down") {
            for (const auto& device : g_pInputManager->m_touches) {
                if (device->m_boundOutput != "eDP-2") continue;
                g_pInputManager->onTouchDown({.timeMs=1000,.touchID=id,.pos={0.5,0.75},.device=device});
                g_pSeatManager->sendTouchFrame();
                return "ok";
            }
        } else if (action == "move") {
            g_pInputManager->onTouchMove({.timeMs=1050,.touchID=id,.pos={0.55,0.75}});
            g_pSeatManager->sendTouchFrame();
            return "ok";
        } else if (action == "up") {
            g_pInputManager->onTouchUp({.timeMs=1500,.touchID=id});
            g_pSeatManager->sendTouchFrame();
            return "ok";
        }
        return "Expected down/move/up and lower touchscreen";
    }});
#endif
    return {"yoga-panel-gesture","Yoga panel touch routing and multi-finger touchscreen gestures","local","0.4.0"};
}
APICALL EXPORT void PLUGIN_EXIT() {
    if (textInputTimer) { g_pEventLoopManager->removeTimer(textInputTimer); textInputTimer.reset(); }
    for (const auto& [id, layer] : panelTouches) g_pSeatManager->sendTouchUp(0, id);
    if (!panelTouches.empty()) g_pSeatManager->sendTouchFrame();
    panelTouches.clear();
    recognizer.reset();
}
