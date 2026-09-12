# Model authorship is native Nu data; the adapter only maps it to bpy calls.
export def box [name: string, position: list, scale: list, material: int, --part: int = 0] {
    {name: $name, shape: cube, position: $position, scale: $scale, rotation: [0 0 0], materials: [$material], animation_part: $part}
}

def orb [name: string, position: list, scale: list, --material: int = 0, --segments: int = 6, --rings: int = 3, --part: int = 0, --tilt: number = 0] {
    let base = {name: $name, position: $position, scale: $scale, rotation: [0 $tilt 0], materials: [$material], animation_part: $part}
    if $rings == 2 {
        # Blender clamps UV-sphere rings to three; use the original octahedron.
        $base | merge {
            shape: mesh,
            vertices: [[1 0 0] [0 1 0] [-1 0 0] [0 -1 0] [0 0 1] [0 0 -1]],
            faces: [[4 0 1] [4 1 2] [4 2 3] [4 3 0] [5 1 0] [5 2 1] [5 3 2] [5 0 3]]
        }
    } else { $base | merge {shape: sphere, segments: $segments, rings: $rings} }
}

export def material [name: string, rgb: list, index: int] {
    {name: $name, color: ($rgb | each {|v| $v / 255 } | append 1), palette_index: $index}
}

export def rabbit-scene [] {
    let materials = [
        (material 'Vanilla fur' [247 237 214] 0)
        (material 'Rose ears and nose' [233 143 159] 1)
        (material 'Espresso eyes' [38 48 63] 2)
        (material 'Player jersey' [234 123 83] 3)
        (material 'Cream muzzle' [255 250 230] 4)
        {name: 'Sage backdrop', color: [0.25 0.37 0.32 1], palette_index: null}
    ]
    mut objects = [
        (orb 'Pear-shaped jersey' [0 0 0.97] [0.44 0.31 0.57] --material 3)
        (orb 'Big soft head' [0 -0.035 1.70] [0.49 0.39 0.43] --rings 4)
    ]
    for side in [-1 1] {
        let front = if $side < 0 { 1 } else { 2 }
        let back = if $side < 0 { 2 } else { 1 }
        $objects = $objects | append [
            (orb 'Long ear' [($side * 0.235) 0.015 2.28] [0.145 0.115 0.60] --segments 4 --rings 2 --part 3 --tilt ($side * 0.12))
            (orb 'Pink inner ear' [($side * 0.235) -0.094 2.30] [0.082 0.021 0.43] --material 1 --segments 4 --rings 2 --part 3 --tilt ($side * 0.12))
            (orb 'Little arm' [($side * 0.47) -0.015 0.99] [0.145 0.17 0.37] --rings 2 --part $front --tilt ($side * 0.22))
            (orb 'Large bunny shoe' [($side * 0.245) -0.12 0.23] [0.22 0.34 0.23] --rings 2 --part $back)
            (orb 'Bright eye' [($side * 0.19) -0.383 1.77] [0.061 0.029 0.095] --material 2 --segments 4 --rings 2)
            (orb 'Eye sparkle' [($side * 0.19 - 0.012) -0.412 1.809] [0.020 0.010 0.025] --material 4 --segments 4 --rings 2)
            (orb 'Muzzle cheek' [($side * 0.10) -0.381 1.57] [0.135 0.068 0.10] --material 4 --segments 4 --rings 2)
        ]
    }
    $objects = $objects | append [
        (orb 'Tiny nose' [0 -0.465 1.64] [0.050 0.032 0.042] --material 1 --segments 4 --rings 2)
        (orb 'Cotton tail' [0 0.35 0.72] [0.21 0.19 0.21] --material 4 --segments 4 --rings 2)
        {name: 'Preview floor (not exported)', shape: mesh, position: [0 0 0], scale: [1 1 1], rotation: [0 0 0], materials: [5], animation_part: null, export: false,
            vertices: [[-100 -100 0] [100 -100 0] [100 100 0] [-100 100 0]], faces: [[0 1 2 3]]}
    ]
    {collection: Character, materials: $materials, objects: $objects, studio: {
        camera_position: [4 -7 3.8], camera_target: [0 0 1.35], camera_scale: 3.7,
        light_position: [-3 -4 7], light_energy: 450, light_size: 5,
        samples: 24, resolution: [640 640], world_color: [0.35 0.35 0.35]
    }}
}

export def robot-scene [] {
    let materials = [
        (material 'Steel shell' [195 216 226] 0)
        (material 'Player chest' [239 137 101] 1)
        (material 'Dark joints' [42 59 79] 2)
        (material 'Cyan display' [94 218 228] 3)
    ]
    mut objects = [
        (box 'Chest' [0 0 0.95] [0.36 0.24 0.40] 1)
        (box 'Neck' [0 0 1.42] [0.12 0.12 0.08] 2)
        (box 'Head' [0 0 1.74] [0.37 0.28 0.26] 0)
        (box 'Display' [0 -0.286 1.76] [0.26 0.018 0.11] 3)
        (box 'Antenna' [0 0 2.12] [0.035 0.035 0.12] 2 --part 3)
        (box 'Antenna light' [0 0 2.28] [0.075 0.075 0.06] 3 --part 3)
    ]
    for side in [-1 1] {
        let front = if $side < 0 { 1 } else { 2 }
        let back = if $side < 0 { 2 } else { 1 }
        $objects = $objects | append [
            (box $'Arm ($side)' [($side * 0.48) 0 0.98] [0.10 0.14 0.32] 0 --part $front)
            (box $'Leg ($side)' [($side * 0.20) 0 0.36] [0.11 0.12 0.20] 2 --part $back)
            (box $'Foot ($side)' [($side * 0.20) -0.08 0.10] [0.15 0.22 0.10] 0 --part $back)
        ]
    }
    {collection: Character, materials: $materials, objects: $objects}
}
