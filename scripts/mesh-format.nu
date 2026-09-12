# Native Nu mesh validation, Blender coordinate conversion and Zig serialization.
export def integer [value: any, low: int, high: int, label: string] {
    if ($value | describe) != 'int' or $value < $low or $value > $high {
        error make $'($label): expected an integer in ($low)..($high), got ($value | to nuon)'
    }
    $value
}

def finite [value: any] {
    if ($value | describe) not-in ['int' 'float'] { return false }
    ($value - $value) == 0
}

# Python's original exporter used ties-to-even; Nu's math round rounds away.
export def round-even [value: number] {
    let lower = $value | math floor | into int
    let fraction = $value - $lower
    if $fraction < 0.5 { $lower } else if $fraction > 0.5 { $lower + 1 } else { $lower + ($lower mod 2) }
}

export def quantize-position [position: list, label: string] {
    if ($position | length) != 3 or not ($position | all {|v| finite $v }) {
        error make $'($label): position must have three finite coordinates'
    }
    [$position.0 $position.2 (-1 * $position.1)] | enumerate | each {|v|
        integer (round-even ($v.item * 256)) (-32768) 32767 $'($label) axis ($v.index) after Q8 conversion; check scale'
    }
}

export def packed-vertex-count [vertices: list, faces: list] {
    let shadow = $vertices | length
    let triangles = $faces | append (0..<16 | each {|i| [$shadow ($shadow + 1 + $i) ($shadow + 1 + (($i + 1) mod 16)) (-1) 255] })
    mut total = 0
    mut batches = 0
    mut keys = []
    for face in $triangles {
        if ($keys | is-empty) or ($keys | length) > 61 {
            $total += ($keys | length) + (($keys | length) mod 2)
            $keys = []
            $batches += 1
        }
        for id in ($face | first 3) {
            let key = $'($id),($face.3),($face.4)'
            if $key not-in $keys { $keys = $keys | append $key }
        }
    }
    {vertices: ($total + ($keys | length) + (($keys | length) mod 2)), batches: $batches}
}

export def subtract [a: list, b: list] { 0..<3 | each {|i| ($a | get $i) - ($b | get $i) } }
export def cross [a: list, b: list] {
    [($a.1 * $b.2 - $a.2 * $b.1) ($a.2 * $b.0 - $a.0 * $b.2) ($a.0 * $b.1 - $a.1 * $b.0)]
}
export def dot [a: list, b: list] { 0..<3 | each {|i| ($a | get $i) * ($b | get $i) } | math sum }

export def validate-mesh [vertices: list, faces: list, colors: list] {
    if ($vertices | is-empty) or ($faces | is-empty) { error make 'export selection contains no mesh triangles' }
    if ($colors | length) < 1 or ($colors | length) > 255 { error make 'palette must contain 1..255 colors (one slot is reserved for the shadow)' }
    for color in ($colors | enumerate) { integer $color.item 0 4294967295 $'palette color ($color.index)' | ignore }
    if ($vertices | length) + 17 > 65535 { error make 'source vertex count plus shadow exceeds u16 indices; simplify the mesh' }
    for row in ($vertices | enumerate) {
        let v = $row.item
        let i = $row.index
        if ($v | length) != 4 { error make $'vertex ($i): expected x, y, z and animation_part' }
        for axis in 0..<3 { integer ($v | get $axis) (-32768) 32767 $'vertex ($i) axis ($axis)' | ignore }
        integer $v.3 0 3 $'vertex ($i) animation_part: 0=body, 1/2=opposing limbs, 3=sway' | ignore
        if ($v.0 | math abs) + ($v.2 | math abs) + 46 + 13 * 256 > 32767 {
            error make $'vertex ($i): horizontal extent can overflow during rotation/movement; reduce scale'
        }
        if $v.1 < 0 or $v.1 + 14 + 570 > 32767 {
            error make $'vertex ($i): height must be above the ground and leave room for bob/hop; adjust origin/scale'
        }
    }
    for row in ($faces | enumerate) {
        let f = $row.item
        let i = $row.index
        if ($f | length) != 5 { error make $'triangle ($i): expected three indices, palette index and shade' }
        for id in ($f | first 3) { integer $id 0 (($vertices | length) - 1) $'triangle ($i) vertex index' | ignore }
        integer $f.3 0 (($colors | length) - 1) $'triangle ($i) material index' | ignore
        integer $f.4 0 255 $'triangle ($i) shade' | ignore
        let a = $vertices | get $f.0 | first 3
        let b = $vertices | get $f.1 | first 3
        let c = $vertices | get $f.2 | first 3
        if (cross (subtract $b $a) (subtract $c $a)) == [0 0 0] {
            error make $'triangle ($i): degenerate after Q8 conversion; remove it or increase detail size'
        }
    }
    if (($faces | length) + 16) * 3 > 4096 { error make 'triangle count plus contact shadow exceeds the 4096-index mesh capacity' }
    let count = packed-vertex-count $vertices $faces
    if $count.vertices > 768 or $count.batches > 64 {
        error make $'mesh needs ($count.vertices)/768 animated vertices and ($count.batches)/64 batches including shadow; simplify geometry or reduce shade splits'
    }
    $count
}

