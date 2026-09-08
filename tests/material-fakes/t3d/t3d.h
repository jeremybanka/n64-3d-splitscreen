#ifndef MATERIAL_TEST_T3D_H
#define MATERIAL_TEST_T3D_H
enum { T3D_FLAG_DEPTH = 1, T3D_FLAG_TEXTURED = 2, T3D_FLAG_SHADED = 4, T3D_FLAG_CULL_BACK = 16 };
void t3d_state_set_drawflags(unsigned flags);
#endif
