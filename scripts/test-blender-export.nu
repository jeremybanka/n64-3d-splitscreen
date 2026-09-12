# Optional integration tests: Nu owns fixtures, commands, assertions and hashes.
use std/assert
use blender.nu [run-blender write-source]
use export-mesh.nu export-asset
use mesh-format.nu [assemble-mesh subtract cross dot]
use model-recipes.nu [rabbit-scene robot-scene box material]

def fails [message: string, action: closure] {
    let result = try { do $action | collect | ignore; {failed: false} } catch {|e| {failed: true, message: $e.debug} }
    assert $result.failed $'Expected error containing ($message)'
    assert ($result.message =~ $message) $'Wrong error: ($result.message)'
}

def digest [path: path] { open --raw $path | hash sha256 }
def extracted [source: path] { run-blender {action: extract, source: $source, collection: Character} | assemble-mesh $in }

# Blender may reorder a primitive's loop triangles when rebuilding its mesh.
# Keep indexed vertices, colors and limits exact; compare the triangle multiset.
def equivalent-recipe [expected: string, actual: string] {
    let before = $expected | split row 'pub const faces = [_]Face{'
    let after = $actual | split row 'pub const faces = [_]Face{'
    assert equal $before.0 $after.0
    assert equal ($before.1 | lines | sort) ($after.1 | lines | sort)
}

def suite [root: path, scratch: path] {
    for name in [rabbit robot] {
        let source = $root | path join assets $'($name).blend'
        let checked = $root | path join src generated $'($name).zig'
        let target = $scratch | path join $'($name).zig'
        let before = digest $source
        export-asset $source Character $target
        let first = open --raw $target
        export-asset $source Character $target
        assert equal $first (open --raw $target)
        assert equal $first (open --raw $checked)
        assert equal $before (digest $source)
        print $'($name): repeat export matches checked-in data; source SHA-256 unchanged'

        let scene = if $name == rabbit { rabbit-scene } else { robot-scene }
        let generated = $scratch | path join $'generated-($name).blend'
        write-source $scene $generated
        export-asset $generated Character $target
        equivalent-recipe $first (open --raw $target)
        let generated_hash = digest $generated
        fails 'exists; choose a new path' { write-source $scene $generated }
        assert equal $generated_hash (digest $generated)
        print $'($name): native Nu recipe preserves original mesh and refuses implicit overwrite'
    }

    let fixture = $scratch | path join fixture.blend
    let output = $scratch | path join fixture.zig
    let white = material White [255 255 255] 0
    let red = material Red [255 0 0] 1
    let cube = box Chest [0 0 0.95] [0.36 0.24 0.40] 0
    let baseline = {collection: Character, materials: [$white], objects: [$cube]}

    write-source ($baseline | update objects [($cube | update scale [-0.36 0.24 0.40])]) $fixture
    let mirrored = extracted $fixture
    let center = [0 243 0]
    for face in $mirrored.faces {
        let a = $mirrored.vertices | get $face.0 | first 3
        let b = $mirrored.vertices | get $face.1 | first 3
        let c = $mirrored.vertices | get $face.2 | first 3
        let centroid = 0..<3 | each {|i| (($a | get $i) + ($b | get $i) + ($c | get $i)) / 3 }
        assert ((dot (cross (subtract $b $a) (subtract $c $a)) (subtract $centroid $center)) > 0)
    }
    print 'Mirrored transform: all triangle normals still point outward'

    let slotted = $cube | update materials [0 1] | insert polygon_materials [1 0 0 0 0 0]
    write-source {collection: Character, materials: [$white $red], objects: [$slotted]} $fixture --overwrite
    let mesh = extracted $fixture
    assert equal ($mesh.faces | where {|f| $f.3 == 1 } | length) 2
    assert equal ($mesh.faces | where {|f| $f.3 == 0 } | length) 10
    print 'Per-face material slots survive evaluated Blender triangulation'

    for case in [
        {scene: ($baseline | update materials [($white | update palette_index null)]), error: palette_index}
        {scene: ($baseline | update materials [($white | update palette_index 8)]), error: contiguous}
        {scene: {collection: Character, materials: [$white ($red | update palette_index 0)], objects: [$slotted]}, error: 'shared by different colors'}
        {scene: ($baseline | update objects [($cube | update scale [0 0.24 0.40])]), error: 'zero/non-finite scale'}
        {scene: ($baseline | update objects [($cube | update animation_part null)]), error: 'Chest animation_part'}
    ] {
        write-source $case.scene $fixture --overwrite
        'previous valid output' | save --force $output
        let source_hash = digest $fixture
        fails $case.error { export-asset $fixture Character $output }
        assert equal 'previous valid output' (open --raw $output)
        assert equal $source_hash (digest $fixture)
    }
    fails 'not found' { export-asset ($root | path join assets rabbit.blend) Missing $output }
    print 'Metadata/transform errors are actionable and preserve both source and previous output'
}

def main [] {
    let root = $env.FILE_PWD | path dirname
    let scratch = mktemp -d -t n64-blender-tests.XXXXXX
    try { suite $root $scratch; rm -rf $scratch } catch {|e| rm -rf $scratch; error make $e }
    print 'Blender integration: all native Nu source, recipe, material, mirror and failure-preservation checks pass'
}
