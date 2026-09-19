import QtQuick
import "KeyboardLayout.js" as Layouts

Key {
    id: key
    required property var symbols
    property bool russianActive: true
    property bool shifted: false
    property bool caps: false
    readonly property string character: Layouts.character(symbols,russianActive,shifted,caps)
    readonly property bool dual: symbols.en !== symbols.ru
    radius: 8
    Text {
        visible: key.dual
        anchors.left: parent.left; anchors.top: parent.top
        anchors.leftMargin: 13; anchors.topMargin: 7
        text: key.symbols.en.toUpperCase()
        color: key.russianActive ? Theme.textDim : Theme.text
        font.pixelSize: 25; font.weight: Font.Medium
    }
    Text {
        visible: key.dual
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.rightMargin: 13; anchors.bottomMargin: 7
        text: key.symbols.ru.toUpperCase()
        color: key.russianActive ? Theme.accent : Theme.accentDim
        font.pixelSize: 25; font.weight: Font.Medium
    }
    Text {
        visible: !key.dual
        anchors.left: parent.left; anchors.bottom: parent.bottom
        anchors.leftMargin: 16; anchors.bottomMargin: 9
        text: key.symbols.en
        color: Theme.text; font.pixelSize: 32; font.weight: Font.Medium
    }
    Text {
        visible: !/^[a-z]$/i.test(key.symbols.en)
        anchors.right: parent.right; anchors.top: parent.top
        anchors.rightMargin: 10; anchors.topMargin: 5
        text: key.russianActive ? key.symbols.ruShift : key.symbols.enShift
        color: key.shifted ? Theme.text : Theme.textDim; font.pixelSize: 21
    }
}
