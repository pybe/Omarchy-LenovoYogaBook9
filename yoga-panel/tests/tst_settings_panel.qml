import QtQuick
import QtTest
import ".."

TestCase {
    name: "SettingsPanel"
    visible: true; when: windowShown
    width: 1408; height: 420
    QtObject {
        id: values
        property real pointerSpeed: 2.4
        property real pointerAccel: .4
        property real scrollSpeed: .09
        property bool inertiaEnabled: true
        property real inertiaStrength: .65
        property real inertiaDuration: 650
        property bool predictionEnabled: false
        property bool autocorrectEnabled: true
    }
    Rectangle { anchors.fill: parent; color: "#101722" }
    PanelSettings { id: panel; anchors.fill: parent; settings: values }
    function test_render() {
        wait(100);
        compare(panel.height,420);
        grabImage(this).save("/tmp/yoga-settings-preview.png");
    }
}
