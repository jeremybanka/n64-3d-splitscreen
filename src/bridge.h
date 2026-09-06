#ifndef BUNNY_BRIDGE_H
#define BUNNY_BRIDGE_H
#include <stdint.h>
/* Callable seam: at most one uint32_t argument and one uint32_t result. */
uint32_t game_reset(uint32_t unused);
uint32_t game_input(uint32_t packed);
uint32_t game_tick(uint32_t steps);
uint32_t game_command(uint32_t command);
uint32_t game_status(void);
uint32_t game_benchmark(uint32_t steps);
uint32_t scene_init(uint32_t unused);
uint32_t scene_prepare(uint32_t frame);
/* Packed RSP data and fixed-width camera inputs; no aggregate calls. */
typedef struct { int16_t pos_a[3]; uint16_t norm_a; int16_t pos_b[3]; uint16_t norm_b; uint32_t color_a, color_b; int16_t uv_a[2], uv_b[2]; } packed_vertex_t;
typedef struct { uint32_t vertex_offset, vertex_count, index_offset, index_count; } batch_t;
typedef struct {
    packed_vertex_t vertices[1024];
    batch_t batches[64];
    uint8_t indices[4096];
    uint32_t vertex_count, index_count, batch_count;
} mesh_t;
typedef struct { int32_t x, y, w, h; } viewport_t;
typedef struct { int32_t eye[3], target[3]; } camera_t;
#define FRAME_PAIRS 384
extern mesh_t scene_environment, scene_rabbit;
extern packed_vertex_t scene_frames[3][4][FRAME_PAIRS];
extern viewport_t scene_views[4];
extern camera_t scene_cameras[4];
extern int16_t scene_bounds[4][6];
extern uint32_t scene_overflow;
_Static_assert(sizeof(packed_vertex_t) == 32, "Zig/C packed vertex layout");
_Static_assert(sizeof(viewport_t) == 16, "Zig/C viewport layout");
_Static_assert(sizeof(camera_t) == 24, "Zig/C camera layout");
_Static_assert(sizeof(mesh_t) == 37900, "Zig/C mesh layout");
#endif
