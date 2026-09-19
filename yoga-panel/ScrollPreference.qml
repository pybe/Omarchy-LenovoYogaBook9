import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

RowLayout {
    id: row
    property real value: 0.18
    signal adjusted(real value)
    Layout.fillWidth: true
    Layout.preferredHeight: 54
    spacing: 12
    function adjust(amount) { adjusted(Math.max(0.03,Math.min(1,Math.round((value+amount)*100)/100))); }
    Text { text: "Скорость прокрутки"; color: "#e3edff"; font.pixelSize: 20; Layout.preferredWidth: 245 }
    Key { label: "−"; repeatable: true; Layout.preferredWidth: 60; Layout.fillHeight: true; onActivated: row.adjust(-0.01) }
    Controls.Slider {
        id: slider
        objectName: "scrollSpeedSlider"
        Layout.fillWidth: true; Layout.minimumWidth: 180
        from: 0.03; to: 1; stepSize: 0.01
        value: row.value
        onMoved: row.adjusted(Math.round(value*100)/100)
    }
    Text { text: Math.round(row.value/0.18*100)+"%"; color: "#f0f5ff"; font.pixelSize: 22; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 85 }
    Key { label: "+"; repeatable: true; Layout.preferredWidth: 60; Layout.fillHeight: true; onActivated: row.adjust(0.01) }
}
