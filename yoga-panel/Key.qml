import QtQuick

Rectangle {
    id: key
    property string label: ""
    property real textSize: label.length > 3 ? 17 : 24
    property bool selected: false
    property bool repeatable: false
    property bool activateOnRelease: false
    property bool down: false
    signal activated()
    onVisibleChanged: if (!visible) reset()
    radius: 11
    color: down ? Theme.keyDown : selected ? Theme.keySelected : Theme.key
    border.color: down || selected ? Theme.keyActiveBorder : Theme.keyBorder
    border.width: 1
    Text {
        anchors.fill: parent
        anchors.margins: 6
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: key.label
        color: Theme.text
        font.pixelSize: key.textSize
        font.weight: Font.Medium
    }
    TapHandler {
        // Holding a repeat key tolerates drift within its entire surface.
        gesturePolicy: key.repeatable ? TapHandler.WithinBounds : key.activateOnRelease ? TapHandler.DragThreshold : TapHandler.ReleaseWithinBounds
        acceptedButtons: Qt.LeftButton
        onPressedChanged: {
            if (pressed) {
                key.down = true;
                if (!key.activateOnRelease) key.activated();
                if (key.repeatable) delay.restart();
            } else key.reset();
        }
        onTapped: if (key.activateOnRelease) key.activated()
        onCanceled: key.reset()
    }
    function reset() { down = false; delay.stop(); repeater.stop(); }
    Timer { id: delay; interval: 420; onTriggered: repeater.start() }
    Timer { id: repeater; interval: 65; repeat: true; onTriggered: key.activated() }
}
