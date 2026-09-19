import QtQuick
import QtTest
import ".."
TestCase {
 name: "LanguageKey"
 when: windowShown
 visible: true
 width: 260; height: 140
 Key { id: key; x:10; y:10; width:220; height:80; label:"RU / en"; activateOnRelease:true }
 SignalSpy { id: spy; target:key; signalName:"activated" }
 function init() { key.reset(); spy.clear(); }
 function test_tap_once() {
  let t=touchEvent(key);t.press(0,key,30,35).commit();compare(spy.count,0);
  t.release(0,key,30,35).commit();compare(spy.count,1);
 }
 function test_slide_is_not_language_switch() {
  let t=touchEvent(key);t.press(0,key,30,35).commit();
  t.move(0,key,150,35).commit();t.release(0,key,150,35).commit();
  compare(spy.count,0,"Sliding across the language key must not switch");
 }
}
