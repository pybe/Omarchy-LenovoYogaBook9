import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Window overview for touch: every window as a live thumbnail on the upper
// panel. Tap a card to go to that window, the cross to close it, empty space or
// the gesture again to leave. Reads Hyprland's window list; commands go through
// `hyprctl eval` because `hyprctl dispatch` does not exist under the Lua config.
PanelWindow {
    id: overview
    property bool opened: false
    function toggle() { if (opened) opened=false; else { Hyprland.refreshToplevels(); opened=true; } }

    screen: Quickshell.screens.find(s => s.name === "eDP-1") ?? null
    visible: opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "#e6101722"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "yoga-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Minimised windows live on special:minimized-* workspaces (minimize.lua) and
    // are shown too; other special workspaces (scratchpad) are not windows you left.
    readonly property var windows: Hyprland.toplevels.values.filter(t => {
        const ws = t.workspace ? t.workspace.name : "";
        return !ws.startsWith("special:") || ws.startsWith("special:minimized-");
    })

    Process { id: hypr }
    function run(lua) { hypr.command = ["hyprctl", "eval", lua]; hypr.running = true; }
    function address(t) { return "address:0x" + t.address; }
    function activate(t) {
        const ws = t.workspace ? t.workspace.name : "";
        opened = false;
        // A minimised window comes back to the upper panel's current desktop first.
        if (ws.startsWith("special:minimized-"))
            run(`local w=hl.get_active_workspace("eDP-1") hl.dispatch(hl.dsp.window.move({ workspace = tostring(w.id), window = "${address(t)}", follow = false })) hl.dispatch(hl.dsp.focus({ window = "${address(t)}" }))`);
        else
            run(`hl.dispatch(hl.dsp.focus({ window = "${address(t)}" }))`);
    }
    function close(t) { run(`hl.dispatch(hl.dsp.window.close({ window = "${address(t)}" }))`); }

    Item {
        anchors.fill: parent
        focus: overview.opened
        Keys.onEscapePressed: overview.opened = false

        MouseArea { anchors.fill: parent; onClicked: overview.opened = false }

        Text {
            anchors.centerIn: parent
            visible: overview.windows.length === 0
            text: "Нет открытых окон"
            color: "#cdd6f4"; font.pixelSize: 22
        }

        GridView {
            id: grid
            // Sized from the screen, not from the grid, or height and columns feed each other.
            readonly property real areaWidth: parent.width - 64
            readonly property real areaHeight: parent.height - 64
            readonly property int columns: Math.max(1, Math.ceil(Math.sqrt(count * areaWidth / Math.max(1, areaHeight))))
            readonly property int rows: Math.max(1, Math.ceil(count / columns))
            width: areaWidth
            height: Math.min(areaHeight, cellHeight * rows)
            anchors.centerIn: parent
            cellWidth: areaWidth / columns
            cellHeight: Math.min(cellWidth * 0.75, areaHeight / rows)
            interactive: contentHeight > height
            model: overview.windows

            delegate: Item {
                id: card
                required property var modelData
                width: grid.cellWidth; height: grid.cellHeight

                Rectangle {
                    anchors.fill: parent; anchors.margins: 12
                    radius: 10; color: "#1e1e2e"
                    border.width: 2; border.color: modelData.activated ? "#89b4fa" : "#45475a"

                    Text {
                        id: title
                        anchors { left: parent.left; right: shut.left; top: parent.top; margins: 10 }
                        text: card.modelData.title || "—"
                        elide: Text.ElideRight; color: "#cdd6f4"; font.pixelSize: 15
                    }

                    ScreencopyView {
                        anchors { left: parent.left; right: parent.right; top: title.bottom; bottom: parent.bottom; margins: 10 }
                        captureSource: overview.opened ? card.modelData.wayland : null
                        live: true
                    }

                    MouseArea { anchors.fill: parent; onClicked: overview.activate(card.modelData) }

                    Rectangle {
                        id: shut
                        width: 40; height: 40; radius: 20
                        anchors { right: parent.right; top: parent.top; margins: 4 }
                        color: shutArea.pressed ? "#f38ba8" : "#e06c75"
                        Text { anchors.centerIn: parent; text: "✕"; color: "#1e1e2e"; font.pixelSize: 20 }
                        MouseArea { id: shutArea; anchors.fill: parent; onClicked: overview.close(card.modelData) }
                    }
                }
            }
        }
    }
}
