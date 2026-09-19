import QtQuick
import QtTest
import ".."

TestCase {
    name: "KeyHold"
    when: windowShown
    width: 260; height: 140
    visible: true
    Key { id: key; x: 10; y: 10; width: 220; height: 80; label: "Backspace"; repeatable: true }
    SignalSpy { id: spy; target: key; signalName: "activated" }
    function init() { key.visible=true; key.reset(); wait(50); spy.clear(); }
    function test_slide_inside_keeps_repeating() {
        let touch=touchEvent(key);
        touch.press(0,key,30,35).commit();
        wait(530);
        verify(spy.count>=2,"Held key should repeat");
        touch.move(0,key,140,40).commit();
        let before=spy.count;
        wait(200);
        verify(spy.count>before,"Movement inside key must not cancel repetition");
        touch.release(0,key,140,40).commit();
        wait(20);before=spy.count;wait(200);
        compare(spy.count,before,"Release must stop repetition");
        compare(key.down,false);
    }
    function test_outside_cancels_repetition() {
        let touch=touchEvent(key);
        touch.press(0,key,30,35).commit();wait(530);
        touch.move(0,key,240,40).commit();wait(20);
        let before=spy.count;wait(200);compare(spy.count,before);
        compare(key.down,false);
        touch.release(0,key,240,40).commit();
    }
    function test_hide_cancels_repetition() {
        let touch=touchEvent(key);
        touch.press(0,key,30,35).commit();wait(530);
        key.visible=false;let before=spy.count;wait(200);
        compare(spy.count,before);compare(key.down,false);
        touch.release(0,key,30,35).commit();
    }
}
