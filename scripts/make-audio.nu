#!/usr/bin/env nu
# Generate the original CC0 mono music loop and hop sound with native Nu math
# and binary commands. Normal ROM builds use the checked-in WAV sources.
const ROOT = path self ..
const RATE = 22050
const PI = 3.141592653589793

# Match PCM quantization's previous ties-to-even behavior, including negatives.
export def round-even [value: number]: nothing -> int {
    let lower = ($value | math floor | into int)
    let fraction = $value - $lower
    if $fraction < 0.5 { $lower } else if $fraction > 0.5 {
        $lower + 1
    } else if ($lower mod 2) == 0 { $lower } else { $lower + 1 }
}

def little32 [value: int]: nothing -> binary {
    $value | into binary --endian little | bytes at 0..3
}

# Explicit little-endian RIFF/WAVE PCM layout, independent of host endianness.
export def encode-wav [samples: list<number>]: nothing -> binary {
    let pcm = ($samples | each {|value|
        let sample = (round-even ($value * 32767))
        if $sample < -32768 or $sample > 32767 { error make 'PCM sample exceeds 16-bit range' }
        $sample | into binary --endian little | bytes at 0..1
    } | bytes collect)
    let size = ($pcm | bytes length)
    bytes build 0x[52494646] (little32 ($size + 36)) 0x[57415645666d7420] (little32 16) 0x[01000100] (little32 $RATE) (little32 ($RATE * 2)) 0x[0200100064617461] (little32 $size) $pcm
}

def music []: nothing -> list<number> {
    # Original sixteen-beat phrase at 120 BPM; C/A/F/G bass over eight seconds.
    let frequencies = ([72 76 79 76 69 72 76 72 65 69 72 69 67 71 74 71] | each {|note|
        440 * (2 ** (($note - 69) / 12))
    })
    let bass = ([48 45 41 43] | each {|note| 440 * (2 ** (($note - 69) / 12)) })
    0..<($RATE * 8) | each {|i|
        let time = $i / $RATE
        let beat = ($time * 2 | into int)
        let local = $time - $beat * 0.5
        let envelope = ([($local / 0.015) 1] | math min) * (([0 (1 - $local / 0.46)] | math max) ** 2)
        let frequency = ($frequencies | get $beat)
        let low = ($bass | get ($beat // 4))
        let tone = (2 * $PI * $frequency * $local | math sin) + 0.2 * (4 * $PI * $frequency * $local | math sin)
        $envelope * (0.14 * $tone + 0.08 * (2 * $PI * $low * $local | math sin))
    }
}

def hop []: nothing -> list<number> {
    0..<(round-even (0.18 * $RATE)) | each {|i|
        let time = $i / $RATE
        let envelope = ([($time / 0.005) 1] | math min) * (([0 (1 - $time / 0.18)] | math max) ** 2)
        # Smooth upward sine chirp, with silent attack and tail boundaries.
        0.28 * $envelope * (2 * $PI * (480 * $time + 1200 * $time * $time) | math sin)
    }
}

export def generate-wav [name: string]: nothing -> binary {
    let samples = match $name {
        meadow => { music }
        hop => { hop }
        _ => { error make $'Unknown sample: ($name)' }
    }
    encode-wav $samples
}

# Rebuild original WAV sources, or verify them without modifying files.
export def main [--check] {
    for name in [meadow hop] {
        let data = (generate-wav $name)
        let relative = $'assets/audio/($name).wav'
        let path = ($ROOT | path join $relative)
        if $check {
            if not ($path | path exists) or (open --raw $path) != $data {
                error make $'FAIL: regenerate ($relative) with nu scripts/make-audio.nu'
            }
        } else {
            mkdir ($path | path dirname)
            $data | save --force --raw $path
        }
        print $'($relative): ($data | bytes length) bytes'
    }
}
