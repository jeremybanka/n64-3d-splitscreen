use std/assert
use mesh-format.nu *

def fails [message: string, action: closure] {
    let result = try { do $action | collect | ignore; {failed: false} } catch {|e| {failed: true, message: $e.debug} }
    assert $result.failed $'Expected error containing ($message)'
    assert ($result.message =~ $message) $'Wrong error: ($result.message)'
}

def main [] {
    let vertices = [[0 0 0 0] [256 0 0 1] [0 256 0 2]]
    let faces = [[0 1 2 0 255]]
    let colors = [4294967295]
    assert equal (quantize-position [1 -2 3] 'head') [256 768 512]
    assert equal ([0.5 1.5 2.5 -0.5 -1.5] | each {|v| round-even $v }) [0 2 2 0 -2]
    fails 'head' { quantize-position [128 0 0] 'head' }
    fails 'head' { quantize-position [null 0 0] 'head' }
    for case in [
        {face: [0 1 3 0 255], message: 'vertex index'}
        {face: [0 1 2 1 255], message: 'material index'}
        {face: [0 1 2 0 256], message: shade}
    ] { fails $case.message { validate-mesh $vertices [$case.face] $colors } }
    fails 'animation_part' { validate-mesh ($vertices | update 0 [0 0 0 4]) $faces $colors }
    fails 'degenerate after Q8' { validate-mesh ($vertices | update 2 [128 0 0 0]) $faces $colors }
    for vertex in [[30000 0 0 0] [0 32767 0 0] [0 -1 0 0]] {
        fails 'rotation/movement|bob/hop' { validate-mesh ($vertices | update 0 $vertex) $faces $colors }
    }
    assert equal (validate-mesh $vertices $faces $colors) {vertices: 20, batches: 1}
    let big_vertices = 0..<250 | each { $vertices } | flatten
    let big_faces = 0..<250 | each {|i| [($i * 3) ($i * 3 + 1) ($i * 3 + 2) 0 255] }
    fails '768 animated vertices' { validate-mesh $big_vertices $big_faces $colors }
    fails '4096-index' { validate-mesh $vertices (0..<1350 | each { $faces.0 }) $colors }
    assert equal (validate-mesh $vertices ($faces | append [[0 1 2 1 255] [0 1 2 0 200]]) [4294967295 4294967295]) {vertices: 26, batches: 1}
    let serialized = serialize-mesh $vertices $faces $colors
    assert ($serialized | str contains 'pub const colors = [_]u32{ 0xffffffff };')
    assert equal $serialized (serialize-mesh $vertices $faces $colors)
    fails 'no mesh triangles' { serialize-mesh [] [] $colors }
    print 'Mesh validation: coordinates, ties-to-even, indices, materials, tags, shading, motion bounds, capacity and serialization pass'
}
