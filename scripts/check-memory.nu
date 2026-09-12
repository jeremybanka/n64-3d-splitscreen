# Validate one runtime capture; this does not certify its physical source.
export def records [text: string, kind: string] {
    $text | lines | where { str starts-with ($kind + ' ') } | each {|line|
        let fields = ($line | split row --regex '\s+' | skip 1 | where $it != '')
        mut row = {}
        for field in $fields {
            let parts = ($field | split row '=')
            if ($parts | length) != 2 or $parts.0 == '' or $parts.1 == '' {
                error make {msg: $'Malformed ($kind) record'}
            }
            if $parts.0 in ($row | columns) { error make {msg: $'Duplicate ($kind) field'} }
            $row = ($row | upsert $parts.0 $parts.1)
        }
        $row
    }
}

def numbers [row: record] {
    $row | transpose key value | reduce --fold {} {|field, parsed|
        if $field.value !~ '^-?\d+$' { error make {msg: $'Invalid integer field ($field.key)'} }
        let magnitude = ($field.value | str replace --regex '^-' '' | str replace --regex '^0+' '')
        let limit = (if ($field.value | str starts-with '-') { '9223372036854775808' } else { '9223372036854775807' })
        if ($magnitude | str length) > 19 or (($magnitude | str length) == 19 and $magnitude > $limit) {
            error make {msg: $'Integer field ($field.key) exceeds the supported range'}
        }
        $parsed | upsert $field.key ($field.value | into int)
    }
}

export def check-memory-capture [text: string, options: record = {}] {
    let opts = ({require_base_memory: false, tv: null, minimum_seconds: 60, minimum_free: 262144, content: null, audio: null, textured: null, collision: null} | merge $options)
    if $opts.minimum_seconds < 0 or $opts.minimum_free < 0 { error make {msg: 'Minimum duration/headroom cannot be negative'} }
    if $text =~ '(?i)RDPQ_VALIDATION|ASSERTION|capacity.*exceeded|Invalid heap accounting' {
        error make {msg: 'Diagnostic errors in the capture'}
    }
    let configs = (records $text CONFIG)
    let capacities = (records $text CAPACITY)
    let rows = (records $text MEMORY)
    if ($configs | length) != 1 or ($capacities | length) != 1 {
        error make {msg: 'Capture must contain exactly one boot CONFIG and CAPACITY record'}
    }
    let config = $configs.0
    if $config.schema != '1' or (['audio' 'textured' 'collision' 'benchmark' 'validate'] | any {|key| ($config | get $key) not-in ['0' '1'] }) {
        error make {msg: 'Unsupported or invalid CONFIG'}
    }
    if ($config.content? | default '' | is-empty) { error make {msg: 'Missing content identity'} }
    if $config.initial_views not-in ['1' '2' '3' '4'] { error make {msg: 'Invalid initial view count'} }
    for key in ['content' 'audio' 'textured' 'collision'] {
        let expected = ($opts | get $key)
        if $expected != null and ($config | get $key) != ($expected | into string) {
            error make {msg: $'Expected ($key)=($expected); capture has ($config | get $key)'}
        }
    }
    let capacity = (numbers $capacities.0)
    if ($capacity | values | any { $in <= 0 }) { error make {msg: 'Invalid zero/negative capacity'} }
    if $capacity.animated_vertices mod 2 != 0 or $capacity.animation_bytes != ($capacity.animated_vertices // 2 * $capacity.packed_bytes * $capacity.frame_slots * $capacity.ports) {
        error make {msg: 'Animation storage does not match reported ABI capacities'}
    }
    let color_bytes = ($capacity.width * $capacity.height * $capacity.color_bpp * $capacity.color_buffers)
    let depth_bytes = ($capacity.depth_stride * $capacity.depth_height)
    if ($rows | length) < 2 or $rows.0.stage != 'init' { error make {msg: 'Need initialization and later runtime memory samples'} }
    mut previous_time = -1
    mut low_water = -1
    mut identity: list<any> = []
    for row in $rows {
        let video = $row.tv
        let data = (numbers ($row | reject stage tv))
        if $data.schema != 1 or $video not-in ['NTSC' 'PAL' 'MPAL'] { error make {msg: 'Unsupported MEMORY schema or video region'} }
        if $data.ram not-in [4194304 8388608] or $data.expanded != (if $data.ram == 8388608 { 1 } else { 0 }) {
            error make {msg: 'Unsupported/inconsistent RAM report'}
        }
        if $opts.require_base_memory and $data.ram != 4194304 {
            error make {msg: 'Base-memory verification requires an actual 4 MiB runtime report'}
        }
        if $opts.tv != null and $video != $opts.tv { error make {msg: $'Expected ($opts.tv) video; capture reports ($video)'} }
        let current_identity = [$data.ram $video $data.resident $data.heap_total $data.reserved $data.zero_bytes]
        if not ($identity | is-empty) and $current_identity != $identity { error make {msg: 'Mixed runtime memory/region identities'} }
        $identity = $current_identity
        if $data.elapsed_ms <= $previous_time or ($previous_time < 0 and $data.elapsed_ms != 0) or ($previous_time >= 0 and $row.stage != 'run') {
            error make {msg: 'Nonmonotonic time or multiple boots in capture'}
        }
        if $previous_time >= 0 and $data.elapsed_ms - $previous_time > 15000 {
            error make {msg: 'Memory sample gap exceeds 15 seconds; capture must be continuous'}
        }
        $previous_time = $data.elapsed_ms
        if ($data | values | any { $in < 0 }) or $data.resident < $data.zero_bytes { error make {msg: 'Invalid memory accounting'} }
        if $data.heap_total <= 0 or $data.reserved <= 0 or $data.heap_used + $data.heap_free != $data.heap_total {
            error make {msg: 'Heap used/free accounting does not balance'}
        }
        if $data.resident + $data.heap_total + $data.reserved != $data.ram { error make {msg: 'Resident/heap/reserved accounting does not balance'} }
        if $data.color_bytes != $color_bytes or $data.depth_bytes != $depth_bytes { error make {msg: 'Surface storage does not match display configuration'} }
        $low_water = (if $low_water < 0 { $data.heap_free } else { [$low_water $data.heap_free] | math min })
        if $data.sampled_min_free != $low_water { error make {msg: 'Sampled low-water mark is inconsistent'} }
    }
    if $previous_time < $opts.minimum_seconds * 1000 { error make {msg: $'Capture needs at least ($opts.minimum_seconds) seconds'} }
    if $low_water < $opts.minimum_free { error make {msg: $'Sampled headroom ($low_water) is below project policy ($opts.minimum_free)'} }
    $'PASS: ($rows | length) samples over ($previous_time / 1000)s; ($identity.0 // 1048576) MiB ($identity.1); sampled free minimum ($low_water) bytes'
}

export def main [
    log: path
    --require-base-memory
    --tv: string
    --minimum-seconds: int = 60
    --minimum-free: int = 262144
    --content: string
    --audio: int
    --textured: int
    --collision: int
] {
    if $tv != null and $tv not-in ['NTSC' 'PAL' 'MPAL'] { error make {msg: 'TV must be NTSC, PAL or MPAL'} }
    for mode in [$audio $textured $collision] {
        if $mode != null and $mode not-in [0 1] { error make {msg: 'Audio, textured and collision modes must be 0 or 1'} }
    }
    print (check-memory-capture (open --raw $log) {
        require_base_memory: $require_base_memory, tv: $tv, minimum_seconds: $minimum_seconds,
        minimum_free: $minimum_free, content: $content, audio: $audio, textured: $textured, collision: $collision
    })
}
