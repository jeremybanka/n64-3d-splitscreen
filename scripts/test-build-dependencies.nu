use std/assert
use common.nu *
use build.nu [build-rom]

def snapshot [paths: list<string>] { $paths | each {|path| {path: $path, hash: (digest $path), modified: ((ls $path).0.modified)} } }
def main [] {
    let install = sdk
    with-temp build-dependency-test {|scratch|
        for folder in [src/nested tools scripts] { mkdir ($scratch | path join $folder) }
        for name in [common.nu build.nu verify-zig-abi.nu] { cp ($ROOT | path join scripts $name) ($scratch | path join scripts $name) }
        cp ($ROOT | path join tools patch_mips_abi.zig) ($scratch | path join tools patch_mips_abi.zig)
        let source = $scratch | path join src scene.zig
        let object = $scratch | path join build scene.o
        let module = $scratch | path join src nested new.zig
        let embedded = $scratch | path join src value.bin
        let baseline = 'export fn sample() i32 { return @import("content").value; }'
        let build = {|| with-env {N64_INST: $install} { command $nu.current-exe [--no-config-file ($scratch | path join scripts build.nu) object] } }
        'pub const value: i32 = 7;' | save ($scratch | path join src content-meadow.zig)
        'pub const value: i32 = 17;' | save ($scratch | path join src content-robot-courtyard.zig)
        $baseline | save $source
        do $build
        let original = snapshot [$object]
        do $build
        assert equal (snapshot [$object]) $original 'No-op object build changed bytes or mtime'
        with-env {N64_INST: $install} { command $nu.current-exe [--no-config-file ($scratch | path join scripts build.nu) object --content robot-courtyard] }
        assert ((digest $object) != $original.0.hash) 'Changing the selected content module must rebuild'
        do $build
        assert equal (digest $object) $original.0.hash 'Restoring the default content must restore the original object'
        'pub const value: i32 = 11;' | save $module
        'export fn sample() i32 { return @import("nested/new.zig").value; }' | save --force $source
        do $build
        let imported = digest $object
        assert ($imported != $original.0.hash)
        'pub const value: i32 = 29;' | save --force $module
        do $build
        assert ((digest $object) != $imported) 'Changing only a newly imported module must rebuild'
        let stable = snapshot [$object]
        do $build
        assert equal (snapshot [$object]) $stable
        0x[31] | save $embedded
        'export fn sample() i32 { return @embedFile("value.bin")[0]; }' | save --force $source
        do $build
        let first_embedded = digest $object
        0x[47] | save --force $embedded
        do $build
        assert ((digest $object) != $first_embedded) 'Changing an embedded file must rebuild'
        rm $module $embedded
        $baseline | save --force $source
        do $build
        assert equal (digest $object) $original.0.hash 'Removing imports restores baseline object'
    }
    # C header and SDK library edits use a private project/library copy. Shared
    # compiler binaries and headers are read-only symlinks; no SDK is modified.
    let tiny = tiny3d
    let original_libm = $install | path join mips64-elf lib libm.a
    let original_hash = digest $original_libm
    with-temp c-dependency-test {|scratch|
        for folder in [src tools scripts] { cp --recursive ($ROOT | path join $folder) ($scratch | path join $folder) }
        let private_sdk = $scratch | path join sdk
        mkdir ($private_sdk | path join mips64-elf)
        for folder in [bin include lib libexec] { command ln [-s ($install | path join $folder) ($private_sdk | path join $folder)] }
        command ln [-s ($install | path join mips64-elf include) ($private_sdk | path join mips64-elf include)]
        cp --recursive ($install | path join mips64-elf lib) ($private_sdk | path join mips64-elf lib)
        let build = {|| with-env {N64_INST: $private_sdk, TINY3D_DIR: $tiny} { capture $nu.current-exe [--no-config-file ($scratch | path join scripts build.nu)] } }
        do $build | ignore
        let object = $scratch | path join build main.o
        let baseline = digest $object
        let source = $scratch | path join src main.c
        let nested = $scratch | path join src build-test
        mkdir $nested
        '#include "child.h"' | save ($nested | path join parent.h)
        '#define TEMPLATE_VIEWS 1' | save ($nested | path join child.h)
        $'#include "build-test/parent.h"(char nl)#undef INITIAL_VIEWS(char nl)#define INITIAL_VIEWS TEMPLATE_VIEWS(char nl)(open --raw $source)' | save --force $source
        do $build | ignore
        let first = digest $object
        assert ($first != $baseline) 'A new C header must rebuild the adapter'
        '#define TEMPLATE_VIEWS 3' | save --force ($nested | path join child.h)
        do $build | ignore
        assert ((digest $object) != $first) 'Changing only a transitive C header must rebuild'
        assert ((do $build) !~ '\[CC\]|\[LD\]|\[Z64\]') 'No-op C build must skip compilation, linking and packing'
        let marker = $scratch | path join marker.c
        let marker_object = $scratch | path join marker.o
        'int template_fixture_marker(void) { return 7; }' | save $marker
        command (tool gcc) [-mabi=o64 -c $marker -o $marker_object]
        command (tool ar) [r ($private_sdk | path join mips64-elf lib libm.a) $marker_object]
        assert ((do $build) =~ '\[LD\]') 'Replacing a runtime archive must rerun the linker'
        assert ((do $build) !~ '\[CC\]|\[LD\]|\[Z64\]') 'No-op after a library replacement must remain incremental'
    }
    assert equal (digest $original_libm) $original_hash 'Dependency fixtures must leave the shared SDK unchanged'
    cd $ROOT
    let config = {views: 4, autotour: 0, profile: 0, validate: 0, benchmark: 0, content: meadow}
    build-rom $config
    let paths = [build/main.o build/scene.o build/n64-3d-splitscreen.elf n64-3d-splitscreen.z64]
    let before = snapshot $paths
    build-rom $config
    assert equal (snapshot $paths) $before 'No-op build must preserve object, ELF and ROM bytes and mtimes'
    print 'PASS: new Zig/C imports, transitive edits, embedded files, runtime archive replacement and complete no-op ROM build'
}
