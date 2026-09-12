/* Hardware adapter only: libdragon owns input, RDPQ, depth and presentation.
 * See bridge.h and docs/architecture.md for the Zig N32 / C O64 boundary. */
#include <libdragon.h>
#include <stdint.h>
#include <stddef.h>
#include "bridge.h"
#include "sound.h"
#include <t3d/t3d.h>
_Static_assert(sizeof(T3DVertPacked) == sizeof(packed_vertex_t), "RSP vertex layout");
_Static_assert(INITIAL_VIEWS >= 1 && INITIAL_VIEWS <= 4, "INITIAL_VIEWS must be 1..4");

static const color_t player_colors[4] = {
    {239,137,101,255}, {122,184,232,255}, {234,199,98,255}, {178,154,223,255}
};

static void input(void) {
    joypad_poll();
    uint32_t connected = 0;
    for (unsigned i = 0; i < 4; i++)
        if (joypad_is_connected((joypad_port_t)i)) connected |= 1u << i;
    game_connections(connected);
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
        if (held.a) word |= 1 << 20;
        if (held.b) word |= 1 << 21;
        if (held.start || held.z || held.c_down || held.c_up) word |= 1 << 22;
        bool ready = game_input(word) != 0;
        if (i == 0 && ready) {
            if (pressed.start) game_command(GAME_CYCLE_VIEWS);
            if (pressed.z) game_command(GAME_TOGGLE_TOUR);
            if (pressed.c_down) game_command(GAME_RESTART);
            if (pressed.c_up) game_command(GAME_TOGGLE_PAUSE);
        }
    }
}

static unsigned transform_us, submit_us, triangles;
static T3DViewport viewports[3][4] __attribute__((aligned(16)));
static rspq_block_t *environment_blocks[64], *rabbit_blocks[3][4];
static int16_t environment_bounds[64][6];
static rspq_syncpoint_t frame_fences[3];
static bool frame_pending[3];
static unsigned frame_slot;

static rspq_block_t *record_mesh(const mesh_t *mesh, packed_vertex_t *vertices, unsigned first, unsigned end) {
    rspq_block_begin();
    for (unsigned i = first; i < end; i++) {
        const batch_t *b = &mesh->batches[i];
        t3d_vert_load((T3DVertPacked *)&vertices[b->vertex_offset / 2], 0, (b->vertex_count + 1) & ~1u);
        for (unsigned j = b->index_offset; j < b->index_offset + b->index_count; j += 3)
            t3d_tri_draw(mesh->indices[j], mesh->indices[j+2], mesh->indices[j+1]);
        t3d_tri_sync();
    }
    return rspq_block_end();
}

static void init_scene(void) {
    assertf(scene_init(0) == 0, "Scene exceeds packed vertex capacity");
    data_cache_hit_writeback(&scene_environment, sizeof(scene_environment));
    data_cache_hit_writeback(scene_frames, sizeof(scene_frames));
    for (unsigned b = 0; b < scene_environment.batch_count; b++) {
        environment_blocks[b] = record_mesh(&scene_environment, scene_environment.vertices, b, b+1);
        const batch_t *batch = &scene_environment.batches[b];
        for (unsigned axis = 0; axis < 3; axis++) {
            environment_bounds[b][axis] = INT16_MAX;
            environment_bounds[b][axis+3] = INT16_MIN;
        }
        for (unsigned j = batch->vertex_offset; j < batch->vertex_offset + batch->vertex_count; j++) {
            packed_vertex_t *v = &scene_environment.vertices[j/2];
            int16_t *p = j%2 ? v->pos_b : v->pos_a;
            for (unsigned axis = 0; axis < 3; axis++) {
                if (p[axis] < environment_bounds[b][axis]) environment_bounds[b][axis] = p[axis];
                if (p[axis] > environment_bounds[b][axis+3]) environment_bounds[b][axis+3] = p[axis];
            }
        }
    }
    for (unsigned f = 0; f < 3; f++) for (unsigned p = 0; p < 4; p++) {
        viewports[f][p] = t3d_viewport_create();
        rabbit_blocks[f][p] = record_mesh(&scene_rabbit, scene_frames[f][p], 0, scene_rabbit.batch_count);
    }
    debugf("RSP meshes: environment %lu vertices/%lu tris, rabbit %lu vertices/%lu tris\n",
        scene_environment.vertex_count, scene_environment.index_count/3,
        scene_rabbit.vertex_count, scene_rabbit.index_count/3);
}

