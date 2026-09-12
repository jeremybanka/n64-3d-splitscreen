# Keep texture/content identity separate from frame-rate acceptance.
export def check-texture-workload [text: string, textured: string = 'off', content: string = 'meadow'] {
    if $content not-in ['meadow' 'robot-courtyard'] { error make {msg: 'unknown content pack'} }
    let samples = ($text | lines | where { str starts-with 'PERF ' } | each {|line|
        $line | parse --regex '(?P<key>\w+)=(?P<value>\S+)' | reduce --fold {} {|pair, row| $row | upsert $pair.key $pair.value }
    })
    if ($samples | is-empty) { error make {msg: 'capture has no PERF samples'} }
    if $textured == 'legacy' {
        if $content != 'meadow' or ($samples | any {|row| 'textured' in ($row | columns) or 'content' in ($row | columns) }) {
            error make {msg: 'legacy mode is only for untagged historical Bunny Meadow captures'}
        }
        return 'Historical untextured Bunny Meadow capture (before material/content tags).'
    }
    if $textured not-in ['off' 'on'] { error make {msg: 'unknown texture mode'} }
    let expected = (if $textured == 'on' { '1' } else { '0' })
    if ($samples | any {|row| $row.textured? != $expected or $row.content? != $content }) {
        error make {msg: $'every PERF sample must identify textured=($expected) content=($content); use --textured legacy only for historical untagged captures'}
    }
    'Workload: content=' + $content + ', textured=' + $expected + ' (16x16 RGBA16 ground tile when enabled).'
}
