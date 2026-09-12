#!/usr/bin/env nu
# Validate sustained four-player benchmark samples, including audio service load.
# This module also exports check-capture for content/material identity checks.
const BASE_FIELDS = [views phase fps cpu_us submit_us triangles]
const AUDIO_FIELDS = [audio audio_us audio_buffers audio_gap_us audio_budget_us audio_sfx audio_overlap workload]
const AUDIO_WORK_FIELDS = [audio_us audio_buffers audio_gap_us audio_budget_us audio_sfx audio_overlap]

# Return report lines, or raise a native Nu error on an invalid capture.
# Extra fields are ignored here so callers can validate content/material identity.
export def check-capture [
    text: string
    --minimum: int = 40
    --samples-per-phase: int = 15
    --audio: string = '' # on, off, legacy, or omitted to infer from the capture
]: nothing -> list<string> {
    if $minimum < 1 or $samples_per_phase < 1 {
        error make 'minimum and samples-per-phase must be positive'
    }
    if $audio not-in ['' on off legacy] { error make 'audio must be on, off, or legacy' }
    if $text =~ 'RDPQ_VALIDATION|ASSERTION|capacity exceeded' {
        error make 'diagnostic errors in the capture'
    }
    mut rows = []
    for line in ($text | lines) {
        if not ($line | str starts-with 'PERF ') { continue }
        let fields = ($line | parse --regex '(?P<key>\w+)=(?P<value>[^\s]+)' | reduce --fold {} {|field record|
            $record | upsert $field.key $field.value
        })
        let keys = ($fields | columns)
        let some_audio = ($AUDIO_FIELDS | any {|key| $key in $keys })
        if not ($BASE_FIELDS | all {|key| $key in $keys }) or ($some_audio and not ($AUDIO_FIELDS | all {|key| $key in $keys })) {
            error make 'incomplete PERF sample'
        }
        mut row = {}
        for key in ($BASE_FIELDS | append $AUDIO_FIELDS) {
            if $key not-in $keys { continue }
            let value = ($fields | get $key)
            # Nu's into int also truncates decimal strings; PERF integers must not.
            if $value !~ '^[+-]?\d+$' { error make 'invalid numeric PERF field' }
            let number = try { $value | into int } catch { error make 'invalid numeric PERF field' }
            # Conversion can also clamp overflowing strings through a float.
            # Compare canonical decimal text so no field changes silently.
            let digits = ($value | str replace --regex '^[+-]' '' | str replace --regex '^0+' '')
            let canonical = if $digits == '' { '0' } else if ($value | str starts-with '-') { '-' + $digits } else { $digits }
            if ($number | into string) != $canonical { error make 'invalid numeric PERF field' }
            if $number < 0 { error make 'negative PERF field' }
            $row = ($row | insert $key $number)
        }
        let mode = if not $some_audio { 'legacy' } else {
            match $row.audio {
                0 => { 'off' }
                1 => { 'on' }
                _ => { error make 'unknown audio mode' }
            }
        }
        if $row.views != 4 or $row.phase not-in [0 1 2] {
            error make 'capture must contain only four-player benchmark phases'
        }
        $rows = ($rows | append ($row | insert mode $mode))
    }
    if ($rows | is-empty) { error make 'capture has no PERF samples' }
    let modes = ($rows | get mode | uniq)
    let workloads = ($rows | each {|row| $row.workload? | default 1 } | uniq)
    if ($modes | length) != 1 or ($workloads | length) != 1 {
        error make 'mixed audio modes or workloads; capture each configuration separately'
    }
    let mode = $modes.0
    let workload = $workloads.0
    if $audio != '' and $mode != $audio { error make $'expected audio ($audio), found ($mode)' }
    if $mode != 'legacy' and $workload != 2 { error make 'unsupported audio benchmark workload' }
    let historical = if $mode == 'legacy' { ' (historical pre-audio capture)' } else { '' }
    mut result = [$'Audio: ($mode); workload: ($workload)($historical)']
    for phase in ([tour 'independent movement' 'close quarters'] | enumerate) {
        let samples = ($rows | where phase == $phase.index | get fps)
        if ($samples | length) < $samples_per_phase {
            error make $'phase ($phase.index) needs ($samples_per_phase) complete samples'
        }
        let lowest = ($samples | math min)
        let highest = ($samples | math max)
        let average = ($samples | math avg | into string --decimals 1)
        $result = ($result | append $'($phase.item): ($samples | length) samples; ($lowest)–($highest) FPS; mean ($average)')
        if $lowest < $minimum { error make $'phase ($phase.index) fell below ($minimum) FPS' }
    }
    if $mode == 'on' {
        if ($rows | any {|row| $row.audio_buffers == 0 }) {
            error make 'audio-enabled sample produced no output buffers'
        }
        if ($rows | any {|row| $row.audio_budget_us == 0 or $row.audio_gap_us > $row.audio_budget_us }) {
            error make 'audio service gap exceeded its conservative buffer budget'
        }
        if ($rows | where phase == 2 | get audio_overlap | math max) != 4 {
            error make 'close-quarters capture did not exercise four overlapping player sounds'
        }
        let mixing = ($rows | get audio_us | math avg | into string --decimals 0)
        let gap = ($rows | get audio_gap_us | math max)
        $result = ($result | append $'Audio: mean ($mixing) µs/frame mixing; maximum service gap ($gap) µs')
    } else if $mode == 'off' {
        if ($rows | any {|row| $AUDIO_WORK_FIELDS | any {|key| ($row | get $key) != 0 } }) {
            error make 'audio-off capture reports audio work'
        }
    }
    $result | append $'PASS: all ($rows | length) one-second samples reached ($minimum)+ FPS'
}

# Check one capture. Do not mix modes or workloads in the same log.
export def main [
    log: path
    --minimum: int = 40
    --samples-per-phase: int = 15
    --audio: string = '' # on, off, legacy, or omitted to infer from the capture
] {
    try {
        let report = (check-capture (open --raw $log) --minimum $minimum --samples-per-phase $samples_per_phase --audio $audio)
        for line in $report { print $line }
    } catch {|err| error make $'FAIL: ($err.msg)' }
}
