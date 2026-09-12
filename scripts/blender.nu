# JSON transport and filesystem ownership stay in Nu; bpy is API-only.
export def run-blender [request: record] {
    let adapter = $env.FILE_PWD | path join blender-adapter.py
    let scratch = mktemp -d -t n64-blender.XXXXXX
    let input = $scratch | path join request.json
    let output = $scratch | path join response.json
    let executable = $env.BLENDER? | default '/Applications/Blender.app/Contents/MacOS/Blender'
    try {
        $request | to json | save $input
        let process = do { ^$executable --background --factory-startup --python-exit-code 1 --python $adapter -- $input $output } | complete
        if $process.exit_code != 0 { error make $'Blender API bridge failed: ($process.stdout)($process.stderr)' }
        let result = open $output
        rm -rf $scratch
        $result
    } catch {|e|
        rm -rf $scratch
        error make $e
    }
}

export def write-source [scene: record, output: path, --overwrite, --preview: path] {
    let target = $output | path expand
    if ($target | path parse | get extension) != 'blend' { error make '--output must be a .blend file' }
    if ($target | path exists) and not $overwrite { error make $'($target) exists; choose a new path or explicitly pass --overwrite' }
    if $preview != null and ($scene.studio? | default null) == null { error make 'This scene has no studio camera for --preview' }
    let preview_path = if $preview == null { null } else { $preview | path expand }
    if $preview_path != null and ($preview_path == $target or ($preview_path | path parse | get extension) != 'png') {
        error make '--preview must be a separate .png file'
    }
    mkdir ($target | path dirname)
    if $preview_path != null { mkdir ($preview_path | path dirname) }
    run-blender {action: create, scene: $scene, output: $target, preview: $preview_path} | ignore
    print $'Generated editable source at ($target); run export-mesh.nu to update the ROM mesh'
}
