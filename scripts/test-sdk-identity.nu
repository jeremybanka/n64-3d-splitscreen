# Offline regression tests: every fake SDK and compiler lives in scratch storage.
use std/assert
use common.nu *
use sdk-identity.nu *

def expect-failure [pattern: string, action: closure] {
    let message = try { do $action; '' } catch {|err| $err.msg }
    assert ($message =~ $pattern) $'Expected failure matching ($pattern), got: ($message)'
}
def fake-compiler [install: path, version: string = $GCC_VERSION] {
    let file = $install | path join bin mips64-elf-gcc
    # The compiler fixture is itself a native Nu script; no shell interpreter.
    $'#!($nu.current-exe) --no-config-file
    def --wrapped main [...args: string] {
        if "-dumpfullversion" in $args { print "($version)" }
        if "-dumpmachine" in $args { print "($TARGET)" }
    }
' | save --force $file
    command chmod [+x $file]
}
def fixture [action: closure] {
    with-temp sdk-identity-test {|scratch|
        let install = $scratch | path join sdk
        let receipt = $scratch | path join project identity.json
        mkdir ($install | path join bin) ($install | path join include)
        'pinned SDK makefile' | save ($install | path join include n64.mk)
        fake-compiler $install
        do $action $install $receipt $scratch
    }
}
def record [install: path] { record-sdk $install ($install | path join $MANIFEST) 'test fixture' }
def main [] {
    fixture {|install receipt scratch|
        record $install
        verify $install $receipt
        let relocated = $scratch | path join relocated
        mv $install $relocated
        verify $relocated $receipt
    }
    fixture {|install receipt|
        let before = fingerprints $install
        expect-failure 'no identity receipt' { verify $install $receipt }
        assert equal $before (fingerprints $install)
        assert (not ($install | path join $MANIFEST | path exists))
    }
    fixture {|install receipt|
        record $install
        let path = $install | path join $MANIFEST
        write-json $path (open $path | update libdragon_revision another-revision)
        expect-failure 'pinned revision' { verify $install $receipt }
    }
    fixture {|install receipt scratch|
        let shared = $scratch | path join shared-bin
        mv ($install | path join bin) $shared
        command ln [-s $shared ($install | path join bin)]
        record $install
        '# replacement' | save --append ($install | path join bin mips64-elf-gcc)
        expect-failure 'contents differ.*mips64-elf-gcc' { verify $install $receipt }
    }
    fixture {|install receipt|
        record $install
        fake-compiler $install '0.0.0'
        expect-failure 'Expected GCC' { verify $install $receipt }
    }
    fixture {|install receipt|
        record $install
        '# another compiler binary' | save --append ($install | path join bin mips64-elf-gcc)
        expect-failure 'contents differ.*mips64-elf-gcc' { verify $install $receipt }
    }
    for change in [replace delete add] {
        fixture {|install receipt|
            record $install
            let path = $install | path join include n64.mk
            match $change {
                replace => { 'incompatible header' | save --force $path }
                delete => { rm $path }
                add => { 'unexpected header' | save ($install | path join include added.h) }
            }
            expect-failure 'contents differ' { verify $install $receipt }
        }
    }
    fixture {|install receipt|
        let before = fingerprints $install
        record-sdk $install $receipt 'verified external fixture'
        verify $install $receipt
        assert equal $before (fingerprints $install)
        assert (not ($install | path join $MANIFEST | path exists))
    }
    fixture {|install receipt|
        let origin = 'ghcr.io/dragonminded/libdragon@sha256:fixture'
        record-compiler $install $origin
        let stamp = open ($install | path join $COMPILER_MANIFEST)
        assert equal $stamp.origin $origin
        assert equal $stamp.compiler (compiler $install)
        record $install
        verify $install $receipt
        assert ((open ($install | path join $MANIFEST)).origin | str contains $origin)
        '# replaced binary with same version' | save --append ($install | path join bin mips64-elf-gcc)
        expect-failure 'Compiler file changed' { compiler $install }
    }
    fixture {|install receipt scratch|
        let project = $scratch | path join project
        let scripts = $project | path join scripts
        mkdir $scripts
        for name in [bootstrap-libdragon.nu sdk-identity.nu common.nu] { cp ($ROOT | path join scripts $name) ($scripts | path join $name) }
        let before = fingerprints $install
        let result = with-env {N64_INST: $install} { do { ^$nu.current-exe --no-config-file ($scripts | path join bootstrap-libdragon.nu) } | complete }
        assert ($result.exit_code != 0)
        assert ($result.stderr | str contains '--verify-source')
        assert ($result.stderr | str contains 'new empty N64_INST')
        assert equal $before (fingerprints $install)
        assert (not ($project | path join .build libdragon-src | path exists))
    }
    fixture {|install|
        command ln [-s $install ($install | path join loop)]
        expect-failure 'symlink cycle' { fingerprints $install }
    }
    print 'PASS: SDK relocation, unknown/revision/compiler/content rejection, symlink fingerprints/cycles, external recovery and CI provenance'
}
