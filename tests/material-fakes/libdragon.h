/* Narrow test doubles for material.c; runtime RDP validation remains separate. */
#ifndef MATERIAL_TEST_LIBDRAGON_H
#define MATERIAL_TEST_LIBDRAGON_H
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#define assertf(condition, ...) assert(condition)
enum { FMT_RGBA16, TILE0, TLUT_NONE, FILTER_BILINEAR };
enum { RDPQ_COMBINER_SHADE = 1, RDPQ_COMBINER_TEX_SHADE = 2 };
#define REPEAT_INFINITE 2048
typedef struct { void *buffer; unsigned format, width, height, stride; } surface_t;
typedef struct { struct { float repeats; } s, t; } rdpq_texparms_t;
static inline surface_t surface_make(void *buffer, unsigned format, unsigned width, unsigned height, unsigned stride) {
    return (surface_t){buffer, format, width, height, stride};
}
void data_cache_hit_writeback(void *data, size_t size);
int rdpq_tex_upload(unsigned tile, const surface_t *surface, const rdpq_texparms_t *params);
void rdpq_mode_tlut(unsigned mode);
void rdpq_mode_combiner(unsigned combiner);
void rdpq_mode_persp(bool enabled);
void rdpq_mode_filter(unsigned mode);
#endif
