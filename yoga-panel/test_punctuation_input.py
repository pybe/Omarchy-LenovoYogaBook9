#!/usr/bin/env python3
"""Own test surface: punctuation text and virtual keyboard layout events."""
import os
from pathlib import Path
import selectors
import socket
import subprocess
import time

base=Path(__file__).parent
proc=subprocess.Popen(['quickshell','-p',str(base/'test-input'),'--no-color'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
sel=selectors.DefaultSelector();sel.register(proc.stdout,selectors.EVENT_READ)
keyboard=None
stream=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
stream.connect(str(Path(os.environ['XDG_RUNTIME_DIR'])/'hypr'/os.environ['HYPRLAND_INSTANCE_SIGNATURE']/'.socket2.sock'))
stream.setblocking(False)
output=''
def drain():
    data=b''
    while True:
        try: data+=stream.recv(65536)
        except BlockingIOError:return data.decode(errors='replace')
try:
    deadline=time.monotonic()+10
    while 'Configuration Loaded' not in output and time.monotonic()<deadline:
        if sel.select(.2):output+=os.read(proc.stdout.fileno(),65536).decode(errors='replace')
    assert 'Configuration Loaded' in output
    time.sleep(.3)
    keyboard=subprocess.Popen([str(base/'build/yoga-keyboard')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
    assert keyboard.stdout.readline().strip()=='ready'
    keyboard.stdin.write('g 1\n');keyboard.stdin.flush();time.sleep(.15);drain()
    expected='Привет. Да, ещё! Что? Всё: хорошо; №42 / тест '
    assert proc.poll() is None
    keyboard.stdin.write(''.join(f't {ord(c)} 0\n' for c in expected));keyboard.stdin.flush()
    events='';deadline=time.monotonic()+5
    while time.monotonic()<deadline:
        if sel.select(.1):output+=os.read(proc.stdout.fileno(),65536).decode(errors='replace')
        events+=drain()
        if expected in output:break
    assert expected in output, 'Punctuation output mismatch'
    bad=[e for e in events.splitlines() if e.startswith('activelayout>>') and 'yoga-keyboard' in e and 'English' in e]
    assert not bad, 'Punctuation changed the virtual keyboard to English'
    print('PASS: Russian punctuation and space preserve layout and produce exact text')
finally:
    if keyboard:
        keyboard.stdin.close();keyboard.wait(timeout=3)
    proc.terminate();proc.wait(timeout=3);stream.close();sel.close()
