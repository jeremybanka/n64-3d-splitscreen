# Synthetic checker fixtures, not console or emulator measurements.
use std/assert
use check-memory.nu check-memory-capture

def capture [ram: int = 4194304] {
    let total = ($ram - 500000 - 65536)
    mut result = "CONFIG schema=1 content=meadow audio=1 textured=1 collision=0 benchmark=1 validate=0 initial_views=4\n"
    $result += "CAPACITY mesh_bytes=37900 mesh_vertices=2048 mesh_batches=64 mesh_indices=4096 animated_vertices=768 packed_bytes=32 frame_slots=3 ports=4 meshes_bytes=75800 animation_bytes=147456 width=320 height=240 color_bpp=2 color_buffers=3 depth_stride=640 depth_height=240\n"
    let samples = ([{stage: init elapsed: 0 used: 1000000} {stage: run elapsed: 1000 used: 1100000}] | append (10..20..60 | each {|second| {stage: run elapsed: ($second * 1000) used: 1200000} }))
    for sample in $samples {
        $result += ($'MEMORY schema=1 stage=($sample.stage) elapsed_ms=($sample.elapsed) ram=($ram) expanded=(if $ram == 8388608 {1} else {0}) tv=NTSC ' +
            $'resident=500000 zero_bytes=250000 heap_total=($total) heap_used=($sample.used) heap_free=($total - $sample.used) ' +
            $"sampled_min_free=($total - $sample.used) reserved=65536 color_bytes=460800 depth_bytes=153600\n")
    }
    $result
}

def main [] {
    let base = (capture)
    assert str contains (check-memory-capture $base {require_base_memory: true tv: NTSC audio: 1 textured: 1 collision: 0}) '4 MiB NTSC'
    assert str contains (check-memory-capture (capture 8388608)) '8 MiB'
    assert error { check-memory-capture (capture 8388608) {require_base_memory: true} }
    for options in [{tv: PAL} {audio: 0} {collision: 1} {content: robot-courtyard} {minimum_seconds: 600} {minimum_free: 3000000}] {
        assert error { check-memory-capture $base $options }
    }
    assert error { check-memory-capture ($base + $base) }
    assert error { check-memory-capture ($base | str replace ' content=meadow' '') }
    assert error { check-memory-capture ($base | lines | where { $in !~ 'elapsed_ms=60000' } | str join "\n") }
    assert error { check-memory-capture ($base | str replace 'elapsed_ms=60000 ram=4194304 expanded=0 tv=NTSC' 'elapsed_ms=60000 ram=4194304 expanded=0 tv=PAL') }
    assert error { check-memory-capture ($base | lines | where { $in !~ 'elapsed_ms=(20000|30000)' } | str join "\n") }
    for change in [
        {from: 'reserved=65536' to: 'reserved=0'}
        {from: 'animation_bytes=147456' to: 'animation_bytes=1'}
        {from: 'animated_vertices=768' to: 'animated_vertices=769'}
        {from: 'mesh_vertices=2048' to: 'mesh_vertices=999999999999999999999999'}
        {from: 'color_bytes=460800' to: 'color_bytes=1'}
        {from: 'heap_used=1200000' to: 'heap_used=1200001'}
        {from: 'sampled_min_free=2428768' to: 'sampled_min_free=1'}
        {from: 'schema=1 content' to: 'schema=1 schema=1 content'}
    ] {
        assert error { check-memory-capture ($base | str replace --all $change.from $change.to) }
    }
    assert error { check-memory-capture ($base + "ASSERTION failed\n") }
    print 'Memory: base/expanded RAM, identity, continuous duration, policy and malformed accounting checks pass'
}
