#include <libdragon.h>
#include <t3d/t3d.h>
#include "bridge.h"
#include "material.h"

static unsigned uploads, draw_flags, combiner, cache_writes;
static bool tmem_valid, perspective, bilinear;
static void *texture_source;

void data_cache_hit_writeback(void *data, size_t size) {
    assert(data != NULL && size == 512 && (uintptr_t)data % 8 == 0);
    texture_source = data;
    cache_writes++;
}
int rdpq_tex_upload(unsigned tile, const surface_t *surface, const rdpq_texparms_t *params) {
    assert(tile == TILE0 && surface->format == FMT_RGBA16);
    assert(surface->width == 16 && surface->height == 16 && surface->stride == 32);
    assert(surface->buffer == texture_source);
    assert(params->s.repeats == REPEAT_INFINITE && params->t.repeats == REPEAT_INFINITE);
    uploads++;
    tmem_valid = true;
    return 512;
}
void rdpq_mode_tlut(unsigned mode) { assert(mode == TLUT_NONE); }
void rdpq_mode_combiner(unsigned mode) { combiner = mode; }
void rdpq_mode_persp(bool enabled) { perspective = enabled; }
void rdpq_mode_filter(unsigned mode) { bilinear = mode == FILTER_BILINEAR; }
void t3d_state_set_drawflags(unsigned flags) { draw_flags = flags; }

int main(void) {
    material_init();
    assert(cache_writes == TEXTURED);
    unsigned expected_uploads = 0;
    for (unsigned views = 1; views <= 4; views++) for (unsigned view = 0; view < views; view++) {
        material_view_begin();
#if TEXTURED
        // Multiple visible ground batches use one upload. A previous view's
        // font data must never be reused as ground texture data.
        material_bind(MATERIAL_GROUND);
        expected_uploads++;
        assert(uploads == expected_uploads && tmem_valid && perspective && bilinear);
        assert(combiner == RDPQ_COMBINER_TEX_SHADE && (draw_flags & T3D_FLAG_TEXTURED));
        material_bind(MATERIAL_GROUND);
        assert(uploads == expected_uploads);
#endif
        material_bind(MATERIAL_FLAT);
        assert(combiner == RDPQ_COMBINER_SHADE && !(draw_flags & T3D_FLAG_TEXTURED));
        assert((draw_flags & (T3D_FLAG_DEPTH | T3D_FLAG_CULL_BACK)) == (T3D_FLAG_DEPTH | T3D_FLAG_CULL_BACK));
        // Simulate the HUD replacing TMEM/tile state before the next camera.
        tmem_valid = false;
        combiner = 0;
        perspective = bilinear = false;
    }
    // A fully culled ground still allows ordinary world/actor drawing.
    material_view_begin();
    material_bind(MATERIAL_FLAT);
    assert(uploads == expected_uploads && combiner == RDPQ_COMBINER_SHADE);
    return 0;
}
