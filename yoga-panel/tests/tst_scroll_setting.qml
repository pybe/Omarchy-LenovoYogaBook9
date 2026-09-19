import QtQuick
import QtTest
import ".."

TestCase {
    name: "ScrollSetting"
    visible: true; when: windowShown
    width: 1100; height: 100
    property real appliedSpeed: 0.09
    SettingsSlider { id: row; label: "Скорость"; minimum: 1; maximum: 500; step: 1; width: 1100; height: 62; value: appliedSpeed/.0018; onAdjusted: value => appliedSpeed=value*.0018 }
    function test_drag_applies_and_external_update_stays_bound() {
        let slider=findChild(row,"settingsSlider");
        verify(slider!==null);wait(50);
        let touch=touchEvent(slider);
        touch.press(0,slider,slider.width*.07,slider.height/2).commit();
        touch.move(0,slider,slider.width*.6,slider.height/2).commit();wait(50);
        verify(appliedSpeed>.4,"Dragging applies before release");
        touch.release(0,slider,slider.width*.6,slider.height/2).commit();
        appliedSpeed=.09;wait(50);
        compare(slider.value,50,"External setting remains bound after dragging");
        appliedSpeed=.0018;wait(20);row.change(-1);compare(appliedSpeed,.0018);
        row.change(1);compare(appliedSpeed,.0036);
    }
}
