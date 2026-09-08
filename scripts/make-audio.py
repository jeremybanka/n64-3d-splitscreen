#!/usr/bin/env python3
"""Generate the template's original CC0 mono music loop and hop sound.

Only Python's standard library is needed. Normal ROM builds use the checked-in
WAV files and the pinned SDK's audioconv64; this generator is an authoring tool.
"""
import argparse
import io
import math
from pathlib import Path
import struct
import wave

RATE = 22050
ROOT = Path(__file__).resolve().parent.parent


def encode(samples):
    stream = io.BytesIO()
    with wave.open(stream, 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(b''.join(struct.pack('<h', round(value * 32767)) for value in samples))
    return stream.getvalue()


def music():
    # Original 16-beat phrase, 120 BPM; C/A/F/G bass motion over eight seconds.
    notes = (72, 76, 79, 76, 69, 72, 76, 72, 65, 69, 72, 69, 67, 71, 74, 71)
    bass = (48, 45, 41, 43)
    for i in range(8 * RATE):
        time = i / RATE
        beat = int(time * 2)
        local = time - beat * 0.5
        envelope = min(local / 0.015, 1) * max(0, 1 - local / 0.46) ** 2
        frequency = 440 * 2 ** ((notes[beat] - 69) / 12)
        low = 440 * 2 ** ((bass[beat // 4] - 69) / 12)
        tone = math.sin(2 * math.pi * frequency * local) + 0.2 * math.sin(4 * math.pi * frequency * local)
        yield envelope * (0.14 * tone + 0.08 * math.sin(2 * math.pi * low * local))


def hop():
    for i in range(round(0.18 * RATE)):
        time = i / RATE
        envelope = min(time / 0.005, 1) * max(0, 1 - time / 0.18) ** 2
        # Smooth upward sine chirp; zero attack and tail avoid boundary clicks.
        yield 0.28 * envelope * math.sin(2 * math.pi * (480 * time + 1200 * time * time))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='verify the checked-in WAVs without writing')
    args = parser.parse_args()
    for name, samples in (('meadow', music()), ('hop', hop())):
        data = encode(samples)
        path = ROOT / 'assets' / 'audio' / f'{name}.wav'
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit(f'FAIL: regenerate {path.relative_to(ROOT)} with scripts/make-audio.py')
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        print(f'{path.relative_to(ROOT)}: {len(data)} bytes')


if __name__ == '__main__':
    main()
