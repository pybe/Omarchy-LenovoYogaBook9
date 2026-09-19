import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

ColumnLayout {
    id: row
    property string label
    property real value
    property real minimum
    property real maximum
    property real step
    property string displayValue: value.toFixed(2)
    signal adjusted(real value)
    Layout.fillWidth: true
    Layout.preferredHeight: 62; Layout.minimumHeight: 62; Layout.maximumHeight: 62
    spacing: 6
    function change(delta) { adjusted(Math.max(minimum,Math.min(maximum,Math.round((value+delta)*100)/100))); }
    RowLayout {
        Layout.fillWidth: true
        Text { text: row.label; color: Theme.text; font.pixelSize: 14; Layout.fillWidth: true }
        Text { text: row.displayValue; color: Theme.accent; font.pixelSize: 14; font.weight: Font.DemiBold }
    }
    RowLayout {
        Layout.fillWidth: true; Layout.preferredHeight: 34; Layout.minimumHeight: 34; Layout.maximumHeight: 34; spacing: 9
        Key { label: "−"; textSize: 21; radius: 8; repeatable: true; Layout.preferredWidth: 34; Layout.fillHeight: true; onActivated: row.change(-row.step) }
        Controls.Slider {
            id: slider
            objectName: "settingsSlider"
            implicitHeight: 34
            Layout.fillHeight: true
            Layout.fillWidth: true; Layout.minimumWidth: 40
            from: row.minimum; to: row.maximum; stepSize: row.step; value: row.value
            onMoved: row.adjusted(Math.round(value*100)/100)
            background: Rectangle {
                x: slider.leftPadding; y: slider.topPadding+slider.availableHeight/2-height/2
                width: slider.availableWidth; height: 4; radius: 2; color: Theme.track
                Rectangle { width: slider.visualPosition*parent.width; height: parent.height; radius: 2; color: Theme.trackFill }
            }
            handle: Rectangle {
                x: slider.leftPadding+slider.visualPosition*(slider.availableWidth-width)
                y: slider.topPadding+slider.availableHeight/2-height/2
                width: 20; height: 20; radius: 10
                color: slider.pressed ? Theme.text : Theme.knob; border.color: Theme.trackFill; border.width: 2
            }
        }
        Key { label: "+"; textSize: 21; radius: 8; repeatable: true; Layout.preferredWidth: 34; Layout.fillHeight: true; onActivated: row.change(row.step) }
    }
}
