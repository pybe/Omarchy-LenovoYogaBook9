import QtQuick
import QtQuick.Layouts

RowLayout {
    id: row
    property string label
    property real value
    property real minimum
    property real maximum
    property real step
    signal adjusted(real value)
    Layout.fillWidth: true
    Layout.preferredHeight: 54
    spacing: 15
    Text { text: row.label; color: "#e3edff"; font.pixelSize: 20; Layout.fillWidth: true }
    Key { label: "−"; repeatable: true; Layout.preferredWidth: 80; Layout.fillHeight: true; onActivated: row.adjusted(Math.max(row.minimum,Math.round((row.value-row.step)*100)/100)) }
    Text { text: row.value.toFixed(2); color: "#f0f5ff"; font.pixelSize: 22; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 85 }
    Key { label: "+"; repeatable: true; Layout.preferredWidth: 80; Layout.fillHeight: true; onActivated: row.adjusted(Math.min(row.maximum,Math.round((row.value+row.step)*100)/100)) }
}
