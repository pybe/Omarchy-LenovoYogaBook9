#!/bin/bash
# Build hyprbars (window title bars with a touch-friendly close button and
# drag-to-move) for the running Hyprland. Upstream pins a plugins commit per
# Hyprland commit in hyprpm.toml; hyprpm itself needs root, this does not.
set -euo pipefail
cd -- "$(dirname -- "$0")"
mkdir -p build
cache=${XDG_CACHE_HOME:-$HOME/.cache}/yoga-panel/hyprland-plugins
[[ -d $cache/.git ]] || git clone -q --filter=blob:none https://github.com/hyprwm/hyprland-plugins "$cache"
hyprland=$(hyprctl version -j | python3 -c "import json,sys;print(json.load(sys.stdin)['commit'])")
pin() { grep -F "\"$hyprland\"" "$cache/hyprpm.toml" | head -1 | cut -d'"' -f4; }
git -C "$cache" checkout -q origin/HEAD -- hyprpm.toml 2>/dev/null || true
commit=$(pin)
if [[ -z $commit ]]; then git -C "$cache" fetch -q origin && git -C "$cache" checkout -q origin/HEAD -- hyprpm.toml; commit=$(pin); fi
[[ -n $commit ]] || { echo "hyprbars: no plugins commit pinned for Hyprland $hyprland" >&2; exit 1; }
git -C "$cache" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$cache" fetch -q origin "$commit"
src=$(mktemp -d); temporary=; trap 'rm -rf -- "$src" ${temporary:+"$temporary"}' EXIT
git -C "$cache" archive "$commit" hyprbars | tar -x -C "$src"
temporary=$(mktemp build/hyprbars.XXXXXX.so)
g++ -std=c++2b -O2 -shared -fPIC -fno-gnu-unique -w $(pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon) \
  "$src"/hyprbars/{main,barDeco,BarPassElement}.cpp -o "$temporary"
# Atomic replacement never truncates the inode mapped by a running compositor.
mv -- "$temporary" build/hyprbars.so
