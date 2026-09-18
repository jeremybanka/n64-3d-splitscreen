# Require explicit obstacle workload identity when accepting a capture.
export def check-collision-workload [text: string, collision: string = 'off'] {
    let samples = ($text | lines | where { str starts-with 'PERF ' } | each {|line|
        $line | parse --regex '(?P<key>\w+)=(?P<value>\S+)' | reduce --fold {} {|pair, row| $row | upsert $pair.key $pair.value }
    })
    if ($samples | is-empty) { error make {msg: 'capture has no PERF samples'} }
    if $collision == 'legacy' {
        if ($samples | any {|row| 'collision' in ($row | columns) }) {
            error make {msg: 'legacy collision mode requires an untagged historical capture'}
        }
        return 'Historical capture without collision workload tags.'
    }
    if $collision not-in ['off' 'on'] { error make {msg: 'unknown collision mode'} }
    let expected = (if $collision == 'on' { '1' } else { '0' })
    if ($samples | any {|row| $row.collision? != $expected }) {
        error make {msg: $'every PERF sample must identify collision=($expected); capture each configuration separately'}
    }
    $'Collision demo: ($collision).'
}
