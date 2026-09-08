#ifndef BUNNY_SOUND_H
#define BUNNY_SOUND_H
#include <stdint.h>
/* C-only platform helper; structs never cross the Zig/C bridge. */
typedef struct {
    uint32_t mix_us, buffers, max_gap_us, budget_us, starts, overlap;
} sound_stats_t;
void sound_init(void);
void sound_update(uint32_t game_status);
void sound_service(void);
sound_stats_t sound_take_stats(void);
#endif
