#!/usr/bin/env python3
"""Verify the Hyprland plugins are loaded; rebuild once after an ABI update."""
import fcntl
import json
from pathlib import Path
import subprocess
import sys

BASE = Path(__file__).resolve().parent
# (plugin name, library, build script, required). Title bars are a convenience:
# a failed rebuild (no network for the pinned source) must not keep the panel down.
PLUGINS = (('yoga-panel-gesture', 'yoga-panel-gesture.so', 'build-gesture.sh', True),
           ('hyprbars', 'hyprbars.so', 'build-hyprbars.sh', False))

def loaded(name):
    result = subprocess.run(['hyprctl','plugin','list','-j'], capture_output=True, text=True, check=True)
    return any(p.get('name') == name for p in json.loads(result.stdout))

def try_load(name, library):
    result = subprocess.run(['hyprctl','plugin','load',str(BASE/'build'/library)], capture_output=True, text=True)
    # Some hyprctl versions exit zero even when loading failed.
    print(result.stdout.strip() or result.stderr.strip(), flush=True)
    return loaded(name)

def ensure(name, library, script):
    if loaded(name) or ((BASE/'build'/library).exists() and try_load(name, library)):
        return
    print(f'{name} unavailable; rebuilding against installed Hyprland headers', flush=True)
    subprocess.run(['bash',str(BASE/script)], cwd=BASE, check=True)
    if not try_load(name, library):
        raise RuntimeError(f'{name} could not load after rebuilding; check whether Hyprland needs a session restart after updates')

def main():
    (BASE/'build').mkdir(exist_ok=True)
    with (BASE/'build/plugin-load.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for name, library, script, required in PLUGINS:
            try:
                ensure(name, library, script)
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                if required: raise
                print(f'Yoga panel startup: {name} skipped: {error}', file=sys.stderr, flush=True)

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'Yoga panel startup: {error}', file=sys.stderr)
        sys.exit(1)
