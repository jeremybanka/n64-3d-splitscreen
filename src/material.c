#include <libdragon.h>
#include <t3d/t3d.h>
#include "bridge.h"
#include "material.h"

_Static_assert(TEXTURED == 0 || TEXTURED == 1, "TEXTURED must be 0 or 1");
static uint32_t bound_material;

#if TEXTURED
#include "generated/ground_texture.h"
_Static_assert(sizeof(ground_texture_pixels) == 512, "Ground texture is 16x16 RGBA16");
_Static_assert(sizeof(ground_texture_pixels) <= 4096, "Texture must fit RDP TMEM");
static surface_t ground_texture;
static bool texture_uploaded;
#endif

void material_init(void) {
#if TEXTURED
    ground_texture = surface_make((void *)ground_texture_pixels, FMT_RGBA16, 16, 16, 32);
    // Texture data lives in RDRAM for the program lifetime and never changes.
    data_cache_hit_writeback((void *)ground_texture_pixels, sizeof(ground_texture_pixels));
#endif
}

void material_view_begin(void) {
    // The previous view's HUD uses TMEM and tile descriptors. Never assume the
    // world texture survives it, even when this view uses the same material.
    bound_material = UINT32_MAX;
#if TEXTURED
    texture_uploaded = false;
#endif
}

void material_bind(uint32_t material) {
    assertf(material <= MATERIAL_GROUND, "Unknown scene material %lu", material);
    if (bound_material == material) return;
    const unsigned flags = T3D_FLAG_SHADED | T3D_FLAG_DEPTH | T3D_FLAG_CULL_BACK;
#if TEXTURED
    if (material == MATERIAL_GROUND) {
        if (!texture_uploaded) {
            int used = rdpq_tex_upload(TILE0, &ground_texture, &(rdpq_texparms_t){
                .s.repeats = REPEAT_INFINITE, .t.repeats = REPEAT_INFINITE,
            });
            assertf(used == 512, "Unexpected texture TMEM cost: %d", used);
            texture_uploaded = true;
        }
        rdpq_mode_tlut(TLUT_NONE);
        rdpq_mode_combiner(RDPQ_COMBINER_TEX_SHADE);
        rdpq_mode_persp(true);
        rdpq_mode_filter(FILTER_BILINEAR);
        t3d_state_set_drawflags(flags | T3D_FLAG_TEXTURED);
    } else
#else
    assertf(material == MATERIAL_FLAT, "Textured material in a flat build");
#endif
    {
        rdpq_mode_combiner(RDPQ_COMBINER_SHADE);
        t3d_state_set_drawflags(flags);
    }
    bound_material = material;
}
