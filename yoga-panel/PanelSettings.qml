import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: view
    required property var settings
    spacing: 12
    RowLayout {
        Layout.fillWidth: true; Layout.preferredHeight: 32; Layout.minimumHeight: 32; Layout.maximumHeight: 32
        Text { text: "Под себя"; color: Theme.text; font.pixelSize: 23; font.weight: Font.DemiBold }
        Text { text: "Сохраняется автоматически"; color: Theme.textMuted; font.pixelSize: 12; Layout.leftMargin: 12 }
        Item { Layout.fillWidth: true }
        Key { label: "Сбросить тачпад"; textSize: 12; radius: 8; Layout.preferredWidth: 150; Layout.fillHeight: true; onActivated: { settings.pointerSpeed=2.4; settings.pointerAccel=.1; settings.scrollSpeed=.9; settings.inertiaEnabled=true; settings.inertiaStrength=1.5; settings.inertiaDuration=650; } }
    }
    RowLayout {
        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
        SettingsCard {
            title: "Курсор"; subtitle: "Движение одним пальцем"
            SettingsSlider { label: "Скорость"; value: settings.pointerSpeed; minimum: .5; maximum: 5; step: .1; displayValue: value.toFixed(1)+"×"; onAdjusted: value => settings.pointerSpeed=value }
            SettingsSlider { label: "Ускорение"; value: settings.pointerAccel; minimum: 0; maximum: 2; step: .1; displayValue: value.toFixed(1); onAdjusted: value => settings.pointerAccel=value }
            Item { Layout.fillHeight: true }
            Text { text: "Быстрый жест перемещает курсор дальше.\n0 — движение без ускорения."; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
        SettingsCard {
            title: "Прокрутка"; subtitle: "Два пальца · плавное завершение жеста"
            SettingsSlider { label: "Скорость"; value: settings.scrollSpeed/.0018; minimum: 1; maximum: 500; step: 1; displayValue: Math.round(value)+"%"; onAdjusted: value => settings.scrollSpeed=value*.0018 }
            SettingsSwitch { label: "Инерция"; checked: settings.inertiaEnabled; onToggled: value => settings.inertiaEnabled=value }
            SettingsSlider { label: "Сила инерции"; value: settings.inertiaStrength; minimum: .15; maximum: 1.5; step: .05; displayValue: Math.round(value*100)+"%"; enabled: settings.inertiaEnabled; opacity: enabled ? 1 : .4; onAdjusted: value => settings.inertiaStrength=value }
            SettingsSlider { label: "Длительность затухания"; value: settings.inertiaDuration; minimum: 200; maximum: 1500; step: 50; displayValue: (value/1000).toFixed(2)+" с"; enabled: settings.inertiaEnabled; opacity: enabled ? 1 : .4; onAdjusted: value => settings.inertiaDuration=value }
        }
        SettingsCard {
            title: "Ввод"; subtitle: "Подсказки и исправление слов"
            SettingsSwitch { label: "Подсказки слов"; checked: settings.predictionEnabled; onToggled: value => settings.predictionEnabled=value }
            SettingsSwitch { label: "Исправлять по пробелу"; checked: settings.autocorrectEnabled; onToggled: value => settings.autocorrectEnabled=value }
            SettingsSwitch { label: "Тема OLED: чёрный фон, контуры"; checked: settings.oledTheme; onToggled: value => settings.oledTheme=value }
            Text { text: "Backspace сразу после исправления\nвозвращает исходное слово."; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Item { Layout.fillHeight: true }
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 62; radius: 10; color: Theme.surface; border.color: Theme.surfaceBorder
                Text { anchors.fill: parent; anchors.margins: 12; text: "Тачпад внизу активен —\nпроверяй ощущения прямо здесь."; color: Theme.textMuted; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
            }
        }
    }
}
