#!/usr/bin/env python3
"""Integration test: inject only while our own exclusive test surface lives."""
import os
from pathlib import Path
import selectors
import subprocess
import time

base = Path(__file__).parent
proc = subprocess.Popen(['quickshell', '-p', str(base/'test-input'), '--no-color'],
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
sel = selectors.DefaultSelector()
sel.register(proc.stdout, selectors.EVENT_READ)
output = ''
try:
    deadline = time.monotonic() + 15
    sent = False
    while time.monotonic() < deadline and proc.poll() is None:
        if sel.select(0.2):
            chunk = os.read(proc.stdout.fileno(), 65536).decode(errors='replace')
            output += chunk
        if 'Configuration Loaded' in output and not sent:
            time.sleep(0.5)
            if proc.poll() is not None:
                raise RuntimeError('Test surface exited before injection')

            import json
            events=[{'type':'text','text':ch} for ch in 'ЙогаTest42']
            events += [{'type':'key','key':'BackSpace'},{'type':'text','text':'2'}]
            subprocess.run(['python3',str(base/'backend.py')],input=''.join(json.dumps(e)+'\n' for e in events),text=True,check=True,timeout=5)
            sent = True
        if 'INPUT_TEST:ЙогаTest42' in output:
            print('PASS: Russian/English virtual input received by test field')
            break
    else:
        raise RuntimeError('No matching input received:\n' + output)
finally:
    proc.terminate()
    try: proc.wait(timeout=3)
    except subprocess.TimeoutExpired: proc.kill(); proc.wait()
