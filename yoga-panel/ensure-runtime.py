#!/usr/bin/env python3
"""Rebuild native input helpers when files or shared libraries are missing."""
from pathlib import Path
import subprocess

BASE=Path(__file__).resolve().parent

def usable(path):
    if not path.is_file(): return False
    result=subprocess.run(['ldd',str(path)],capture_output=True,text=True,timeout=10)
    return result.returncode==0 and 'not found' not in result.stdout+result.stderr

def main():
    if not all(usable(BASE/'build'/name) for name in ('yoga-keyboard','yoga-pointer')):
        print('Rebuilding Yoga input helpers against installed libraries',flush=True)
        subprocess.run(['bash',str(BASE/'build.sh')],cwd=BASE,check=True,timeout=60)
        if not all(usable(BASE/'build'/name) for name in ('yoga-keyboard','yoga-pointer')):
            raise RuntimeError('Input helpers still have unresolved libraries')
if __name__=='__main__':main()
