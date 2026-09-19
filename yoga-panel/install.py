#!/usr/bin/env python3
"""Build before replacing the user installation. No root or package changes."""
import argparse
from datetime import datetime
from pathlib import Path
import shutil
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parent
HOME = Path.home()
TARGET = HOME/'.local/share/yoga-panel'

def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run',action='store_true')
    parser.add_argument('--no-start',action='store_true')
    parser.add_argument('--previous-app',type=Path,help='Previous application directory when migrating a development installation')
    args=parser.parse_args()
    destinations={
        SOURCE/'bin/yoga-panel':HOME/'.local/bin/yoga-panel',
        SOURCE/'systemd/yoga-panel.service':HOME/'.config/systemd/user/yoga-panel.service',
        SOURCE.parent/'bin/yoga-recovery':HOME/'.local/bin/yoga-recovery',
        SOURCE.parent/'bin/yoga-brightness-sync':HOME/'.local/bin/yoga-brightness-sync',
        SOURCE.parent/'config/systemd/user/yoga-brightness-sync.service':HOME/'.config/systemd/user/yoga-brightness-sync.service',
        SOURCE.parent/'config/hypr/minimize.lua':HOME/'.config/hypr/minimize.lua',
        SOURCE.parent/'config/hypr/yoga-windows.lua':HOME/'.config/hypr/yoga-windows.lua',
        SOURCE.parent/'config/hypr/yoga-titlebars.lua':HOME/'.config/hypr/yoga-titlebars.lua',
    }
    if args.dry_run:
        print('Build and install application:',TARGET)
        for destination in destinations.values(): print('Install:',destination)
        print('Back up existing files; enable panel and brightness synchronization services; install Omarchy post-update check.')
        return
    for command in ['g++','gcc','pkg-config','wayland-scanner','quickshell','hyprctl','brightnessctl']:
        if not shutil.which(command): raise SystemExit('Missing dependency: '+command)
    TARGET.parent.mkdir(parents=True,exist_ok=True)
    backup=HOME/'.local/state/yoga-panel/backups'/datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    with tempfile.TemporaryDirectory(prefix='.yoga-panel-',dir=TARGET.parent) as staging:
        app=Path(staging)/'app'
        shutil.copytree(SOURCE,app,ignore=shutil.ignore_patterns('build','__pycache__','*.pyc'))
        run('bash','build.sh',cwd=app)
        run('bash','build-gesture.sh',cwd=app)
        # Title bars are optional: no network for the pinned source must not block an install.
        if subprocess.run(['bash','build-hyprbars.sh'],cwd=app).returncode: print('hyprbars not built; windows keep no title bars')
        subprocess.run(['systemctl','--user','stop','yoga-panel.service'],check=False)
        for old_app in {TARGET,args.previous_app} - {None}:
            for library in ('yoga-panel-gesture.so','hyprbars.so'):
                subprocess.run(['hyprctl','plugin','unload',str(old_app/'build'/library)],check=False)
        backup.mkdir(parents=True)
        if TARGET.exists(): shutil.move(str(TARGET),str(backup/'app'))
        shutil.move(str(app),str(TARGET))
        for source,destination in destinations.items():
            destination.parent.mkdir(parents=True,exist_ok=True)
            if destination.exists():
                saved=backup/destination.relative_to(HOME)
                saved.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(destination,saved)
            shutil.copy2(source,destination)
            if destination.parent.name=='bin': destination.chmod(0o755)
    hyprland=HOME/'.config/hypr/hyprland.lua'
    for module,comment in (('hypr.minimize','Three-finger swipe down/up: minimize/restore all windows on the workspace.'),
                           ('hypr.yoga-windows','Windows opened while the lower-screen keyboard is up go to the upper screen.'),
                           ('hypr.yoga-titlebars','Compact touch title bars: drag to move, close button.')):
        if hyprland.exists() and 'require("'+module+'")' not in hyprland.read_text():
            with hyprland.open('a') as config:
                config.write('\n-- '+comment+'\nrequire("'+module+'")\n')
    run('systemctl','--user','daemon-reload')
    run('systemctl','--user','enable','yoga-panel.service','yoga-brightness-sync.service')
    if not args.no_start:
        run('systemctl','--user','restart','yoga-brightness-sync.service','yoga-panel.service')
    if shutil.which('omarchy'):
        run('omarchy','hook','install','post-update',str(SOURCE.parent/'config/omarchy/hooks/90-yoga-check'))
    print('Installed. Previous files:',backup)
    print('Open with ~/.local/bin/yoga-panel show')

if __name__=='__main__': main()
