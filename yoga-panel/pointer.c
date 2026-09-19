#define _POSIX_C_SOURCE 200809L
#include <wayland-client.h>
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>
#include "virtual-pointer.h"

static struct zwlr_virtual_pointer_manager_v1 *manager;
static void global(void *data, struct wl_registry *registry, uint32_t id,
                   const char *name, uint32_t version) {
    (void)data;
    if (!strcmp(name, "zwlr_virtual_pointer_manager_v1"))
        manager = wl_registry_bind(registry, id,
            &zwlr_virtual_pointer_manager_v1_interface, version > 2 ? 2 : version);
}
static void removed(void *data, struct wl_registry *registry, uint32_t id) {
    (void)data; (void)registry; (void)id;
}
static uint32_t now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint32_t)(t.tv_sec * 1000 + t.tv_nsec / 1000000);
}
static wl_fixed_t scroll_fixed(double delta, double *remainder) {
    double total=delta+*remainder;
    wl_fixed_t value=wl_fixed_from_double(total);
    *remainder=total-wl_fixed_to_double(value);
    return value;
}

int main(int argc, char **argv) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) { fputs("Cannot connect to Wayland\n", stderr); return 1; }
    struct wl_registry *registry = wl_display_get_registry(display);
    const struct wl_registry_listener listener = {global, removed};
    wl_registry_add_listener(registry, &listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !manager) {
        fputs("Virtual pointer protocol unavailable\n", stderr); return 1;
    }
    if (argc > 1 && !strcmp(argv[1], "--check")) {
        puts("Wayland virtual pointer available"); wl_display_disconnect(display); return 0;
    }
    struct zwlr_virtual_pointer_v1 *pointer =
        zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, NULL);
    char line[160], op;
    double x, y, scroll_remainder_x=0, scroll_remainder_y=0;
    unsigned button, state, ax, ay, width, height;
    while (fgets(line, sizeof(line), stdin)) {
        uint32_t time = now();
        if (sscanf(line, "%c %lf %lf", &op, &x, &y) == 3 &&
            (op == 'm' || op == 's') && isfinite(x) && isfinite(y) &&
            fabs(x) < 4096 && fabs(y) < 4096) {
            if (op == 'm') {
                zwlr_virtual_pointer_v1_motion(pointer, time,
                    wl_fixed_from_double(x), wl_fixed_from_double(y));
            } else {
                wl_fixed_t sx=scroll_fixed(x,&scroll_remainder_x);
                wl_fixed_t sy=scroll_fixed(y,&scroll_remainder_y);
                // Hyprland resets the event in axis(), and source applies to
                // the last axis. Set it AFTER each axis, before frame().
                // We generate our own inertia: expose continuous motion.
                if (sx) {
                    zwlr_virtual_pointer_v1_axis(pointer, time, WL_POINTER_AXIS_HORIZONTAL_SCROLL, sx);
                    zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_CONTINUOUS);
                }
                if (sy) {
                    zwlr_virtual_pointer_v1_axis(pointer, time, WL_POINTER_AXIS_VERTICAL_SCROLL, sy);
                    zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_CONTINUOUS);
                }
            }
        } else if (sscanf(line, "a %u %u %u %u", &ax, &ay, &width, &height) == 4 && width && height && ax <= width && ay <= height) {
            zwlr_virtual_pointer_v1_motion_absolute(pointer,time,ax,ay,width,height);
        } else if (sscanf(line, "b %u %u", &button, &state) == 2 &&
                   (button == BTN_LEFT || button == BTN_RIGHT) && state <= 1) {
            zwlr_virtual_pointer_v1_button(pointer, time, button, state);
        } else if (line[0] == 'e') {
            scroll_remainder_x=scroll_remainder_y=0;
            zwlr_virtual_pointer_v1_axis_stop(pointer, time, WL_POINTER_AXIS_VERTICAL_SCROLL);
            zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_CONTINUOUS);
            zwlr_virtual_pointer_v1_axis_stop(pointer, time, WL_POINTER_AXIS_HORIZONTAL_SCROLL);
            zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_CONTINUOUS);
        } else if (line[0] == 'r') {
            scroll_remainder_x=scroll_remainder_y=0;
            zwlr_virtual_pointer_v1_button(pointer, time, BTN_LEFT, 0);
            zwlr_virtual_pointer_v1_button(pointer, time, BTN_RIGHT, 0);
            zwlr_virtual_pointer_v1_axis_stop(pointer, time, WL_POINTER_AXIS_VERTICAL_SCROLL);
            zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_CONTINUOUS);
            zwlr_virtual_pointer_v1_axis_stop(pointer, time, WL_POINTER_AXIS_HORIZONTAL_SCROLL);
            zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_CONTINUOUS);
        } else continue;
        zwlr_virtual_pointer_v1_frame(pointer);
        if (wl_display_roundtrip(display) < 0) break;
    }
    zwlr_virtual_pointer_v1_button(pointer, now(), BTN_LEFT, 0);
    zwlr_virtual_pointer_v1_button(pointer, now(), BTN_RIGHT, 0);
    zwlr_virtual_pointer_v1_frame(pointer);
    zwlr_virtual_pointer_v1_destroy(pointer);
    wl_display_flush(display);
    wl_display_disconnect(display);
    return 0;
}