static void prepare_scene(void) {
    if (frame_pending[frame_slot]) {
        rspq_flush();
        while (!rspq_syncpoint_check(frame_fences[frame_slot])) sound_service();
    }
    uint64_t start = get_ticks_us();
    scene_prepare(frame_slot);
    triangles = 0;
    for (unsigned p = 0; p < 4; p++)
        data_cache_hit_writeback(scene_frames[frame_slot][p], ((scene_rabbit.vertex_count + 1) / 2) * sizeof(packed_vertex_t));
    transform_us = get_ticks_us() - start;
    submit_us = 0;
}

static void draw_scene(unsigned view, uint32_t status) {
    uint64_t start_time = get_ticks_us();
    unsigned player = game_view_port(view);
    viewport_t v = scene_views[view];
    camera_t *cam = &scene_cameras[view];
    T3DViewport *vp = &viewports[frame_slot][view];
    T3DVec3 eye = {{cam->eye[0]/64.0f, cam->eye[1]/64.0f, cam->eye[2]/64.0f}};
    T3DVec3 target = {{cam->target[0]/64.0f, cam->target[1]/64.0f, cam->target[2]/64.0f}};
    t3d_viewport_set_area(vp, v.x, v.y, v.w, v.h);
    t3d_viewport_set_projection(vp, 0.78958224f, 4.0f, 320.0f);
    t3d_viewport_look_at(vp, &eye, &target, &(T3DVec3){{0,1,0}});
    // Convert the game's +Z-forward basis and Q8 units for Tiny3D. Keep
    // clip-space W in a useful range for the RSP's reciprocal/screen scales.
    for (unsigned row = 0; row < 4; row++) vp->matCamera.m[row][0] *= -1.0f;
    for (unsigned row = 0; row < 3; row++) for (unsigned col = 0; col < 3; col++)
        vp->matCamera.m[row][col] *= 1.0f/64.0f;
    t3d_mat4_mul(&vp->matCamProj, &vp->matProj, &vp->matCamera);
    t3d_mat4_to_frustum(&vp->viewFrustum, &vp->matCamProj);
    t3d_viewport_attach(vp);
    rdpq_clear(RGBA32(191,215,205,255));
    t3d_frame_start();
    rdpq_mode_dithering(DITHER_NONE_NONE);
    rdpq_mode_combiner(RDPQ_COMBINER_SHADE);
    const uint8_t ambient[4] = {255,255,255,255};
    t3d_light_set_ambient(ambient);
    t3d_light_set_count(0);
    t3d_state_set_drawflags(T3D_FLAG_SHADED | T3D_FLAG_DEPTH | T3D_FLAG_CULL_BACK);
    for (unsigned b = 0; b < scene_environment.batch_count; b++) {
        if (!t3d_frustum_vs_aabb_s16(&vp->viewFrustum, environment_bounds[b], environment_bounds[b]+3)) continue;
        rspq_block_run(environment_blocks[b]);
        triangles += scene_environment.batches[b].index_count/3;
    }
    t3d_state_set_drawflags(T3D_FLAG_SHADED | T3D_FLAG_DEPTH | T3D_FLAG_CULL_BACK);
    for (unsigned p = 0; p < 4; p++) {
        if (!(status & (1u << (16 + p)))) continue;
        if (!t3d_frustum_vs_aabb_s16(&vp->viewFrustum, scene_bounds[p], scene_bounds[p]+3)) continue;
        rspq_block_run(rabbit_blocks[frame_slot][p]);
        triangles += scene_rabbit.index_count/3;
    }
    rdpq_set_mode_fill(player_colors[player]);
    rdpq_fill_rectangle(v.x, v.y, v.x + v.w, v.y + 2);
    rdpq_set_mode_standard();
    rdpq_text_printf(NULL, 1, v.x + 6, v.y + 13, "P%d%s", player + 1,
        BENCHMARK ? " TEST" : status & (1u << (12 + player)) ? "" : " OFF");
    submit_us += get_ticks_us() - start_time;
}

