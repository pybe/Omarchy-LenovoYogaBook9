import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

RowLayout {
    id: row
    property string label
    property bool checked
    signal toggled(bool value)
    Layout.fillWidth: true; Layout.preferredHeight: 38; Layout.minimumHeight: 38; Layout.maximumHeight: 38
    Text { text: row.label; color: Theme.text; font.pixelSize: 14; Layout.fillWidth: true }
    Controls.Switch {
        id: toggle
        checked: row.checked
        onToggled: row.toggled(checked)
        implicitWidth: 54; implicitHeight: 34
        padding: 0
        indicator: Rectangle {
            width: 50; height: 28; y: 3; radius: 14
            color: toggle.checked ? Theme.trackFill : Theme.track
            Rectangle {
                x: toggle.checked ? 25 : 3; y: 3; width: 22; height: 22; radius: 11; color: Theme.knob
                Behavior on x { NumberAnimation { duration: 100 } }
            }
        }
    }
}
