#include <libdragon.h>
#include <stdint.h>
#include <stdio.h>

enum {
    MOVE_LEFT = 0,
    MOVE_RIGHT = 1,
    MOVE_UP = 2,
    MOVE_DOWN = 3,
    STATUS_PLAYING = 0,
    STATUS_WON = 1,
    STATUS_LOST = 2,
};

/* Scalar-only exports from game.zig; see docs/architecture.md. */
extern uint32_t game_reset(uint32_t seed);
extern uint32_t game_move(uint32_t direction);
extern uint32_t game_keep_playing(void);
extern uint32_t game_get_cell(uint32_t index);
extern uint32_t game_get_score(void);
extern uint32_t game_get_best(void);
extern uint32_t game_get_status(void);

static uint32_t rgba(int r, int g, int b) {
    return graphics_make_color(r, g, b, 255);
}
static uint32_t tile_color(uint32_t value) {
    switch (value) {
        case 0: return rgba(205, 193, 180);
        case 2: return rgba(238, 228, 218);
        case 4: return rgba(237, 224, 200);
        case 8: return rgba(242, 177, 121);
        case 16: return rgba(245, 149, 99);
        case 32: return rgba(246, 124, 95);
        case 64: return rgba(246, 94, 59);
        case 128: return rgba(237, 207, 114);
        case 256: return rgba(237, 204, 97);
        case 512: return rgba(237, 200, 80);
        case 1024: return rgba(237, 197, 63);
        case 2048: return rgba(237, 194, 46);
        default: return rgba(60, 58, 50);
    }
}

static void draw_centered(surface_t *screen, int center_x, int y, const char *text) {
    int width = 0;
    while (text[width] != '\0') width++;
    graphics_draw_text(screen, center_x - width * 4, y, text);
}

static void draw_header(surface_t *screen) {
    char score[24];
    char best[24];
    snprintf(score, sizeof(score), "SCORE %lu", (unsigned long)game_get_score());
    snprintf(best, sizeof(best), "BEST  %lu", (unsigned long)game_get_best());

    graphics_set_color(rgba(119, 110, 101), rgba(250, 248, 239));
    graphics_draw_text(screen, 12, 8, "2048");
    graphics_draw_text(screen, 12, 19, "NINTENDO 64");

    graphics_draw_box(screen, 172, 5, 136, 15, rgba(187, 173, 160));
    graphics_draw_box(screen, 172, 22, 136, 15, rgba(187, 173, 160));
    graphics_set_color(rgba(255, 255, 255), rgba(187, 173, 160));
    draw_centered(screen, 240, 9, score);
    draw_centered(screen, 240, 26, best);
}

static void draw_board(surface_t *screen) {
    const int board_x = 68;
    const int board_y = 43;
    const int tile = 41;
    const int gap = 4;

    graphics_draw_box(screen, board_x, board_y, tile * 4 + gap * 5,
                      tile * 4 + gap * 5, rgba(187, 173, 160));

    for (uint32_t index = 0; index < 16; index++) {
        int row = index / 4;
        int column = index % 4;
        int x = board_x + gap + column * (tile + gap);
        int y = board_y + gap + row * (tile + gap);
        uint32_t value = game_get_cell(index);
        graphics_draw_box(screen, x, y, tile, tile, tile_color(value));

        if (value != 0) {
            char label[12];
            snprintf(label, sizeof(label), "%lu", (unsigned long)value);
            uint32_t foreground = value <= 4 ? rgba(119, 110, 101) : rgba(249, 246, 242);
            graphics_set_color(foreground, tile_color(value));
            draw_centered(screen, x + tile / 2, y + 16, label);
        }
    }
}

static void draw_footer(surface_t *screen) {
    graphics_set_color(rgba(119, 110, 101), rgba(250, 248, 239));
    draw_centered(screen, 160, 231, "STICK/D-PAD MOVE   START NEW GAME");
}

static void draw_overlay(surface_t *screen, uint32_t status) {
    if (status == STATUS_PLAYING) return;

    graphics_draw_box(screen, 89, 107, 142, 45, rgba(60, 58, 50));
    graphics_set_color(rgba(255, 255, 255), rgba(60, 58, 50));
    if (status == STATUS_WON) {
        draw_centered(screen, 160, 116, "YOU MADE 2048!");
        draw_centered(screen, 160, 134, "A CONTINUE  START NEW");
    } else {
        draw_centered(screen, 160, 116, "GAME OVER");
        draw_centered(screen, 160, 134, "PRESS START");
    }
}

static int requested_move(joypad_buttons_t pressed) {
    if (pressed.d_left) return MOVE_LEFT;
    if (pressed.d_right) return MOVE_RIGHT;
    if (pressed.d_up) return MOVE_UP;
    if (pressed.d_down) return MOVE_DOWN;

    int x = joypad_get_axis_pressed(JOYPAD_PORT_1, JOYPAD_AXIS_STICK_X);
    int y = joypad_get_axis_pressed(JOYPAD_PORT_1, JOYPAD_AXIS_STICK_Y);
    if (x < 0) return MOVE_LEFT;
    if (x > 0) return MOVE_RIGHT;
    if (y > 0) return MOVE_UP;
    if (y < 0) return MOVE_DOWN;
    return -1;
}

int main(void) {
    debug_init_isviewer();
    debug_init_usblog();
    display_init(RESOLUTION_320x240, DEPTH_16_BPP, 3, GAMMA_NONE, FILTERS_RESAMPLE);
    joypad_init();
    game_reset((uint32_t)get_ticks());
    debugf("n64-2048: started\n");

    while (1) {
        joypad_poll();
        joypad_buttons_t pressed = joypad_get_buttons_pressed(JOYPAD_PORT_1);

        if (pressed.start) {
            game_reset((uint32_t)get_ticks());
            debugf("n64-2048: new game\n");
        } else if (game_get_status() == STATUS_WON && pressed.a) {
            game_keep_playing();
        } else {
            int direction = requested_move(pressed);
            if (direction >= 0 && game_move((uint32_t)direction)) {
                debugf("n64-2048: move=%d score=%lu\n", direction,
                       (unsigned long)game_get_score());
            }
        }

        surface_t *screen = display_get();
        graphics_fill_screen(screen, rgba(250, 248, 239));
        draw_header(screen);
        draw_board(screen);
        draw_footer(screen);
        draw_overlay(screen, game_get_status());
        display_show(screen);
    }
}