int main(void) {
    debug_init_isviewer();
    debug_init_usblog();
    display_init(RESOLUTION_320x240, DEPTH_16_BPP, 3, GAMMA_NONE, FILTERS_RESAMPLE);
    joypad_init();
    rdpq_init();
    t3d_init((T3DInitParams){});
#ifdef RDPQ_VALIDATE
    rdpq_debug_start();
#endif
    rdpq_text_register_font(1, rdpq_font_load_builtin(FONT_BUILTIN_DEBUG_VAR));
    surface_t depth = surface_alloc(FMT_RGBA16, 320, 240);
    game_reset(0);
    init_scene();
    for (unsigned i = 0; i < INITIAL_VIEWS % 4; i++) game_command(GAME_CYCLE_VIEWS);
    if (AUTOTOUR) game_command(GAME_TOGGLE_TOUR);
    sound_init();
    sound_update(game_status());
    sound_service(); // Prime output before the first display wait.
    debugf("Bunny Meadow: Zig simulation / RDPQ rasterization / 4 controllers\n");
    uint64_t previous = get_ticks_us();
    uint32_t accumulator = 0;
    unsigned frame_count = 0, fps = 0, benchmark_phase = 0;
    uint64_t fps_time = previous;
    while (1) {
        sound_service();
        surface_t *screen;
        while (!(screen = display_try_get())) sound_service();
        uint64_t now = get_ticks_us();
        uint64_t elapsed = now - previous;
        previous = now;
        // Fixed 60 Hz simulation, bounded catch-up after pauses or breakpoints.
        accumulator += elapsed > 250005 ? 250005 : (uint32_t)elapsed;
        unsigned steps = accumulator / 16667;
        accumulator %= 16667;
        if (BENCHMARK) benchmark_phase = game_benchmark(steps);
        else {
            input();
            game_tick(steps);
        }
        uint32_t status = game_status();
        sound_update(status);
        sound_service();
        unsigned views = status & 255;
        rdpq_attach(screen, &depth);
        rdpq_clear(RGBA32(42,61,57,255));
        rdpq_clear_z(ZBUF_MAX);
        prepare_scene();
        for (unsigned i = 0; i < views; i++) {
            draw_scene(i, status);
            sound_service();
        }
        rdpq_set_scissor(0, 0, 320, 240);
        if (views >= 3) {
            // Keep viewport scissor X aligned to four pixels for RDP fill
            // mode, then place the visual separator over their common edge.
            rdpq_set_mode_fill(RGBA32(42,61,57,255));
            rdpq_fill_rectangle(159, views == 3 ? 121 : 16, 161, 224);
        }
        rdpq_set_mode_standard();
        rdpq_text_printf(NULL, 1, 7, 11, "BUNNY MEADOW   /   %d VIEW%s", views, views == 1 ? "" : "S");
        rdpq_text_printf(NULL, 1, 269, 11, "%d FPS", fps);
        rdpq_text_print(NULL, 1, 7, 234, "START VIEWS   A HOP   C-UP PAUSE   Z TOUR");
#if PROFILE
        rdpq_text_printf(NULL, 1, 8, 219, "CPU %ums / SUBMIT %ums / %u TRI", transform_us/1000, submit_us/1000, triangles);
#endif
        if (BENCHMARK) rdpq_text_printf(NULL, 1, 230, 206, "TEST %u", benchmark_phase);
        if (status & GAME_STATUS_PAUSED) rdpq_text_print(NULL, 1, 230, 219, "PAUSED");
        else if (status & GAME_STATUS_TOUR) rdpq_text_print(NULL, 1, 230, 219, "AUTO TOUR");
        rdpq_detach_show();
        frame_fences[frame_slot] = rspq_syncpoint_new();
        frame_pending[frame_slot] = true;
        frame_slot = (frame_slot + 1) % 3;
        sound_service();
        frame_count++;
        if (now - fps_time >= 1000000) {
            fps = (unsigned)(frame_count * 1000000ULL / (now - fps_time));
            sound_stats_t audio = sound_take_stats();
            unsigned audio_us = audio.mix_us / frame_count;
            (void)audio_us; // Only printed in diagnostic builds.
            frame_count = 0;
            fps_time = now;
#if PROFILE || BENCHMARK || defined(RDPQ_VALIDATE)
            debugf("PERF views=%u phase=%u fps=%u cpu_us=%u submit_us=%u triangles=%u "
                "audio=%u audio_us=%u audio_buffers=%lu audio_gap_us=%lu audio_budget_us=%lu "
                "audio_sfx=%lu audio_overlap=%lu workload=2\n",
                views, benchmark_phase, fps, transform_us, submit_us, triangles,
                AUDIO, audio_us, audio.buffers, audio.max_gap_us, audio.budget_us, audio.starts, audio.overlap);
#endif
        }
    }
}
