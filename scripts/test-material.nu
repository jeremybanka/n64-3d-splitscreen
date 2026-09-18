# Native host test of the adapter's material-state transitions.
const root = path self ..

def main [] {
    cd $root
    let directory = (mktemp --directory --tmpdir n64-material-test.XXXXXX)
    let executable = ($directory | path join material-test)
    let compiler = ($env.HOST_CC? | default 'cc')
    try {
        for textured in [0 1] {
            let compiled = (run-external $compiler '-std=c11' '-Wall' '-Wextra' '-Werror' $'-DTEXTURED=($textured)' '-Itests/material-fakes' '-Isrc' src/material.c tests/material-state.c '-o' $executable | complete)
            if $compiled.exit_code != 0 { error make {msg: $'Material test compilation failed: ($compiled.stderr)'} }
            let tested = (run-external $executable | complete)
            if $tested.exit_code != 0 { error make {msg: $'Material state test failed: ($tested.stdout)($tested.stderr)'} }
        }
    } catch {|failure|
        rm --recursive --force $directory
        error make {msg: $failure.msg}
    }
    rm --recursive --force $directory
    print 'Material state: flat/textured bindings, depth, and HUD-to-view reloads pass'
}
