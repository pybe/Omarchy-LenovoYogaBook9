import QtQuick
import Quickshell
import Quickshell.Wayland
PanelWindow {
    screen: Quickshell.screens.find(s => s.name === "eDP-1") ?? null
    implicitWidth: 500
    implicitHeight: 130
    color: "#1a2738"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "yoga-input-test"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    Column {
        anchors.centerIn: parent
        spacing: 16
        Text { text: "Проверка ввода Yoga — закроется автоматически"; color: "white" }
        TextInput {
            width: 450; height: 40; color: "white"; font.pixelSize: 24; focus: true
            Component.onCompleted: forceActiveFocus()
            onTextChanged: console.log("INPUT_TEST:" + text)
        }
    }
    Timer { interval: 90000; running: true; onTriggered: Qt.quit() }
}
