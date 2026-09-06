Libdragon features a realtime audio decompressor for the [ULC (“Ultra Low Complexity”) codec](https://github.com/Aikku93/ulc-codec).

ULC is a lightweight MDCT-based audio codec originally designed for constrained hardware. It is conceptually closer to
formats such as MP3, AAC, Vorbis, or Opus/CELT than to ADPCM: audio is split into blocks, converted into frequency-
domain coefficients, quantized, and entropy-coded. At playback time, libdragon decodes the coefficients and runs an
inverse transform to reconstruct PCM samples.

Compared to Opus, ULC is much simpler and less computationally expensive. Compression ratios are lower, but playback is
easier to sustain on Nintendo 64. This makes ULC a useful middle ground between VADPCM and Opus:

- Better compression than VADPCM
- Much lower runtime cost than Opus
- Suitable for realtime music playback, spoken dialog, ambience and longer sound effects
- Supports mono and stereo streams
- Supports seeking (to 1024 sample intervals)
- Supports looped samples and streaming playback

ULC playback in libdragon is RSP-accelerated with a custom microcode. The CPU decodes the compressed coefficient
stream, while the RSP performs the IMDCT, overlap/lapping, output scaling, and stereo interleaving.

## How to compress a WAV file

Encoding is handled in [audioconv64](https://github.com/DragonMinded/libdragon/wiki/Audioconv64) and produces wav64
files, just like the other audio codecs in Libdragon. ULC provides some more command line flags to control bitrate & 
quality. The encoder can work in a “variable bit rate” (VBR), “average bit rate” (ABR) and “constant bitrate” (CBR) 
mode. Typically you would want to use either the VBR mode with a fixed quality, or the ABR mode for exact file sizes.


#### Examples

ULC default (VBR at 50% quality):
```sh
$N64_INST/bin/audioconv64 --wav-compress ulc music.wav
```

VBR with 70% quality:
```sh
$N64_INST/bin/audioconv64 --wav-compress ulc,mode=vbr,quality=70 music.wav
```

ABR with 96kbits/s:
```sh
$N64_INST/bin/audioconv64 --wav-compress ulc,mode=abr,bitrate=96 music.wav
```
See [audioconv64](https://github.com/DragonMinded/libdragon/wiki/Audioconv64) for general information about the
conversion process.

## How to playback

At runtime, ULC-compressed wav64 files are played back through the normal wav64 APIs, like other wav64 files. See the 
wav64.h header file for the full API, and the mixertest example for a simple playback example.

The only difference is that you must explicitly initialize playback of ULC files by calling:

```c
wav64_init_compression(2);
```

This tells libdragon to link support for decompression of ULC WAV64 files. The ULC decoder adds about 16 kb to your ROM.


## Compression ratio and quality

Because the ULC decoder internally works with 16 bit fixed point numbers it can introduce a bit of white noise. This is
less noticeable at higher samplerates. If you can, stick to 44100hz and configure the audio interface to the same 
samplerate, so the mixer does not need to resample (`audio_init(44100, 8)`).

Music starts to sound "good enough" at around 64 kbit/s (of course dependent on the actual track), while speech can go 
as low as 32 or even 16 kbit/s. Try different rates to find a trade-off that works for you.

If you add the `--debug` option, audioconv64 will generate a decoded debug WAV file next to the converted asset. This
lets you quickly listen to the result of the compression process on your PC before testing it on hardware. Be aware
that this currently uses the reference ULC decoder that works with floating point values and will produce less noisy 
results than the RSP accelerated decoder in Libdragon.

Here's a simple demo project with different audio tracks encoded at various bitrates.

Demo: http://phoboslab.org/files/ulcdemo.z64  
Source: https://github.com/phoboslab/ulc64/

## Seeking and looping

ULC-compressed wav64 files support seeking and looping.

For efficient seeking, audioconv64 stores a sparse seek table in the file. The table contains offsets to every 8th
compressed block. When seeking, libdragon jumps to the nearest previous table entry and quickly skips forward 
block-by-block until it reaches the requested position. Playback always starts at a block boundary, so at 1024 
sample intervals. The `wav64_seek()` function internally adjust the time offset to these block boundaries.


## Technical details

ULC is an MDCT codec. The encoder splits the input audio into fixed-size blocks and transforms them into frequency-
domain coefficients. These coefficients are quantized and encoded using a compact nybble-oriented bitstream.

At playback time, libdragon:

1. Reads the compressed block.
2. Decodes quantized coefficients on the CPU.
3. Sends the coefficient buffer to the RSP.
4. Runs the inverse transform on the RSP.
5. Applies overlap/lapping between adjacent blocks.
6. Writes the final PCM samples into the wav64 sample buffer.

ULC uses overlapping transform blocks, so decoding requires preroll blocks before producing usable samples.
Libdragon handles this internally for stream start, loops, and seeks.

If you are inclined, have a look at the [wav64_ulc.c source](https://github.com/DragonMinded/libdragon/blob/preview/src/audio/wav64_ulc.c). 
The source has extensive comments and the CPU part of the decoder is not too hard to understand. The nibble based syntax
for storing block coefficients is a particularly elegant detail in ULC.
