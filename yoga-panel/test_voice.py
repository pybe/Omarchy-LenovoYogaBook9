import subprocess
import unittest
from types import SimpleNamespace
from voice import Voice

class VoiceTests(unittest.TestCase):
    def setUp(self):
        self.calls=[]
        def run(args,**kwargs):
            self.calls.append(args)
            return SimpleNamespace(stdout='idle\n')
        self.voice=Voice(run)
    def test_hold_release(self):
        self.voice.start();self.voice.start();self.voice.stop();self.voice.stop()
        self.assertEqual(self.calls,[['voxtype','status'],['voxtype','record','start','--no-auto-submit','--no-smart-auto-submit'],['voxtype','record','stop']])
    def test_cancel_owned_only(self):
        self.voice.cancel();self.assertEqual(self.calls,[])
        self.voice.start();self.voice.cancel();self.voice.cancel()
        self.assertEqual(self.calls[-1],['voxtype','record','cancel'])
        self.assertFalse(self.voice.owned)
    def test_busy(self):
        self.voice.run=lambda *a,**k: SimpleNamespace(stdout='recording\n')
        with self.assertRaises(ValueError):self.voice.start()
        self.assertFalse(self.voice.owned)
    def test_failure_can_be_cancelled(self):
        self.voice.start()
        self.voice.run=lambda *a,**k: (_ for _ in ()).throw(subprocess.TimeoutExpired('voxtype',4))
        with self.assertRaises(subprocess.TimeoutExpired):self.voice.stop()
        self.assertTrue(self.voice.owned)
if __name__=='__main__':unittest.main()
