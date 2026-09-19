#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
mkdir -p build
wayland-scanner client-header protocol/virtual-pointer.xml build/virtual-pointer.h
wayland-scanner private-code protocol/virtual-pointer.xml build/virtual-pointer.c
gcc -Wall -Wextra -Werror -O2 -Ibuild pointer.c build/virtual-pointer.c -o build/yoga-pointer $(pkg-config --cflags --libs wayland-client) -lm
wayland-scanner client-header protocol/virtual-keyboard.xml build/virtual-keyboard.h
wayland-scanner private-code protocol/virtual-keyboard.xml build/virtual-keyboard.c
gcc -Wall -Wextra -Werror -O2 -Ibuild keyboard.c build/virtual-keyboard.c -o build/yoga-keyboard $(pkg-config --cflags --libs wayland-client xkbcommon)
