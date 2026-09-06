/* Hardware adapter only: libdragon owns input, RDPQ, depth and presentation.
 * See bridge.h and docs/architecture.md for the Zig N32 / C O64 boundary. */
#include <libdragon.h>
#include <stdint.h>
#include <stddef.h>
#include "bridge.h"
_Static_assert(INITIAL_VIEWS >= 1 && INITIAL_VIEWS <= 4, "INITIAL_VIEWS must be 1..4");

static const color_t player_colors[4] = {
    {239,137,101,255}, {122,184,232,255}, {234,199,98,255}, {178,154,223,255}
};

static void input(void) {
    joypad_poll();
    for (unsigned i = 0; i < 4; i++) {
        joypad_port_t port = (joypad_port_t)i;
        joypad_inputs_t stick = joypad_get_inputs(port);
        joypad_buttons_t held = joypad_get_buttons(port);
        joypad_buttons_t pressed = joypad_get_buttons_pressed(port);
        int x = stick.stick_x, y = stick.stick_y;
        if (held.d_left) x = -80;
        if (held.d_right) x = 80;
        if (held.d_up) y = 80;
        if (held.d_down) y = -80;
        uint32_t word = (uint8_t)x | ((uint32_t)(uint8_t)y << 8) | (i << 30);
        if (pressed.a) word |= 1 << 16;
        if (held.c_left || held.l) word |= 1 << 17;
        if (held.c_right || held.r) word |= 1 << 18;
        if (pressed.b) word |= 1 << 19;
        game_input(word);
        if (i == 0) {
            if (pressed.start) game_command(1);
            if (pressed.z) game_command(2);
            if (pressed.c_down) game_command(3);
        }
    }
}

static unsigned transform_us, submit_us, triangles;
static void draw_scene(unsigned player) {
    uint64_t start_time = get_ticks_us();
    unsigned count = scene_render(player);
    transform_us += get_ticks_us() - start_time;
    start_time = get_ticks_us();
    triangles += count;
    viewport_t v = scene_view;
    rdpq_set_scissor(v.x, v.y, v.x + v.w, v.y + v.h);
    rdpq_clear(RGBA32(191,215,205,255));
    rdpq_set_mode_standard();
    rdpq_mode_antialias(AA_STANDARD);
    rdpq_mode_combiner(RDPQ_COMBINER_SHADE);
    rdpq_mode_zbuf(true, true);
    for (unsigned i = 0; i < count; i++) {
        const triangle_t *t = &scene_triangles[i];
        float r = (t->color >> 24) / 255.0f;
        float g = ((t->color >> 16) & 255) / 255.0f;
        float b = ((t->color >> 8) & 255) / 255.0f;
        float vertices[3][7];
        for (unsigned j = 0; j < 3; j++) {
            vertices[j][0] = t->v[j].x / 16.0f;
            vertices[j][1] = t->v[j].y / 16.0f;
            vertices[j][2] = t->v[j].z / 65535.0f;
            vertices[j][3] = r;
            vertices[j][4] = g;
            vertices[j][5] = b;
            vertices[j][6] = 1.0f;
        }
        rdpq_triangle(&TRIFMT_ZBUF_SHADE, vertices[0], vertices[1], vertices[2]);
    }
    rdpq_set_mode_fill(player_colors[player]);
    rdpq_fill_rectangle(v.x, v.y, v.x + v.w, v.y + 2);
    rdpq_set_mode_standard();
    rdpq_text_printf(NULL, 1, v.x + 6, v.y + 13, "P%d", player + 1);
    submit_us += get_ticks_us() - start_time;
    if (scene_overflow) debugf("triangle capacity exceeded: %lu\n", (unsigned long)scene_overflow);
}

int main(void) {
    debug_init_isviewer();
    debug_init_usblog();
    display_init(RESOLUTION_320x240, DEPTH_16_BPP, 3, GAMMA_NONE, FILTERS_RESAMPLE);
    joypad_init();
    rdpq_init();
#ifdef RDPQ_VALIDATE
    rdpq_debug_start();
#endif
    rdpq_text_register_font(1, rdpq_font_load_builtin(FONT_BUILTIN_DEBUG_VAR));
    surface_t depth = surface_alloc(FMT_RGBA16, 320, 240);
    game_reset(0);
    for (unsigned i = 0; i < INITIAL_VIEWS % 4; i++) game_command(1);
    if (AUTOTOUR) game_command(2);
    debugf("Bunny Meadow: Zig simulation / RDPQ rasterization / 4 controllers\n");
    uint64_t previous = get_ticks_us();
    uint32_t accumulator = 0;
    unsigned frame_count = 0, fps = 0;
    uint64_t fps_time = previous;
    while (1) {
        surface_t *screen = display_get();
        uint64_t now = get_ticks_us();
        uint64_t elapsed = now - previous;
        previous = now;
        // Fixed 60 Hz simulation, bounded catch-up after pauses or breakpoints.
        accumulator += elapsed > 250005 ? 250005 : (uint32_t)elapsed;
        unsigned steps = accumulator / 16667;
        accumulator %= 16667;
        input();
        game_tick(steps);
        uint32_t status = game_status();
        unsigned views = status & 255;
        rdpq_attach(screen, &depth);
        rdpq_clear(RGBA32(42,61,57,255));
        rdpq_clear_z(ZBUF_MAX);
        transform_us = submit_us = triangles = 0;
        for (unsigned i = 0; i < views; i++) draw_scene(i);
        rdpq_set_scissor(0, 0, 320, 240);
        if (views >= 3) {
            // Keep viewport scissor X aligned to four pixels for RDP fill
            // mode, then place the visual separator over their common edge.
            rdpq_set_mode_fill(RGBA32(42,61,57,255));
            rdpq_fill_rectangle(159, views == 3 ? 121 : 16, 161, 224);
        }
        rdpq_set_mode_standard();
        rdpq_text_printf(NULL, 1, 7, 11, "BUNNY MEADOW   /   %d PLAYER%s", views, views == 1 ? "" : "S");
        rdpq_text_printf(NULL, 1, 269, 11, "%d FPS", fps);
        rdpq_text_print(NULL, 1, 7, 234, "START VIEWS   A HOP   C/L/R LOOK   Z TOUR");
#if PROFILE
        rdpq_text_printf(NULL, 1, 8, 219, "CPU %ums / SUBMIT %ums / %u TRI", transform_us/1000, submit_us/1000, triangles);
#endif
        if (status & 256) rdpq_text_print(NULL, 1, 230, 219, "AUTO TOUR");
        rdpq_detach_show();
        frame_count++;
        if (now - fps_time >= 1000000) {
            fps = (unsigned)(frame_count * 1000000ULL / (now - fps_time));
            frame_count = 0;
            fps_time = now;
#ifdef RDPQ_VALIDATE
            debugf("RDPQ validation heartbeat: %u views, %u FPS, %u triangles\n", views, fps, triangles);
#endif
        }
    }
}
