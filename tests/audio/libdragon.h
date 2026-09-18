/* Host seam for exercising the real sound adapter without the N64 SDK. */
#ifndef TEST_LIBDRAGON_H
#define TEST_LIBDRAGON_H
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>

#define assertf(condition, ...) assert(condition)
#define DFS_DEFAULT_LOCATION 0
#define DFS_ESUCCESS 0

/* Like the pinned streamed decoder, each open owns a mutable read cursor. */
typedef struct { unsigned position, length; bool loop; } wav64_t;
int dfs_init(int location);
void audio_init(int frequency, int buffers);
int audio_get_frequency(void);
int audio_get_buffer_length(void);
bool audio_can_write(void);
int16_t *audio_write_begin(void);
void audio_write_end(void);
void audio_write_silence(void);
void mixer_init(int channels);
void mixer_set_vol(float volume);
void mixer_ch_set_vol(int channel, float left, float right);
void mixer_ch_set_vol_pan(int channel, float volume, float pan);
void mixer_ch_stop(int channel);
bool mixer_ch_playing(int channel);
void mixer_poll(int16_t *buffer, int samples);
void wav64_open(wav64_t *wave, const char *path);
void wav64_set_loop(wav64_t *wave, bool loop);
void wav64_play(wav64_t *wave, int channel);
uint64_t get_ticks_us(void);
void debugf(const char *format, ...);
#endif
