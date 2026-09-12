use mesh-format.nu [assemble-mesh validate-mesh serialize-mesh]
use blender.nu run-blender

export def export-asset [source: path, collection: string, output: path] {
    let source_path = $source | path expand
    let target = $output | path expand
    if not ($source_path | path exists) or ($source_path | path parse | get extension) != 'blend' { error make $'source must be an existing .blend file: ($source_path)' }
    if ($target | path parse | get extension) != 'zig' or $target == $source_path { error make 'output must be a separate .zig file; the source is never overwritten' }
    let raw = run-blender {action: extract, source: $source_path, collection: $collection}
    let mesh = assemble-mesh $raw
    let count = validate-mesh $mesh.vertices $mesh.faces $mesh.colors
    let result = serialize-mesh $mesh.vertices $mesh.faces $mesh.colors
    mkdir ($target | path dirname)
    # Write beside the destination; rename is atomic and validation is finished.
    let temporary = mktemp --tmpdir-path ($target | path dirname) '.mesh-export.XXXXXX'
    try { $result | save --force $temporary; mv --force $temporary $target } catch {|e|
        rm --force $temporary
        error make $e
    }
    print $'Exported ($mesh.vertices | length) vertices / ($mesh.faces | length) triangles; ($count.vertices)/768 packed animated vertices, ($count.batches)/64 batches -> ($target)'
}

# Export an explicit collection from a saved Blender source without saving it.
def main [--source: path, --collection: string, --output: path] {
    if $source == null or $collection == null or $output == null { error make '--source, --collection and --output are required' }
    export-asset $source $collection $output
}