export def serialize-mesh [vertices: list, faces: list, colors: list] {
    let count = validate-mesh $vertices $faces $colors
    let palette = $colors | each {|v| '0x' + ($v | format number --no-prefix | get lowerhex | fill --alignment right --character '0' --width 8) } | str join ', '
    [
        '// Generated by scripts/export-mesh.nu. Units: 1/256 metre.'
        'pub const Vertex = struct { x: i16, y: i16, z: i16, part: u8 };'
        'pub const Face = struct { a: u16, b: u16, c: u16, material: u8, shade: u8 };'
        $'pub const packed_vertex_count = ($count.vertices);'
        ('pub const colors = [_]u32{ ' + $palette + ' };')
        'pub const vertices = [_]Vertex{'
        ...($vertices | each {|v| '    .{ .x = ' + ($v.0 | into string) + $', .y = ($v.1), .z = ($v.2), .part = ($v.3)' + ' },' })
        '};'
        'pub const faces = [_]Face{'
        ...($faces | each {|f| '    .{ .a = ' + ($f.0 | into string) + $', .b = ($f.1), .c = ($f.2), .material = ($f.3), .shade = ($f.4)' + ' },' })
        '};' ''
    ] | str join (char nl)
}

# The bpy bridge returns raw evaluated data, with no export policy applied.
export def assemble-mesh [raw: record] {
    if not $raw.found { error make $'collection ($raw.collection) not found; available: ($raw.available | str join ", ")' }
    if ($raw.objects | is-empty) { error make $'collection ($raw.collection) is empty' }
    let light0 = [-0.35 -0.6 0.8]
    let light_length = dot $light0 $light0 | math sqrt
    let light = $light0 | each {|v| $v / $light_length }
    mut vertices = []
    mut faces = []
    mut palette = {}
    for obj in ($raw.objects | sort-by name) {
        if $obj.type != 'MESH' { error make $'($obj.name): only mesh objects belong in the export collection; found ($obj.type)' }
        let part = integer $obj.animation_part 0 3 $'($obj.name) animation_part'
        if ($obj.positions | is-empty) or ($obj.triangles | is-empty) { error make $'($obj.name): mesh has no faces' }
        if not (finite $obj.determinant) or ($obj.determinant | math abs) < 0.0000000001 { error make $'($obj.name): transform has zero/non-finite scale' }
        let base = $vertices | length
        $vertices = $vertices | append ($obj.positions | enumerate | each {|p| quantize-position $p.item $'($obj.name) vertex ($p.index)' | append $part })
        for row in ($obj.triangles | enumerate) {
            let tri = $row.item
            if $tri.material == null { error make $'($obj.name) triangle ($row.index): missing material in slot ($tri.material_index)' }
            let mat = $tri.material
            let index = integer $mat.palette_index 0 254 $'($mat.name) palette_index'
            if ($mat.color | length) != 4 or not ($mat.color | all {|v| (finite $v) and $v >= 0 and $v <= 1 }) {
                error make $'($mat.name): viewport diffuse color channels must be finite and in 0..1'
            }
            if $mat.color.3 != 1 { error make $'($mat.name): only opaque materials are supported; set viewport alpha to 1' }
            let color = $mat.color | reduce --fold 0 {|v, acc| $acc * 256 + (round-even ($v * 255)) }
            let key = $index | into string
            if $key in ($palette | columns) and ($palette | get $key) != $color {
                error make $'($mat.name): palette_index ($index) is shared by different colors; assign a unique index'
            }
            $palette = $palette | upsert $key $color
            let shade = round-even (255 * (0.64 + 0.36 * ([0 (dot $tri.normal $light)] | math max)))
            let local = if $obj.determinant < 0 { [$tri.vertices.0 $tri.vertices.2 $tri.vertices.1] } else { $tri.vertices }
            for id in $local { integer $id 0 (($obj.positions | length) - 1) $'($obj.name) triangle ($row.index) vertex index' | ignore }
            $faces = $faces | append [($local | each {|id| $base + $id } | append [$index $shade])]
        }
    }
    let indices = $palette | columns | into int | sort
    if $indices != (0..<($palette | columns | length) | each {|i| $i }) { error make $'palette_index values must be contiguous from zero; found ($indices | to nuon)' }
    let final_palette = $palette
    let colors = $indices | each {|i| $final_palette | get ($i | into string) }
    validate-mesh $vertices $faces $colors | ignore
    {vertices: $vertices, faces: $faces, colors: $colors}
}
