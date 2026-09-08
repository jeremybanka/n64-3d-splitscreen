#ifndef TEMPLATE_MATERIAL_H
#define TEMPLATE_MATERIAL_H
#include <stdint.h>

/* Adapter-side RDP/Tiny3D state. No calls cross the Zig ABI. */
void material_init(void);
void material_view_begin(void);
void material_bind(uint32_t material);
#endif
