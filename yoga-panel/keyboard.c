#define _GNU_SOURCE
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "virtual-keyboard.h"

static struct zwp_virtual_keyboard_manager_v1 *manager;
static struct wl_seat *seat;
static void global(void *data, struct wl_registry *registry, uint32_t id,
                   const char *name, uint32_t version) {
    (void)data; (void)version;
    if (!strcmp(name,"zwp_virtual_keyboard_manager_v1"))
        manager=wl_registry_bind(registry,id,&zwp_virtual_keyboard_manager_v1_interface,1);
    else if (!strcmp(name,"wl_seat") && !seat)
        seat=wl_registry_bind(registry,id,&wl_seat_interface,1);
}
static void removed(void *data, struct wl_registry *registry, uint32_t id) {
    (void)data; (void)registry; (void)id;
}
static uint32_t now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t);
    return (uint32_t)(t.tv_sec*1000+t.tv_nsec/1000000);
}
static uint32_t mask(struct xkb_keymap *map,const char *name) {
    xkb_mod_index_t i=xkb_keymap_mod_get_index(map,name);
    return i<32 ? 1u<<i : 0;
}
int main(void) {
    struct wl_display *display=wl_display_connect(NULL);
    if (!display) return 1;
    struct wl_registry *registry=wl_display_get_registry(display);
    const struct wl_registry_listener listener={global,removed};
    wl_registry_add_listener(registry,&listener,NULL);
    if (wl_display_roundtrip(display)<0 || !manager || !seat) return 2;
    struct xkb_context *context=xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    const struct xkb_rule_names names={.rules="evdev",.model="pc105",.layout="us,ru",.options=""};
    struct xkb_keymap *map=xkb_keymap_new_from_names(context,&names,XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (!map) return 3;
    char *text=xkb_keymap_get_as_string(map,XKB_KEYMAP_FORMAT_TEXT_V1);
    size_t size=strlen(text)+1;
    int fd=memfd_create("yoga-keymap",MFD_CLOEXEC);
    if (fd<0 || ftruncate(fd,(off_t)size)<0 || write(fd,text,size)!=(ssize_t)size) return 4;
    struct zwp_virtual_keyboard_v1 *keyboard=zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager,seat);
    zwp_virtual_keyboard_v1_keymap(keyboard,WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1,fd,(uint32_t)size);
    if (wl_display_roundtrip(display)<0) return 5;
    close(fd);free(text);
    char line[128],name[64],op;
    unsigned cp,mod;
    xkb_layout_index_t last_group=0;
    puts("ready");fflush(stdout);
    while (fgets(line,sizeof(line),stdin)) {
        unsigned requested_group;
        if (sscanf(line,"g %u",&requested_group)==1 && requested_group<2) {
            last_group=requested_group;
            zwp_virtual_keyboard_v1_modifiers(keyboard,0,0,0,last_group);
            if (wl_display_roundtrip(display)<0) break;
            continue;
        }
        xkb_keysym_t symbol=XKB_KEY_NoSymbol;
        int named=0;
        if (sscanf(line,"t %u %u",&cp,&mod)==2) symbol=xkb_utf32_to_keysym(cp);
        else if (sscanf(line,"%c %63s %u",&op,name,&mod)==3 && op=='k') {
            symbol=xkb_keysym_from_name(name,XKB_KEYSYM_NO_FLAGS);
            named=1;
        }
        if (!symbol || mod>15) { puts("input-error");fflush(stdout);continue; }
        xkb_keycode_t found=0;
        xkb_layout_index_t group=0;
        xkb_level_index_t level=0;
        // Search the entire selected layout before trying another layout.
        // Searching both groups per key picked US period before Russian period.
        for (xkb_layout_index_t offset=0;offset<2&&!found;offset++) {
            xkb_layout_index_t wanted=(last_group+offset)%2;
            for (xkb_keycode_t key=xkb_keymap_min_keycode(map);key<=xkb_keymap_max_keycode(map)&&!found;key++) {
                xkb_layout_index_t groups=xkb_keymap_num_layouts_for_key(map,key);
                xkb_layout_index_t g=groups==1 ? 0 : wanted;
                if (g>=groups) continue;
                for (xkb_level_index_t l=0;l<2&&!found;l++) {
                    const xkb_keysym_t *syms;
                    int n=xkb_keymap_key_get_syms_by_level(map,key,g,l,&syms);
                    if (n==1 && syms[0]==symbol) {found=key;group=groups==1 ? last_group : g;level=l;}
                }
            }
        }
        if (!found) {puts("input-error");fflush(stdout);continue;}
        // Neutral keys (space, Backspace, arrows) must preserve the previous
        // language even when XKB stores their identical symbol only in group 0.
        if (symbol == 0x20 || named) group=last_group;
        // A fallback symbol must not change the user-selected language.
        uint32_t mods=level ? mask(map,XKB_MOD_NAME_SHIFT) : 0;
        if (mod&1) mods|=mask(map,XKB_MOD_NAME_CTRL);
        if (mod&2) mods|=mask(map,XKB_MOD_NAME_ALT);
        if (mod&4) mods|=mask(map,XKB_MOD_NAME_LOGO);
        if (mod&8) mods|=mask(map,XKB_MOD_NAME_SHIFT);
        zwp_virtual_keyboard_v1_modifiers(keyboard,mods,0,0,group);
        zwp_virtual_keyboard_v1_key(keyboard,now(),found-8,WL_KEYBOARD_KEY_STATE_PRESSED);
        zwp_virtual_keyboard_v1_key(keyboard,now(),found-8,WL_KEYBOARD_KEY_STATE_RELEASED);
        zwp_virtual_keyboard_v1_modifiers(keyboard,0,0,0,last_group);
        if (wl_display_roundtrip(display)<0) break;
    }
    zwp_virtual_keyboard_v1_modifiers(keyboard,0,0,0,0);
    zwp_virtual_keyboard_v1_destroy(keyboard);
    wl_display_flush(display);wl_display_disconnect(display);
    xkb_keymap_unref(map);xkb_context_unref(context);
    return 0;
}
