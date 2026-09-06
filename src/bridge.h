#ifndef BUNNY_BRIDGE_H
#define BUNNY_BRIDGE_H
#include <stdint.h>
/* Callable seam: at most one uint32_t argument and one uint32_t result. */
uint32_t game_reset(uint32_t unused);
uint32_t game_input(uint32_t packed);
uint32_t game_tick(uint32_t steps);
uint32_t game_command(uint32_t command);
uint32_t game_status(void);
uint32_t scene_render(uint32_t view);
/* Shared data uses explicit 32-bit fields with identical target layout.
 * It is consumed synchronously; RDPQ copies each triangle before the next view. */
typedef struct { int32_t x, y, z; } vertex_t;
typedef struct { vertex_t v[3]; uint32_t color; } triangle_t;
typedef struct { int32_t x, y, w, h; } viewport_t;
extern triangle_t scene_triangles[2048];
extern viewport_t scene_view;
extern uint32_t scene_overflow;
_Static_assert(sizeof(triangle_t) == 40, "Zig/C triangle layout");
_Static_assert(sizeof(viewport_t) == 16, "Zig/C viewport layout");
#endif
