#!/usr/bin/env nu
# Native regression tests: captures cannot pass with missing or mixed workloads.
use std/assert
use check-performance.nu check-capture
use make-audio.nu [round-even encode-wav]
const ROOT = path self ..

export def capture [mode: string = on]: nothing -> string {
    0..2 | each {|phase|
        let base = $'PERF views=4 phase=($phase) fps=60 cpu_us=1000 submit_us=2000 triangles=900'
        if $mode == 'legacy' { $base } else {
            let on = $mode == 'on'
            let work = if $on {
                'audio_us=100 audio_buffers=50 audio_gap_us=18000 audio_budget_us=80000 audio_sfx=4 audio_overlap=4'
            } else {
                'audio_us=0 audio_buffers=0 audio_gap_us=0 audio_budget_us=0 audio_sfx=0 audio_overlap=0'
            }
            $'($base) audio=($on | into int) ($work) workload=2'
        }
    } | str join (char newline)
}

def check [text: string, mode: string = '']: nothing -> list<string> {
    check-capture $text --samples-per-phase 1 --audio $mode
}

def expect-failure [reason: string, action: closure] {
    let result = try {
        do $action | ignore
        {failed: false, message: ''}
    } catch {|err| {failed: true, message: $err.rendered} }
    assert $result.failed $'Expected failure containing: ($reason)'
    assert ($result.message | str contains $reason) $'Expected ($reason), received ($result.message)'
}

def separate-modes [] {
    for mode in [on off legacy] {
        assert ((check (capture $mode) $mode).0 | str contains $'Audio: ($mode)')
    }
    assert ((check (capture legacy)).0 | str contains 'historical pre-audio')
    assert ((check (capture on)).1 | str ends-with 'FPS; mean 60.0')
}

def mixed-modes [] {
    for extra in [(capture off) (capture legacy) (capture | str replace --all 'workload=2' 'workload=3')] {
        expect-failure mixed { check ((capture) + (char newline) + $extra) }
    }
    expect-failure 'expected audio' { check (capture legacy) on }
}

def audio-work [] {
    for fixture in [
        {from: 'audio_buffers=50', to: 'audio_buffers=0', reason: 'no output'}
        {from: 'audio_overlap=4', to: 'audio_overlap=3', reason: 'four overlapping'}
        {from: 'audio_gap_us=18000', to: 'audio_gap_us=90000', reason: 'service gap'}
        {from: 'audio_budget_us=80000', to: 'audio_budget_us=0', reason: 'service gap'}
    ] {
        expect-failure $fixture.reason { check (capture | str replace --all $fixture.from $fixture.to) }
    }
    expect-failure audio-off { check (capture off | str replace --all 'audio_us=0' 'audio_us=100') }
}

def incomplete-or-slow [] {
    for fixture in [
        {text: (capture | str replace --all ' audio_buffers=50' ''), reason: 'incomplete PERF'}
        {text: (capture | str replace --all 'fps=60' 'fps=20'), reason: 'fell below'}
        {text: (capture | lines | first), reason: 'complete samples'}
        {text: ((capture) + (char newline) + 'ASSERTION failed'), reason: 'diagnostic errors'}
        {text: '', reason: 'no PERF samples'}
    ] { expect-failure $fixture.reason { check $fixture.text } }
}

def future-fields [] {
    check (capture | str replace --all 'workload=2' 'workload=2 textured=0 content=meadow') | ignore
}

def integer-validation [] {
    for value in ['1.5' bad '0x10' '1e3' '9223372036854775808'] {
        expect-failure 'invalid numeric' { check (capture | str replace --all 'fps=60' $'fps=($value)') }
    }
    expect-failure 'negative PERF' { check (capture | str replace --all 'fps=60' 'fps=-1') }
    expect-failure 'unknown audio mode' { check (capture | str replace --all 'audio=1 ' 'audio=2 ') }
    expect-failure 'unsupported audio benchmark' { check (capture | str replace --all 'workload=2' 'workload=3') }
    expect-failure 'must be positive' { check-capture (capture) --minimum 0 }
    expect-failure 'must be positive' { check-capture (capture) --samples-per-phase 0 }
    expect-failure 'audio must be' { check-capture (capture) --audio invalid }
}

def pcm-layout [] {
    assert equal ([-3.5 -2.5 -1.5 -0.5 0.5 1.5 2.5 3.5] | each {|n| round-even $n }) [-4 -2 -2 0 0 2 2 4]
    let wav = (encode-wav [0 1 -1 0])
    assert equal ($wav | bytes length) 52
    assert equal ($wav | bytes at 0..3) 0x[52494646]
    assert equal ($wav | bytes at 4..7 | into int --endian little) 44
    assert equal ($wav | bytes at 8..11) 0x[57415645]
    assert equal ($wav | bytes at 20..23) 0x[01000100]
    assert equal ($wav | bytes at 24..27 | into int --endian little) 22050
    assert equal ($wav | bytes at 28..31 | into int --endian little) 44100
    assert equal ($wav | bytes at 32..35) 0x[02001000]
    assert equal ($wav | bytes at 36..39) 0x[64617461]
    assert equal ($wav | bytes at 40..43 | into int --endian little) 8
    assert equal ($wav | bytes at 44..) 0x[0000ff7f01800000]
    expect-failure '16-bit range' { encode-wav [2] }
}

def cli-exit-status [] {
    let directory = ($ROOT | path join .build $'native-audio-test-(random uuid)')
    mkdir $directory
    let log = ($directory | path join capture.log)
    let script = ($ROOT | path join scripts check-performance.nu)
    try {
        capture | lines | each {|line| $line + ' textured=0 content=meadow' } | str join (char nl) | save --raw $log
        let valid = (^$nu.current-exe --no-config-file $script $log --samples-per-phase 1 --audio on | complete)
        assert equal $valid.exit_code 0 $valid.stderr
        assert ($valid.stdout | str contains 'PASS: all 3 one-second samples')
        let invalid = (^$nu.current-exe --no-config-file $script $log --samples-per-phase 1 --audio off | complete)
        assert ($invalid.exit_code != 0)
        assert ($invalid.stderr | str contains 'FAIL: expected audio off, found on')
        let missing = (^$nu.current-exe --no-config-file $script ($directory | path join missing.log) | complete)
        assert ($missing.exit_code != 0)
    } catch {|err|
        rm --recursive --force $directory
        error make $err
    }
    rm --recursive --force $directory
}

export def main [] {
    for test in [
        {name: 'separate on/off/legacy captures', run: { separate-modes }}
        {name: 'mixed modes and workloads', run: { mixed-modes }}
        {name: 'audio work, overlap and service guard', run: { audio-work }}
        {name: 'incomplete, slow and diagnostic captures', run: { incomplete-or-slow }}
        {name: 'future content fields', run: { future-fields }}
        {name: 'integer and option validation', run: { integer-validation }}
        {name: 'ties-to-even PCM and little-endian RIFF', run: { pcm-layout }}
        {name: 'native CLI exit status', run: { cli-exit-status }}
    ] {
        do $test.run
        print $'PASS: ($test.name)'
    }
    print 'All 8 native audio/performance tests passed.'
}
