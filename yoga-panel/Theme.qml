pragma Singleton
import QtQuick

// Colour tokens for every panel surface. `oled` swaps the blue-grey palette for
// pure black fills with thin outlines: on the OLED lower panel a black pixel is
// an unlit pixel, so the keyboard stops burning power while it sits open.
QtObject {
    property bool oled: false
    readonly property color background: oled ? "#000000" : "#101722"
    readonly property color surface: oled ? "#000000" : "#151f2c"
    readonly property color surfaceBorder: oled ? "#2a2a2a" : "#344356"
    readonly property color key: oled ? "#000000" : "#202a38"
    readonly property color keyBorder: oled ? "#3a3a3a" : "#384658"
    readonly property color keyDown: oled ? "#1c1c1c" : "#446b96"
    readonly property color keySelected: oled ? "#000000" : "#284e75"
    readonly property color keyActiveBorder: oled ? "#c8c8c8" : "#87bcf5"
    readonly property color text: oled ? "#d8d8d8" : "#f0f5ff"
    readonly property color textDim: oled ? "#6a6a6a" : "#8190a5"
    readonly property color textMuted: oled ? "#5a5a5a" : "#8296ae"
    readonly property color accent: oled ? "#e0e0e0" : "#a5d6ff"
    readonly property color accentDim: oled ? "#4a4a4a" : "#617d99"
    readonly property color card: oled ? "#000000" : "#182230"
    readonly property color cardBorder: oled ? "#2a2a2a" : "#2d3d51"
    readonly property color track: oled ? "#2a2a2a" : "#304057"
    readonly property color trackFill: oled ? "#a0a0a0" : "#79bfff"
    readonly property color knob: oled ? "#d8d8d8" : "#bbdfff"
    readonly property color mic: oled ? "#000000" : "#ad3848"
    readonly property color micBorder: oled ? "#ff9da9" : "#ff9da9"
}
