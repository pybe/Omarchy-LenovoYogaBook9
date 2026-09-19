"""Exercise SIGTERM cleanup with fake helpers; never opens a microphone."""
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import tempfile
import unittest

class ShutdownTests(unittest.TestCase):
    def test_sigterm_cancels_owned_recording(self):
        source=Path(__file__).parent
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory);(base/'build').mkdir()
            for name in ('backend.py','voice.py','prediction.py','autocorrect.py','defaults.json'):
                shutil.copy2(source/name,base/name)
            helper='#!/usr/bin/python3\nimport sys\nprint("ready",flush=True)\nfor line in sys.stdin: pass\n'
            for name in ('yoga-keyboard','yoga-pointer'):
                path=base/'build'/name;path.write_text(helper);path.chmod(0o755)
            executable=base/'voxtype'
            executable.write_text('#!/usr/bin/python3\nimport os,sys\nfrom pathlib import Path\nif sys.argv[1]=="status": print("idle")\nelse:\n with Path(os.environ["VOICE_TEST_LOG"]).open("a") as f:f.write(sys.argv[2]+"\\n")\n')
            executable.chmod(0o755)
            log=base/'voice.log'
            env={**os.environ,'PATH':str(base)+':'+os.environ['PATH'],'VOICE_TEST_LOG':str(log),'HYPRLAND_INSTANCE_SIGNATURE':'yoga-test-no-session'}
            proc=subprocess.Popen(['python3',str(base/'backend.py')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,text=True)
            try:
                proc.stdin.write(json.dumps({'type':'voice','action':'start'})+'\n');proc.stdin.flush()
                # stdout is line-buffered by emit; bounded select avoids a hung test.
                import time
                deadline=time.monotonic()+5
                selector=selectors.DefaultSelector();selector.register(proc.stdout,selectors.EVENT_READ)
                data=''
                while time.monotonic()<deadline and '"voice": "recording"' not in data:
                    if selector.select(.1):data+=os.read(proc.stdout.fileno(),4096).decode()
                selector.close()
                self.assertIn('"voice": "recording"',data)
                proc.terminate();proc.wait(timeout=5)
                self.assertEqual(log.read_text().splitlines(),['start','cancel'])
                self.assertEqual(proc.returncode,0)
            finally:
                if proc.poll() is None:proc.kill();proc.wait()
                proc.stdin.close();proc.stdout.close();proc.stderr.close()
if __name__=='__main__':unittest.main()
