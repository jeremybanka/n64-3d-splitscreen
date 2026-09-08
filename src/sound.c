/* Cooperative audio producer. Never call the mixer from an interrupt callback. */
#include <libdragon.h>
#include "bridge.h"
#include "sound.h"

_Static_assert(AUDIO == 0 || AUDIO == 1, "AUDIO must be 0 or 1");
static sound_stats_t stats;
#if AUDIO
#define AUDIO_BUFFERS 6
static wav64_t music, hop;
static bool paused;
static uint64_t last_service;
#endif

void sound_init(void) {
#if AUDIO
    assertf(dfs_init(DFS_DEFAULT_LOCATION) == DFS_ESUCCESS, "Audio DFS missing");
    audio_init(22050, AUDIO_BUFFERS);
    mixer_init(5); // Channel 0 = music; 1..4 = physical players P1..P4.
    mixer_set_vol(0.85f);
    wav64_open(&music, "rom:/meadow.wav64");
    wav64_set_loop(&music, true);
    wav64_open(&hop, "rom:/hop.wav64");
    mixer_ch_set_vol(0, 0.55f, 0.55f);
    for (unsigned p = 0; p < 4; p++)
        mixer_ch_set_vol_pan(p + 1, 0.65f, 0.3f + 0.4f * p / 3.0f);
    // A conservative service-gap guard, not a measured AI underrun counter.
    // Leave two buffers of margin for the hardware queue and an in-flight mix.
    stats.budget_us = (uint64_t)(AUDIO_BUFFERS - 2) * audio_get_buffer_length() * 1000000 / audio_get_frequency();
    last_service = get_ticks_us();
    debugf("AUDIO mode=1 rate=%d buffer_samples=%d buffers=%d service_budget_us=%lu\n",
        audio_get_frequency(), audio_get_buffer_length(), AUDIO_BUFFERS, stats.budget_us);
#else
    debugf("AUDIO mode=0\n");
#endif
}

void sound_update(uint32_t status) {
    uint32_t events = game_audio_events(); // Drain even in AUDIO=0 builds.
#if AUDIO
    paused = (status & GAME_STATUS_PAUSED) != 0;
    if (events & (1u << 8)) wav64_play(&music, 0);
    for (unsigned p = 0; p < 4; p++) {
        // Stop before starting: a restart followed by a new hop in the same
        // render frame may legitimately request both actions for this port.
        if (paused || !(status & (1u << (16 + p))) || events & (1u << (4 + p)))
            mixer_ch_stop(p + 1);
        if (!paused && (status & (1u << (16 + p))) && (events & (1u << p))) {
            wav64_play(&hop, p + 1); // Replaces only this player's previous SFX.
            stats.starts++;
        }
    }
    unsigned playing = 0;
    for (unsigned p = 0; p < 4; p++) playing += mixer_ch_playing(p + 1);
    if (playing > stats.overlap) stats.overlap = playing;
#else
    (void)events;
    (void)status;
#endif
}

void sound_service(void) {
#if AUDIO
    uint64_t now = get_ticks_us();
    uint64_t gap = now - last_service;
    last_service = now;
    if (gap > stats.max_gap_us) stats.max_gap_us = gap > UINT32_MAX ? UINT32_MAX : gap;
    // Bounded work: an overloaded mixer must not trap the main loop forever.
    for (unsigned n = 0; n < AUDIO_BUFFERS && audio_can_write(); n++) {
        uint64_t start = get_ticks_us();
        if (paused) {
            // Queued sound drains first. Not polling the mixer freezes music's
            // sample position, without unsafe AI reinitialization on pause.
            audio_write_silence();
        } else {
            int16_t *buffer = audio_write_begin();
            mixer_poll(buffer, audio_get_buffer_length());
            audio_write_end();
        }
        stats.mix_us += get_ticks_us() - start;
        stats.buffers++;
    }
#endif
}

sound_stats_t sound_take_stats(void) {
    sound_stats_t result = stats;
    stats = (sound_stats_t){ .budget_us = result.budget_us };
    return result;
}
