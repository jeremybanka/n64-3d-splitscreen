# Convert ready audio sources and pack only explicitly selected DragonFS files.
use common.nu *
const BUILD_SCRIPT = path self

def same-state [state: path, value: any, output: path] {
    ($output | path exists) and ($state | path exists) and ((open $state) == $value)
}

export def build-audio-files []: nothing -> list<path> {
    let converter = sdk | path join bin audioconv64
    let flags = [--wav-mono --wav-compress 1]
    let implementation = [($BUILD_SCRIPT) ($ROOT | path join scripts common.nu)] | each {|file| digest $file }
    mkdir build/audio
    mut files = []
    for name in [meadow hop] {
        let source = $'assets/audio/($name).wav'
        let output = $'build/audio/($name).wav64'
        let state = $'($output).json'
        let identity = {implementation: $implementation, converter: (digest $converter), flags: $flags, source: (digest $source)}
        if not (same-state $state $identity $output) {
            print $'[WAV64] ($source)'
            with-temp audio-convert {|scratch|
                command $converter ($flags | append [-o $scratch $source])
                replace-if-changed ($scratch | path join $'($name).wav64') $output
            }
            write-json $state $identity
        }
        $files = $files | append $output
    }
    $files
}

# Fresh temporary staging excludes stale files from earlier configurations.
export def build-filesystem [files: list<path>, output: path]: nothing -> path {
    let ordered = $files | sort
    let names = $ordered | each {|file| $file | path basename }
    if ($ordered | is-empty) or ($names | uniq | length) != ($names | length) {
        fail 'DragonFS requires a nonempty list of files with distinct basenames'
    }
    let packer = sdk | path join bin mkdfs
    let identity = {
        implementation: ([($BUILD_SCRIPT) ($ROOT | path join scripts common.nu)] | each {|file| digest $file })
        packer: (digest $packer)
        files: ($ordered | each {|file| {name: ($file | path basename), hash: (digest $file)} })
    }
    let state = $'($output).json'
    if not (same-state $state $identity $output) {
        print $'[DFS] ($output)'
        mkdir ($output | path dirname)
        with-temp audio-filesystem {|scratch|
            let directory = $scratch | path join files
            mkdir $directory
            for file in $ordered { cp $file ($directory | path join ($file | path basename)) }
            let temporary = $scratch | path join audio.dfs
            capture $packer [$temporary $directory] | ignore
            replace-if-changed $temporary $output
        }
        write-json $state $identity
    }
    $output
}
