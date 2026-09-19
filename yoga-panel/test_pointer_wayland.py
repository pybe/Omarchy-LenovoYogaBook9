"""Explicit desktop integration test; moves cursor over its own temporary surface.

Run manually: python3 test_pointer_wayland.py /path/to/build/yoga-pointer
Captures only this surface's Wayland traffic, never keyboard input.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

QML = '''import QtQuick
import Quickshell
import Quickshell.Wayland
PanelWindow {
 screen: Quickshell.screens.find(s=>s.name === "eDP-1") ?? null
 implicitWidth: 500; implicitHeight: 180
 color: "#1a2738"
 exclusionMode: ExclusionMode.Ignore
 WlrLayershell.namespace: "yoga-scroll-probe"
 WlrLayershell.layer: WlrLayer.Overlay
 WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
 Text { anchors.centerIn: parent; text: "Проверка прокрутки — несколько секунд"; color: "white" }
 WheelHandler {}
 Timer { interval: 15000; running: true; onTriggered: Qt.quit() }
}
'''

def check(binary, axis, sign):
    pos = json.loads(subprocess.check_output(['hyprctl', 'cursorpos', '-j']))
    monitors = json.loads(subprocess.check_output(['hyprctl', 'monitors', '-j']))
    assert min(m['x'] for m in monitors) == min(m['y'] for m in monitors) == 0
    width = max(m['x'] + round(m['width']/m['scale']) for m in monitors)
    height = max(m['y'] + round(m['height']/m['scale']) for m in monitors)
    with tempfile.TemporaryDirectory(prefix='yoga-scroll-probe-') as tmp:
        Path(tmp, 'shell.qml').write_text(QML)
        with open(Path(tmp, 'wayland.log'), 'w+') as log:
            probe = subprocess.Popen(['quickshell', '-p', tmp], stdout=log, stderr=log,
                                     env=dict(os.environ, WAYLAND_DEBUG='1'))
            helper = None
            try:
                for _ in range(40):
                    layers = json.loads(subprocess.check_output(['hyprctl', 'layers', '-j']))
                    layer = next((l for m in layers.values() for ls in m['levels'].values()
                                  for l in ls if l['namespace'] == 'yoga-scroll-probe'), None)
                    if layer:
                        break
                    time.sleep(.05)
                assert layer, 'Test surface did not appear'
                time.sleep(.15)
                helper = subprocess.Popen([binary], stdin=subprocess.PIPE, text=True)
                def send(command):
                    helper.stdin.write(command+'\n')
                    helper.stdin.flush()
                send(f"a {layer['x']+layer['w']//2} {layer['y']+layer['h']//2} {width} {height}")
                send('m 1 0')
                time.sleep(.15)
                log.flush()
                log.seek(0)
                assert re.search(r'wl_pointer#\d+\.enter\(', log.read()), 'Pointer missed test surface'
                for magnitude in [1, .5, .25, .1, .05, .02, .01, .004]:
                    x, y = (sign*magnitude, 0) if axis == 1 else (0, sign*magnitude)
                    send(f's {x} {y}')
                    time.sleep(.025)
                send('e')
                time.sleep(.15)
            finally:
                if helper:
                    try:
                        send(f"a {pos['x']} {pos['y']} {width} {height}")
                        helper.stdin.close()
                        helper.wait(timeout=2)
                    except (BrokenPipeError, subprocess.TimeoutExpired):
                        helper.kill()
                        helper.wait()
                probe.terminate()
                probe.wait(timeout=3)
            log.seek(0)
            output = log.read()
        events = [(int(a), float(v)) for a, v in
                  re.findall(r'wl_pointer#\d+\.axis\(\d+, (\d+), (-?[\d.]+)\)', output)]
        assert events, 'No scroll events received'
        assert all(a == axis or v == 0 for a, v in events), 'Stop generated cross-axis scroll'
        assert all(v*sign >= 0 for a, v in events if a == axis), 'System reversed scroll direction'
        total = sum(v for a, v in events if a == axis)
        assert abs(total-sign*1.934) < 1/256, f'Unexpected gain: {total}'
        assert set(re.findall(r'wl_pointer#\d+\.axis_source\((\d+)\)', output)) == {'2'}, 'Not continuous'
        assert not re.search(r'wl_pointer#\d+\.axis_(?:value120|discrete)\(', output), 'Wheel steps synthesized'
        assert re.search(r'wl_pointer#\d+\.axis_stop\(', output), 'Missing stop event'
        print(f'PASS: axis={axis} sign={sign}, exact smooth distance, no reverse or cross-axis stop jump')

if __name__ == '__main__':
    binary = str(Path(sys.argv[1]).resolve())
    for axis in [0, 1]:
        for sign in [-1, 1]:
            check(binary, axis, sign)
