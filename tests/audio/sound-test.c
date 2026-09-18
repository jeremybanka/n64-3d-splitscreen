/* Exercise src/sound.c against a finite, stateful streamed-audio fixture.
 * This checks cursor ownership and lifecycle, not VADPCM decoding or AI/RSP.
 * The pinned decoder continues its file cursor when seeking=false; sharing
 * that cursor across independently advancing mixer channels corrupts reads.
 */
#include <libdragon.h>
#include <stdio.h>
#include <string.h>
#include "bridge.h"
#include "sound.h"

static struct { wav64_t *wave; unsigned position; } channels[5];
static unsigned pending_events, drains, queued, mixed, silent, sdk_calls;
static uint64_t ticks;
static int16_t output[64];

uint32_t game_audio_events(void) {
    unsigned events = pending_events;
    pending_events = 0;
    drains++;
    return events;
}
int dfs_init(int location) { sdk_calls++; return DFS_ESUCCESS; }
void audio_init(int frequency, int buffers) { sdk_calls++; }
int audio_get_frequency(void) { return 22050; }
int audio_get_buffer_length(void) { return 32; }
bool audio_can_write(void) { return queued > 0; }
int16_t *audio_write_begin(void) { return output; }
void audio_write_end(void) { assert(queued); queued--; }
void audio_write_silence(void) { silent++; audio_write_end(); }
void mixer_init(int count) { assert(count == 5); sdk_calls++; }
void mixer_set_vol(float volume) {}
void mixer_ch_set_vol(int channel, float left, float right) {}
void mixer_ch_set_vol_pan(int channel, float volume, float pan) {}
void mixer_ch_stop(int channel) { channels[channel].wave = NULL; }
bool mixer_ch_playing(int channel) { return channels[channel].wave != NULL; }
void wav64_open(wav64_t *wave, const char *path) {
    *wave = (wav64_t){ .length = strstr(path, "meadow") ? 176400 : 3969 };
    sdk_calls++;
}
void wav64_set_loop(wav64_t *wave, bool loop) { wave->loop = loop; }
void wav64_play(wav64_t *wave, int channel) {
    channels[channel].wave = wave;
    channels[channel].position = 0;
}
uint64_t get_ticks_us(void) { return ++ticks; }
void debugf(const char *format, ...) {}

void mixer_poll(int16_t *buffer, int samples) {
    assert(buffer == output);
    mixed++;
    for (unsigned i = 0; i < 5; i++) {
        wav64_t *wave = channels[i].wave;
        if (!wave) continue;
        unsigned position = channels[i].position;
        if (position == 0) wave->position = 0; // Seeking resets decoder state.
        if (wave->position != position) {
            fprintf(stderr, "channel %u: decoder cursor %u, expected %u\n",
                i, wave->position, position);
            assert(wave->position == position);
        }
        unsigned count = wave->length - position;
        if (count > (unsigned)samples) count = samples;
        wave->position += count;
        channels[i].position += count;
        if (channels[i].position == wave->length) {
            if (wave->loop) channels[i].position = 0;
            else channels[i].wave = NULL;
        }
    }
}

#if AUDIO
static void service(unsigned buffers) {
    for (unsigned i = 0; i < buffers; i++) {
        queued = 1;
        sound_service();
        assert(queued == 0);
    }
}
static void update(unsigned events, uint32_t status) {
    pending_events = events;
    sound_update(status);
    assert(pending_events == 0);
}
#endif

int main(void) {
    sound_init();
#if AUDIO
    const uint32_t participants = 15u << 16;
    // Two successive reads of simultaneous effects reproduce the old fault.
    update((1u << 8) | 15u, participants);
    service(8);
    assert(sound_take_stats().overlap == 4);

    // Retrigger one voice while the other three continue at their own offsets.
    update(1u << 1, participants);
    service(8);
    assert(channels[1].position == 512);
    assert(channels[2].position == 256);
    assert(channels[3].position == 512);
    assert(channels[4].position == 512);

    // Stop-before-start must preserve a new hop in the same update.
    update((1u << 6) | (1u << 2), participants);
    service(2);
    assert(channels[3].position == 64);
    update(1u << 7, participants & ~(1u << 19));
    assert(!mixer_ch_playing(4));
    assert(mixer_ch_playing(1) && mixer_ch_playing(2) && mixer_ch_playing(3));

    unsigned music_position = channels[0].position;
    unsigned before_pause = mixed;
    update(15u, participants | GAME_STATUS_PAUSED);
    service(3);
    assert(mixed == before_pause && silent == 3);
    assert(channels[0].position == music_position);
    for (unsigned i = 1; i < 5; i++) assert(!mixer_ch_playing(i));
    update(15u, participants);
    service(1);
    assert(channels[0].position == music_position + 32);

    // Run finite effects to completion and music through multiple loop points.
    service(12000);
    assert(mixer_ch_playing(0));
    for (unsigned i = 1; i < 5; i++) assert(!mixer_ch_playing(i));
    update((1u << 8) | (15u << 4) | 15u, participants);
    service(2);
    for (unsigned i = 0; i < 5; i++) assert(channels[i].position == 64);
    puts("PASS: independent streamed voices, retrigger, removal, pause, restart and looping");
#else
    pending_events = 0x1ff;
    sound_update(15u << 16);
    sound_service();
    sound_stats_t stats = sound_take_stats();
    assert(drains == 1 && pending_events == 0 && sdk_calls == 0);
    assert(stats.starts == 0 && stats.buffers == 0 && stats.budget_us == 0);
    puts("PASS: audio-off drains events without initializing or polling audio");
#endif
}
