"""Push-to-talk adapter for the installed system Voxtype daemon."""
import subprocess

class Voice:
    def __init__(self, run=subprocess.run):
        self.run=run
        self.owned=False

    def command(self, *args):
        return self.run(['voxtype',*args],check=True,capture_output=True,text=True,timeout=4)

    def start(self):
        if self.owned: return
        if self.command('status').stdout.strip()!='idle':
            raise ValueError('System dictation is busy')
        self.owned=True
        self.command('record','start','--no-auto-submit','--no-smart-auto-submit')

    def stop(self):
        if self.owned:
            self.command('record','stop')
            self.owned=False

    def cancel(self):
        if self.owned:
            self.command('record','cancel')
            self.owned=False
