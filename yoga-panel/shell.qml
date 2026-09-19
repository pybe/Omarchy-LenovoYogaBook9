import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "KeyboardLayout.js" as Layouts

ShellRoot {
    id: root
    property bool opened: false
    property bool russian: true
    property bool languagePending: false
    property int languageRequest: 0
    property string keyboardLanguage: ""
    Timer { id: languageGuard; interval: 1500; onTriggered: root.languagePending=false }
    property bool shift: false
    // A held modifier key (Shift, Ctrl, Alt, Super) applies to every key typed
    // until it is released; a tap stays one-shot.
    property var held: ({})
    property var used: ({})
    property bool caps: false
    property bool control: false
    property bool alt: false
    property bool logo: false
    property bool voiceSession: false
    property bool voiceRussian: true
    property bool voiceSawBusy: false
    property string voiceState: "idle"
    function finishVoice() {
        if (!voiceSession) return;
        voiceSession=false; voiceSawBusy=false;
        russian=voiceRussian;
        clearWord();
        requestLanguage();
        status="Готово";
    }
    Timer { id: voiceSettled; interval: 350; onTriggered: root.finishVoice() }
    Process {
        id: voiceMonitor
        command: ["voxtype","status","--follow","--format","json"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    let state=JSON.parse(data).class;
                    root.voiceState=state;
                    if (!root.voiceSession) return;
                    if (state==="recording" || state==="transcribing" || state==="processing") {
                        root.voiceSawBusy=true; voiceSettled.stop();
                        root.status=state==="recording" ? "Говори…" : "Распознаю…";
                    } else if (state==="idle" && root.voiceSawBusy && !micKey.holding) voiceSettled.restart();
                } catch (e) {}
            }
        }
    }
    property bool drag: false
    property bool settingsOpen: false
    property bool settingsLoaded: false
    property bool predictionEnabled: false
    property bool autocorrectEnabled: true
    onAutocorrectEnabledChanged: { clearWord(); if (settingsLoaded) saveSettings.restart(); }
    property string wordPrefix: ""
    property var suggestions: []
    property int predictionRequest: 0
    property real lastTypedAt: 0
    onRussianChanged: clearWord()
    onPredictionEnabledChanged: { clearWord(); if (settingsLoaded) saveSettings.restart(); }
    property real pointerSpeed: 2.4
    property real pointerAccel: 0.1
    property real scrollSpeed: 0.9
    property bool inertiaEnabled: true
    property bool oledTheme: false
    onOledThemeChanged: { Theme.oled=oledTheme; if (settingsLoaded) saveSettings.restart(); }
    property real inertiaStrength: 1.5
    property real inertiaDuration: 650
    onInertiaStrengthChanged: { pad.stopMomentum(); if (settingsLoaded) saveSettings.restart(); }
    onInertiaDurationChanged: { pad.stopMomentum(); if (settingsLoaded) saveSettings.restart(); }
    onInertiaEnabledChanged: { pad.stopMomentum(); if (settingsLoaded) saveSettings.restart(); }
    onPointerSpeedChanged: if (settingsLoaded) saveSettings.restart()
    onPointerAccelChanged: if (settingsLoaded) saveSettings.restart()
    onScrollSpeedChanged: { pad.stopMomentum(); pad.clearVelocity(); if (settingsLoaded) saveSettings.restart(); }
    Timer {
        id: saveSettings; interval: 350
        onTriggered: root.send({type:"settings",values:{pointerSpeed:root.pointerSpeed,pointerAccel:root.pointerAccel,scrollSpeed:root.scrollSpeed,predictionEnabled:root.predictionEnabled,autocorrectEnabled:root.autocorrectEnabled,inertiaEnabled:root.inertiaEnabled,oledTheme:root.oledTheme,inertiaStrength:root.inertiaStrength,inertiaDuration:root.inertiaDuration}})
    }
    property string status: "Подключение…"
    readonly property var bottom: Quickshell.screens.find(s => s.name === "eDP-2") ?? null
    // Tablet mode turns eDP-2 off; the keyboard then docks at the bottom of eDP-1
    // (without the touchpad) and the Hyprland plugin shows it for text fields.
    readonly property var upper: Quickshell.screens.find(s => s.name === "eDP-1") ?? null
    readonly property bool tablet: bottom === null && upper !== null
    readonly property string base: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "") + "/"

    function send(e) {
        if (!backend.running) { status = "Ошибка ввода — перезапусти панель"; return; }
        backend.write(JSON.stringify(e) + "\n");
    }
    Timer {
        id: predictTimer; interval: 65
        onTriggered: if (root.predictionEnabled && root.wordPrefix.length>=2)
            root.send({type:"suggest",prefix:root.wordPrefix,language:root.russian ? "ru" : "en",requestId:root.predictionRequest})
    }
    function clearWord(preserveUndo) {
        if (!preserveUndo) send({type:"resetWord"});
        wordPrefix=""; suggestions=[]; predictionRequest++;
    }
    function updateWord(char) {
        if (!predictionEnabled && !autocorrectEnabled) return;
        if (Date.now()-lastTypedAt>8000) clearWord(true);
        lastTypedAt=Date.now();
        if (/^[a-zа-яё]$/i.test(char)) {
            wordPrefix=(wordPrefix+char).slice(-64); suggestions=[]; predictionRequest++; predictTimer.restart();
        } else clearWord(true);
    }
    function completeWord(word) {
        if (!predictionEnabled || !wordPrefix || Date.now()-lastTypedAt>8000) { clearWord(); return; }
        let original=wordPrefix;
        let suffix=word.startsWith(original) ? word.slice(original.length)+" " : word+" ";
        clearWord();
        if (!word.startsWith(original)) for (let i=0;i<original.length;i++) send({type:"key",key:"BackSpace",mods:[]});
        for (let ch of suffix) send({type:"text",text:ch,mods:[]});
    }
    function toggleOverview() { overview.toggle(); }
    function requestLanguage() {
        languageRequest++; languagePending=true;
        keyboardLanguage=russian ? "ru" : "en";
        languageGuard.interval=1500; languageGuard.restart();
        send({type:"language",language:keyboardLanguage,requestId:languageRequest});
    }
    function acknowledgeLanguage(message) {
        if (message.requestId!==languageRequest) return;
        // Drain the compositor's per-device notifications from this command.
        languageGuard.interval=120; languageGuard.restart();
    }
    function applySystemLanguage(language) {
        if (voiceSession || languagePending) return;
        let target=language==="ru";
        if (russian!==target) { russian=target; shift=false; alt=false; }
        // Same-language notifications must not reset modifiers or echo g forever.
        if (keyboardLanguage!==language) {
            keyboardLanguage=language;
            send({type:"keyboardGroup",language:language});
        }
    }
    function switchLanguage() {
        russian=!russian; if (voiceSession) voiceRussian=russian; shift=false; alt=false; control=false; logo=false; clearWord();
        requestLanguage();
    }
    function toggleShift() { if (alt) switchLanguage(); else shift=!shift; }
    function toggleAlt() { if (shift) switchLanguage(); else alt=!alt; }
    function typeKey(key) {
        pad.stopMomentum();
        let mods = [];
        if (control) mods.push("ctrl");
        if (alt) mods.push("alt");
        if (logo) mods.push("logo");
        if (shift) mods.push("shift");
        send({type: "key", key: key, mods: mods});
        if (key==="BackSpace" && !mods.length && wordPrefix.length) {
            wordPrefix=wordPrefix.slice(0,-1); suggestions=[]; predictionRequest++; predictTimer.restart(); lastTypedAt=Date.now();
        } else clearWord(key==="BackSpace" && !mods.length);
        releaseMods();
    }
    function typeText(char) {
        pad.stopMomentum();
        if (Date.now()-lastTypedAt>8000) clearWord();
        let mods = [];
        if (control) mods.push("ctrl");
        if (alt) mods.push("alt");
        if (logo) mods.push("logo");
        if (shift && (logo || control || alt)) mods.push("shift");
        send({type: "text", text: char, mods: mods, autocorrect: autocorrectEnabled, language: russian ? "ru" : "en"});
        if (control || alt || logo) clearWord(); else updateWord(char);
        releaseMods();
    }
    function setMod(name, value) {
        if (name === "shift") shift = value;
        else if (name === "control") control = value;
        else if (name === "alt") alt = value;
        else if (name === "logo") logo = value;
    }
    function holdMod(name, down) {
        if (down) { held[name] = true; used[name] = false; return; }
        held[name] = false;
        if (used[name]) setMod(name, false);
        used[name] = false;
    }
    function releaseMods() {
        for (const name of ["shift", "control", "alt", "logo"]) {
            if (held[name]) used[name] = true; else setMod(name, false);
        }
    }
    function click(button) {
        clearWord();
        send({type:"button",button:button,state:1});
        send({type:"button",button:button,state:0});
    }
    function closePanel() {
        micKey.cancel();
        clearWord();
        pad.resetGesture();
        send({type:"release"}); drag = false; opened = false;
        shift = false; control = false; alt = false; logo = false;
    }
    Process {
        id: backend
        command: ["python3", root.base + "backend.py"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                if (data.startsWith("{")) {
                    try {
                        let s=JSON.parse(data).settings;
                        let message=JSON.parse(data);
                        if (message.focusChanged) { pad.stopMomentum(); micKey.cancel(); root.clearWord(); }
                        if (message.voice) {
                            if (message.voice==="error") {
                                micKey.holding=false; root.finishVoice(); root.status="Диктовка недоступна или занята";
                            } else if (message.voice==="idle") root.finishVoice();
                            else {
                                root.status=message.voice==="recording" ? "Говори…" : "Распознаю…";
                                if (message.voice==="processing" && root.voiceState==="idle" && root.voiceSawBusy) voiceSettled.restart();
                            }
                        }
                        if (message.languageAck) root.acknowledgeLanguage(message);
                        if (message.language) root.applySystemLanguage(message.language);
                        if (message.suggestions && root.predictionEnabled && message.requestId===root.predictionRequest && message.prefix===root.wordPrefix)
                            root.suggestions=message.suggestions;
                        if (s) {
                            root.settingsLoaded=false;
                            root.pointerSpeed=s.pointerSpeed; root.pointerAccel=s.pointerAccel; root.scrollSpeed=s.scrollSpeed; root.inertiaEnabled=s.inertiaEnabled ?? true;
                            root.inertiaStrength=s.inertiaStrength ?? 1.5; root.inertiaDuration=s.inertiaDuration ?? 650;
                            root.predictionEnabled=s.predictionEnabled ?? false;
                            root.autocorrectEnabled=s.autocorrectEnabled ?? true;
                            root.oledTheme=s.oledTheme ?? false;
                            root.settingsLoaded=true;
                        }
                    } catch(e) { root.status="Не удалось загрузить настройки"; }
                } else root.status = data === "ready" ? "Готово" : "Ошибка ввода — проверь журнал";
            }
        }
        stderr: SplitParser { onRead: data => console.warn(data) }
        onExited: root.status = "Служба ввода остановлена"
    }
    IpcHandler {
        target: "panel"
        function toggle(): void { if (root.opened) root.closePanel(); else root.opened = true; }
        function openPanel(): void { root.opened = true; }
        function hide(): void { root.closePanel(); }
        // Touchscreen gestures recognised by the Hyprland plugin; same actions as the pad's.
        function gesture(name: string): void {
            if (name === "previous" || name === "next") root.send({type:"workspace",direction:name});
            else if (name === "minimize" || name === "restore") root.send({type:"minimize",direction:name === "minimize" ? "down" : "up"});
            else if (name === "overview") root.toggleOverview();
        }
        function status(): string { return root.opened ? "open" : "closed"; }
        function predictionStatus(): string { return JSON.stringify({enabled:root.predictionEnabled,autocorrect:root.autocorrectEnabled,ready:root.suggestions.length,prefixLength:root.wordPrefix.length,requestId:root.predictionRequest,language:root.russian ? "ru" : "en"}); }
        function setWords(enabled: bool): void { root.predictionEnabled=enabled; }
        function testPrediction(): void { root.russian=true; root.predictionEnabled=true; root.clearWord(); root.typeText("п"); root.typeText("р"); root.typeText("и"); }
        function acceptFirstPrediction(): void { if (root.suggestions.length) root.completeWord(root.suggestions[0]); }
        function touchStatus(): string { return JSON.stringify({pressed:pad.pressEvents,updated:pad.updateEvents,samples:pad.samples,moves:pad.moveEvents,count:pad.previousCount,peak:pad.peakCount,histogram:pad.histogram}); }
        function testKeys(): void { let old=root.russian; root.russian=true; digitKeys.itemAt(1).activated(); letterKeys.itemAt(0).activated(); root.typeText(" "); root.russian=old; }
        function testCenters(): string {
            return JSON.stringify([digitKeys.itemAt(1), letterKeys.itemAt(0), spaceKey].map(k => k.mapToGlobal(k.width/2,k.height/2)));
        }
    }
    Overview { id: overview }
    PanelWindow {
        id: panel
        screen: root.tablet ? root.upper : root.bottom
        visible: (root.bottom !== null || root.tablet) && root.opened
        anchors { top: !root.tablet; bottom: true; left: true; right: true }
        // Keyboard rows are sized from the screen, not from this window, which in
        // tablet mode is only as tall as the keyboard itself.
        readonly property real areaHeight: screen ? screen.height : height
        implicitHeight: root.tablet ? keyboard.keyboardHeight + 32 + 10 + 24 : 0
        color: Theme.background
        // Docked in tablet mode, windows shrink above it so the text field stays visible.
        exclusionMode: root.tablet ? ExclusionMode.Auto : ExclusionMode.Ignore
        WlrLayershell.namespace: "yoga-input-panel"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            anchors.topMargin: 8
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                Layout.minimumHeight: 32
                Layout.maximumHeight: 32
                spacing: 6
                Text { text: "YOGA"; color: Theme.textDim; font.pixelSize: 13; font.letterSpacing: 1 }
                Item {
                    Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.fillHeight: true
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                        spacing: 7
                        Repeater {
                            model: root.predictionEnabled && !root.settingsOpen ? root.suggestions : []
                            Key { required property string modelData; Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 1; Layout.fillHeight: true; radius: 7; textSize: 15; label: modelData; onActivated: root.completeWord(modelData) }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: root.status!=="Готово" && (!root.predictionEnabled || !root.suggestions.length)
                        text: root.status; color: Theme.textMuted; font.pixelSize: 12
                    }
                }
                Key { Layout.preferredWidth: 80; Layout.minimumWidth: 80; Layout.maximumWidth: 80; Layout.fillHeight: true; radius: 7; textSize: 13; label: "Слова"; selected: root.predictionEnabled; onActivated: root.predictionEnabled=!root.predictionEnabled }
                Key { visible: !root.tablet; Layout.preferredWidth: 110; Layout.fillHeight: true; radius: 7; textSize: 13; label: root.settingsOpen ? "← Клавиатура" : "⚙ Настройки"; onActivated: { pad.resetGesture(); root.settingsOpen=!root.settingsOpen; } }
                Key { Layout.preferredWidth: 36; Layout.fillHeight: true; radius: 7; textSize: 17; label: "✕"; onActivated: root.closePanel() }
            }
            ColumnLayout {
                id: keyboard
                visible: !root.settingsOpen || root.tablet
                Layout.fillWidth: true
                Layout.preferredHeight: keyboardHeight
                Layout.maximumHeight: keyboardHeight
                Layout.minimumHeight: 280
                spacing: 7
                // Integer sizes: the layout engine rounds every preferred size UP, so a
                // fractional unit overflows the row by a pixel per key and the rows end
                // past the touchpad edge. The remainder goes to the last key of each row.
                readonly property int keyHeight: Math.floor((Math.min(380,panel.areaHeight*0.44)-28)/5)
                readonly property int keyboardHeight: keyHeight*5+28
                readonly property int unit: Math.floor((panel.width - 32 - 14*7)/15)
                Layout.minimumWidth: 0
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: keyboard.keyHeight; Layout.minimumHeight: keyboard.keyHeight; Layout.maximumHeight: keyboard.keyHeight; spacing: 7
                    Key { Layout.preferredWidth: keyboard.unit; Layout.fillHeight: true; label: "Esc"; onActivated: root.typeKey("Escape") }
                    Repeater {
                        id: digitKeys
                        model: Layouts.numbers
                        LetterKey { required property var modelData; symbols: modelData; russianActive: root.russian; shifted: root.shift; caps: root.caps; Layout.preferredWidth: keyboard.unit; Layout.fillHeight: true; onActivated: root.typeText(character) }
                    }
                    Key { Layout.preferredWidth: keyboard.unit; Layout.fillWidth: true; Layout.fillHeight: true; label: "⌫"; repeatable: true; onActivated: root.typeKey("BackSpace") }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: keyboard.keyHeight; Layout.minimumHeight: keyboard.keyHeight; Layout.maximumHeight: keyboard.keyHeight; spacing: 7
                    Key { Layout.preferredWidth: keyboard.unit*1.5+3.5; Layout.fillHeight: true; label: "Tab ⇥"; onActivated: root.typeKey("Tab") }
                    Repeater {
                        id: letterKeys
                        model: Layouts.upper
                        LetterKey { required property var modelData; symbols: modelData; russianActive: root.russian; shifted: root.shift; caps: root.caps; Layout.preferredWidth: keyboard.unit; Layout.fillHeight: true; onActivated: root.typeText(character) }
                    }
                    LetterKey { symbols: Layouts.pair("\\","\\","|","/"); russianActive: root.russian; shifted: root.shift; caps: root.caps; Layout.preferredWidth: keyboard.unit*1.5+3.5; Layout.fillWidth: true; Layout.fillHeight: true; onActivated: root.typeText(character) }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: keyboard.keyHeight; Layout.minimumHeight: keyboard.keyHeight; Layout.maximumHeight: keyboard.keyHeight; spacing: 7
                    Key { Layout.preferredWidth: keyboard.unit*1.75+5.25; Layout.fillHeight: true; label: "Caps ⇪"; selected: root.caps; onActivated: root.caps=!root.caps }
                    Repeater {
                        model: Layouts.middle
                        LetterKey { required property var modelData; symbols: modelData; russianActive: root.russian; shifted: root.shift; caps: root.caps; Layout.preferredWidth: keyboard.unit; Layout.fillHeight: true; onActivated: root.typeText(character) }
                    }
                    Key { Layout.preferredWidth: keyboard.unit*2.25+8.75; Layout.fillWidth: true; Layout.fillHeight: true; label: "Enter ↵"; onActivated: root.typeKey("Return") }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: keyboard.keyHeight; Layout.minimumHeight: keyboard.keyHeight; Layout.maximumHeight: keyboard.keyHeight; spacing: 7
                    Key { Layout.preferredWidth: keyboard.unit*2.25+8.75; Layout.fillHeight: true; label: "Shift ⇧"; selected: root.shift; onActivated: root.toggleShift(); onDownChanged: root.holdMod("shift", down) }
                    Repeater {
                        model: Layouts.lower
                        LetterKey { required property var modelData; symbols: modelData; russianActive: root.russian; shifted: root.shift; caps: root.caps; Layout.preferredWidth: keyboard.unit; Layout.fillHeight: true; onActivated: root.typeText(character) }
                    }
                    Key { Layout.preferredWidth: keyboard.unit*2.75+12.25; Layout.fillWidth: true; Layout.fillHeight: true; label: "Shift ⇧"; selected: root.shift; onActivated: root.toggleShift(); onDownChanged: root.holdMod("shift", down) }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: keyboard.keyHeight; Layout.minimumHeight: keyboard.keyHeight; Layout.maximumHeight: keyboard.keyHeight; spacing: 7
                    Key { Layout.preferredWidth: keyboard.unit*1.25+1.75; Layout.minimumWidth: keyboard.unit*1.25+1.75; Layout.maximumWidth: keyboard.unit*1.25+1.75; Layout.fillHeight: true; label: "Ctrl"; selected: root.control; onActivated: root.control=!root.control; onDownChanged: root.holdMod("control", down) }
                    Key { Layout.preferredWidth: keyboard.unit*1.25+1.75; Layout.minimumWidth: keyboard.unit*1.25+1.75; Layout.maximumWidth: keyboard.unit*1.25+1.75; Layout.fillHeight: true; label: "🚀"; selected: root.logo; onActivated: root.logo=!root.logo; onDownChanged: root.holdMod("logo", down) }
                    Key { Layout.preferredWidth: keyboard.unit*1.25+1.75; Layout.minimumWidth: keyboard.unit*1.25+1.75; Layout.maximumWidth: keyboard.unit*1.25+1.75; Layout.fillHeight: true; label: "Alt"; selected: root.alt; onActivated: root.toggleAlt(); onDownChanged: root.holdMod("alt", down) }
                    Key { id: spaceKey; Layout.fillWidth: true; Layout.fillHeight: true; label: root.russian ? "Русский  ·  пробел" : "English  ·  space"; onActivated: root.typeText(" ") }
                    MicKey {
                        id: micKey
                        Layout.preferredWidth: keyboard.unit; Layout.minimumWidth: keyboard.unit; Layout.maximumWidth: keyboard.unit; Layout.fillHeight: true
                        onStarted: { voiceSettled.stop(); root.voiceRussian=root.russian; root.voiceSession=true; root.voiceSawBusy=false; root.clearWord(); root.shift=false; root.control=false; root.alt=false; root.logo=false; root.send({type:"voice",action:"start"}); }
                        onFinished: { root.clearWord(); root.send({type:"voice",action:"stop"}); }
                        onAborted: root.send({type:"voice",action:"cancel"})
                    }
                    Key { Layout.preferredWidth: keyboard.unit; Layout.minimumWidth: keyboard.unit; Layout.maximumWidth: keyboard.unit; Layout.fillHeight: true; label: "Del"; textSize: 18; repeatable: true; onActivated: root.typeKey("Delete") }
                    Key { Layout.preferredWidth: keyboard.unit*1.25; Layout.minimumWidth: keyboard.unit*1.25; Layout.maximumWidth: keyboard.unit*1.25; Layout.fillHeight: true; label: root.russian ? "RU / en" : "ru / EN"; activateOnRelease: true; textSize: 18; onActivated: root.switchLanguage() }
                    Key { Layout.preferredWidth: keyboard.unit; Layout.minimumWidth: keyboard.unit; Layout.maximumWidth: keyboard.unit; Layout.fillHeight: true; label: "←"; repeatable: true; onActivated: root.typeKey("Left") }
                    ColumnLayout {
                        Layout.preferredWidth: keyboard.unit; Layout.minimumWidth: keyboard.unit; Layout.maximumWidth: keyboard.unit; Layout.fillHeight: true; spacing: 4
                        Key { Layout.fillWidth: true; Layout.fillHeight: true; label: "↑"; textSize: 18; repeatable: true; onActivated: root.typeKey("Up") }
                        Key { Layout.fillWidth: true; Layout.fillHeight: true; label: "↓"; textSize: 18; repeatable: true; onActivated: root.typeKey("Down") }
                    }
                    Key { Layout.preferredWidth: keyboard.unit; Layout.minimumWidth: keyboard.unit; Layout.maximumWidth: keyboard.unit; Layout.fillHeight: true; label: "→"; repeatable: true; onActivated: root.typeKey("Right") }
                }
            }
            PanelSettings {
                visible: root.settingsOpen && !root.tablet
                settings: root
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(420, panel.height * 0.50)
                Layout.minimumHeight: 380
                Layout.maximumHeight: Math.min(420, panel.height * 0.50)
            }
            Rectangle {
                visible: !root.tablet
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.minimumHeight: 120
                radius: 15
                color: Theme.surface
                border.color: Theme.surfaceBorder
                MultiPointTouchArea {
                    id: pad
                    anchors.fill: parent
                    minimumTouchPoints: 1; maximumTouchPoints: 5
                    mouseEnabled: false
                    property real lastX: 0
                    property real lastY: 0
                    property real travel: 0
                    property real began: 0
                    property int previousCount: 0
                    property int peakCount: 0
                    property int pressEvents: 0
                    property int updateEvents: 0
                    property int samples: 0
                    property int moveEvents: 0
                    property var histogram: [0,0,0,0,0,0]
                    property var positions: ({})
                    property int scrollEvents: 0
                    property real lastSampleTime: 0
                    property real lastTapTime: -1000
                    property real lastTapX: 0
                    property real lastTapY: 0
                    property bool tapDragging: false
                    property int dragPointId: -1
                    property bool workspaceGesture: false
                    property real swipeX: 0
                    property real swipeY: 0
                    // Four or five fingers drawn together open the window overview.
                    property real pinchStart: 0
                    property real pinchMin: 0
                    property bool scrolling: false
                    // A mostly sideways two-finger stroke moves window focus instead of scrolling.
                    property bool focusSwipe: false
                    // Co-directional two-finger drift before scrolling commits.
                    // Settling fingertips drift a pixel or two during a tap.
                    property real pairX: 0
                    property real pairY: 0
                    property var scrollDirections: ({x:0,y:0})
                    property var scrollReversals: ({x:0,y:0})
                    property var reversalSamples: ({x:0,y:0})
                    property var reversalStarted: ({x:0,y:0})
                    property real scrollVX: 0
                    property real scrollVY: 0
                    property real lastScrollTime: 0
                    property int velocitySamples: 0
                    property real scrollDistance: 0
                    property real momentumStarted: 0
                    property real momentumLast: 0
                    property real momentumProgress: 0
                    property real carryVX: 0
                    property real carryVY: 0
                    property real carryUntil: 0
                    // Match the display animation clock, not a free-running 16 ms timer.
                    FrameAnimation {
                        id: momentum
                        onTriggered: pad.tickMomentum(pad.momentumStarted + elapsedTime*1000)
                    }
                    touchPoints: [TouchPoint { id: p1 }, TouchPoint { id: p2 }, TouchPoint { id: p3 }, TouchPoint { id: p4 }, TouchPoint { id: p5 }]
                    function sample(currentPoints) {
                        samples++;
                        let points = Array.from(currentPoints).filter(p => p.pressed);
                        let n = points.length;
                        histogram[n]++;
                        let now=Date.now();
                        let scrollElapsed=Math.max(1,now-lastSampleTime);
                        let elapsed=Math.max(4,Math.min(40,scrollElapsed));
                        lastSampleTime=now;
                        let endedDrag=false;
                        if (tapDragging && !points.some(p => p.pointId === dragPointId)) {
                            root.send({type:"button",button:272,state:0});
                            tapDragging=false; endedDrag=true; lastTapTime=-1000;
                        }
                        if (!n) {
                            if (scrolling && !startMomentum(now)) root.send({type:"scrollEnd"});
                            scrollDirections={x:0,y:0}; scrollReversals={x:0,y:0};
                            reversalSamples={x:0,y:0}; reversalStarted={x:0,y:0};
                            if (!scrolling) clearCarry();
                            if (workspaceGesture) {
                                if (peakCount===3 && now-began < 1800 && Math.abs(swipeX)>=100 && Math.abs(swipeX)>Math.abs(swipeY)*1.5)
                                    root.send({type:"workspace",direction:swipeX>0 ? "previous" : "next"});
                                else if (peakCount===3 && now-began < 1800 && Math.abs(swipeY)>=100 && Math.abs(swipeY)>Math.abs(swipeX)*1.5)
                                    root.send({type:"minimize",direction:swipeY>0 ? "down" : "up"});
                                else if (peakCount>=4 && now-began < 2000 && pinchStart>0 && pinchMin<=pinchStart*0.6)
                                    root.toggleOverview();
                                workspaceGesture=false; swipeX=0; swipeY=0; lastTapTime=-1000;
                            } else if (!scrolling && !endedDrag && previousCount && now-began < (peakCount === 2 ? 450 : 350) && travel < 18 && !root.drag && peakCount <= 2) {
                                root.click(peakCount === 2 ? 273 : 272);
                                lastTapTime=peakCount === 1 ? now : -1000;
                                lastTapX=lastX; lastTapY=lastY;
                            }
                            previousCount=0; positions={}; scrolling=false; focusSwipe=false; swipeX=0;
                            return;
                        }
                        if (!previousCount) {
                            interruptMomentumForTouch(); clearVelocity();
                            began=now; travel=0; peakCount=0; pairX=0; pairY=0;
                            if (n===1 && !root.drag && now-lastTapTime < 350 && Math.hypot(points[0].x-lastTapX,points[0].y-lastTapY)<60) {
                                tapDragging=true; dragPointId=points[0].pointId;
                                root.send({type:"button",button:272,state:1});
                            }
                            lastTapTime=-1000;
                        }
                        let x = points.reduce((a,p) => a+p.x,0)/n;
                        let y = points.reduce((a,p) => a+p.y,0)/n;
                        peakCount = Math.max(peakCount,n);
                        let startingSwipe = n >= 3 && !workspaceGesture;
                        if (startingSwipe) {
                            stopMomentum(); clearVelocity();
                            workspaceGesture=true; swipeX=0; swipeY=0; pinchStart=0; pinchMin=0; lastTapTime=-1000;
                            if (tapDragging) {
                                root.send({type:"button",button:272,state:0}); tapDragging=false;
                            }
                        }
                        let next = {}, moving = [];
                        for (let p of points) {
                            let before = positions[p.pointId];
                            next[p.pointId] = {x:p.x,y:p.y};
                            if (!before) continue;
                            let dx=p.x-before.x, dy=p.y-before.y;
                            let distance=Math.hypot(dx,dy);
                            if (distance > 0.05) moving.push({dx:dx,dy:dy,distance:distance});
                        }
                        positions=next;
                        if (workspaceGesture && n<3 && Math.max(Math.abs(swipeX),Math.abs(swipeY))<30)
                            workspaceGesture=false;
                        if (workspaceGesture && n>=4) {
                            let spread=points.reduce((a,p) => a+Math.hypot(p.x-x,p.y-y),0)/n;
                            // Measure from the moment the last finger lands.
                            if (n>previousCount) { pinchStart=spread; pinchMin=spread; }
                            else pinchMin=Math.min(pinchMin,spread);
                        }
                        if (workspaceGesture) {
                            // Accumulate only movement while all three fingers
                            // are present; lifting them cannot move or click.
                            if (!startingSwipe && n===3 && previousCount===3) {
                                swipeX+=moving.reduce((sum,p)=>sum+p.dx,0)/3;
                                swipeY+=moving.reduce((sum,p)=>sum+p.dy,0)/3;
                            }
                            previousCount=n; lastX=x; lastY=y;
                            return;
                        }
                        moving.sort((a,b) => b.distance-a.distance);
                        // Wait for all scrolling fingers to lift. The last
                        // finger's release must not turn into cursor movement.
                        if (scrolling && n<2) {
                            previousCount=n; lastX=x; lastY=y; return;
                        }
                        if (moving.length) {
                            let first=moving[0], second=moving[1];
                            travel += first.distance;
                            // A resting palm or stale contact must not turn a
                            // moving finger into a two-finger scroll gesture.
                            let pairMotion = !root.drag && n === 2 && second &&
                                second.distance > first.distance*0.25 &&
                                first.dx*second.dx + first.dy*second.dy > 0;
                            if (pairMotion && !scrolling) {
                                pairX+=(first.dx+second.dx)/2; pairY+=(first.dy+second.dy)/2;
                            }
                            let scrollIntent = pairMotion && Math.hypot(pairX,pairY) >= 4;
                            if (pairMotion && !scrolling && !scrollIntent) {
                                // Undecided between tap and scroll: neither move nor scroll.
                                previousCount=n; lastX=x; lastY=y; return;
                            }
                            if (scrollIntent && !scrolling && Math.abs(pairX)>Math.abs(pairY)*2) {
                                focusSwipe=true; swipeX=pairX;
                            }
                            if (scrollIntent) {
                                scrolling=true; lastTapTime=-1000;
                                if (tapDragging) {
                                    root.send({type:"button",button:272,state:0}); tapDragging=false;
                                }
                            }
                            if (focusSwipe) {
                                // ponytail: 150 px per window, tune on the pad if it feels off.
                                if (n===2) swipeX+=moving.reduce((sum,p)=>sum+p.dx,0)/2;
                                if (Math.abs(swipeX)>=150) {
                                    // Natural like the scroll: fingers left bring the right-hand window.
                                    root.send({type:"focus",direction:swipeX>0 ? "l" : "r"});
                                    swipeX-=Math.sign(swipeX)*150;
                                }
                            } else if (scrolling && n===2) {
                                root.clearWord();
                                scrollEvents++;
                                let dx=filterScroll(moving.reduce((sum,p)=>sum+p.dx,0)/2,"x");
                                let dy=filterScroll(moving.reduce((sum,p)=>sum+p.dy,0)/2,"y");
                                if (dx || dy) {
                                    let sx=-dx*root.scrollSpeed, sy=-dy*root.scrollSpeed;
                                    root.send({type:"scroll",x:sx,y:sy});
                                    if (sx*scrollVX<0) scrollVX=0;
                                    if (sy*scrollVY<0) scrollVY=0;
                                    let blend=1-Math.exp(-scrollElapsed/35);
                                    scrollVX=scrollVX*(1-blend)+(sx/scrollElapsed)*blend;
                                    scrollVY=scrollVY*(1-blend)+(sy/scrollElapsed)*blend;
                                    lastScrollTime=now; velocitySamples++; scrollDistance+=Math.hypot(dx,dy);
                                }
                            } else {
                                root.clearWord();
                                clearCarry();
                                moveEvents++;
                                let gain=root.pointerSpeed*(1+root.pointerAccel*Math.min(first.distance/elapsed/1.2,2));
                                root.send({type:"move",x:first.dx*gain,y:first.dy*gain});
                            }
                        }
                        previousCount=n; lastX=x; lastY=y;
                    }
                    function resetGesture() {
                        stopMomentum(); clearVelocity();
                        if (scrolling) root.send({type:"scrollEnd"});
                        if (tapDragging) root.send({type:"button",button:272,state:0});
                        tapDragging=false; dragPointId=-1; lastTapTime=-1000;
                        previousCount=0; positions={};
                        workspaceGesture=false; swipeX=0; swipeY=0;
                        scrolling=false; focusSwipe=false; pairX=0; pairY=0;
                        scrollDirections={x:0,y:0}; scrollReversals={x:0,y:0};
                        reversalSamples={x:0,y:0}; reversalStarted={x:0,y:0};
                    }
                    function filterScroll(delta, axis) {
                        if (!delta) return 0;
                        let direction=Math.sign(delta);
                        if (!scrollDirections[axis] || direction===scrollDirections[axis]) {
                            scrollDirections[axis]=direction; scrollReversals[axis]=0;
                            reversalSamples[axis]=0; reversalStarted[axis]=0;
                            return delta;
                        }
                        // A lifting fingertip often rolls backwards. Stop coasting
                        // on this axis until continued motion confirms a reversal.
                        if (axis==="x") { scrollVX=0; carryVX=0; }
                        else { scrollVY=0; carryVY=0; }
                        if (!reversalSamples[axis]) reversalStarted[axis]=Date.now();
                        reversalSamples[axis]++;
                        scrollReversals[axis]+=delta;
                        if (Math.abs(scrollReversals[axis])<10 || reversalSamples[axis]<3 ||
                                Date.now()-reversalStarted[axis]<32) return 0;
                        scrollDirections[axis]=direction; scrollReversals[axis]=0;
                        reversalSamples[axis]=0; reversalStarted[axis]=0;
                        // Do not replay the buffered jitter as one velocity spike.
                        return delta;
                    }

                    function clearVelocity() {
                        scrollVX=0; scrollVY=0; lastScrollTime=0; velocitySamples=0; scrollDistance=0;
                    }
                    function clearCarry() { carryVX=0; carryVY=0; carryUntil=0; }
                    function interruptMomentumForTouch() {
                        if (!momentum.running) return;
                        // Stop visible movement immediately, retain only a short
                        // opportunity to add velocity to another matching swipe.
                        let remaining=Math.max(0,1-momentumProgress/root.inertiaDuration);
                        carryVX=scrollVX*Math.pow(remaining,3);
                        carryVY=scrollVY*Math.pow(remaining,3);
                        carryUntil=Date.now()+350;
                        stopMomentum(true);
                    }
                    function stopMomentum(keepCarry) {
                        if (!keepCarry) clearCarry();
                        if (momentum.running) { momentum.stop(); root.send({type:"scrollEnd"}); }
                    }
                    function startMomentum(now) {
                        if (!root.inertiaEnabled || workspaceGesture || peakCount>2 || velocitySamples<2 || scrollDistance<12 || now-lastScrollTime>70) {
                            clearCarry(); return false;
                        }
                        let vx=scrollVX*root.inertiaStrength, vy=scrollVY*root.inertiaStrength;
                        let speed=Math.hypot(vx,vy), carried=Math.hypot(carryVX,carryVY);
                        // Opposite/perpendicular gestures must brake, not inherit
                        // a previous direction. A stationary touch never resumes it.
                        if (now<=carryUntil && speed>0 && carried>0 &&
                                vx*carryVX+vy*carryVY>0.8*speed*carried) {
                            let retention=0.85*Math.max(0,(carryUntil-now)/350);
                            vx+=carryVX*retention; vy+=carryVY*retention;
                        }
                        clearCarry();
                        speed=Math.hypot(vx,vy);
                        if (speed<0.0001) return false;
                        // Smooth, gain-relative limiting keeps fast swipes distinct
                        // and repeated flicks bounded, unlike the old 0.8 clamp.
                        let limit=Math.max(0.02,root.scrollSpeed*root.inertiaStrength*8);
                        let gain=limit*(-Math.expm1(-speed/limit))/speed;
                        scrollVX=vx*gain; scrollVY=vy*gain;
                        momentumStarted=now; momentumLast=now; momentumProgress=0;
                        momentum.restart(); return true;
                    }
                    function tickMomentum(frameNow) {
                        let now=frameNow === undefined ? Date.now() : frameNow;
                        let elapsed=now-momentumLast;
                        if (previousCount || !root.opened || !root.inertiaEnabled || elapsed>500) { stopMomentum(); return; }
                        if (elapsed<=0) return;
                        let duration=root.inertiaDuration;
                        // A late frame should neither abort nor replay a large jump.
                        // Pause the unrendered portion and continue the same curve.
                        let step=Math.min(elapsed,32);
                        let a=Math.min(1,momentumProgress/duration);
                        let b=Math.min(1,(momentumProgress+step)/duration);
                        // Integrate v(t)=v0*(1-t/T)^3: velocity AND its slope
                        // reach zero at the end instead of chopping off a live tail.
                        let distance=duration/4*(Math.pow(1-a,4)-Math.pow(1-b,4));
                        if (distance>0) root.send({type:"scroll",x:scrollVX*distance,y:scrollVY*distance});
                        momentumLast=now; momentumProgress+=step;
                        if (b>=1) stopMomentum();
                    }
                    onPressed: { interruptMomentumForTouch(); pressEvents++; }
                    onUpdated: { updateEvents++; }
                    // Use the completed event's active list once, not intermediate
                    // pressed/released snapshots while Qt updates its point pool.
                    onTouchUpdated: points => sample(points)
                    onCanceled: { resetGesture(); root.send({type:"release"}); root.drag=false; }
                }
            }
        }
    }
}
