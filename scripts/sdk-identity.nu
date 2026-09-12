# Installed SDK provenance: hashes include files in shared directory symlinks.
use common.nu *
export const REVISION = '494f1f586d3d6d5fc65b516a8ce29ccf42f85e15'
export const GCC_VERSION = '16.2.0'
export const TARGET = 'mips64-elf'
export const MANIFEST = '.n64-template-sdk.json'
export const COMPILER_MANIFEST = '.n64-template-compiler.json'

export def compiler [install: path] {
    let gcc = $install | path join bin mips64-elf-gcc
    let identity = {version: (capture $gcc [-dumpfullversion]), target: (capture $gcc [-dumpmachine])}
    if $identity != {version: $GCC_VERSION, target: $TARGET} { fail $'Expected GCC ($GCC_VERSION) for ($TARGET); found ($identity | to json --raw)' }
    let provenance = $install | path join $COMPILER_MANIFEST
    if ($provenance | path exists) {
        let recorded = open $provenance
        if $recorded.compiler? != $identity or ($recorded.files? | describe) !~ '^record' { fail 'Compiler receipt is invalid' }
        for file in ($recorded.files | transpose name expected) {
            let path = $install | path join $file.name
            if not ($path | path exists) or (digest $path) != $file.expected { fail $'Compiler file changed since bootstrap: ($file.name)' }
        }
    }
    $identity
}

def visit [install: path, directory: path, ancestors: list<string>] {
    let resolved = $directory | path expand
    if $resolved in $ancestors { fail $'SDK contains a directory symlink cycle: ($directory)' }
    mut result = {}
    for entry in (ls --all $directory | sort-by name) {
        let path = $entry.name
        if ($path | path expand | path type) == dir {
            $result = $result | merge (visit $install $path ($ancestors | append $resolved))
        } else if ($path | path basename) not-in [$MANIFEST $COMPILER_MANIFEST] {
            $result = $result | insert ($path | path relative-to $install) (digest $path)
        }
    }
    $result
}
export def fingerprints [install: path] { visit $install $install [] }
export def source-revision [source: path] {
    if (capture git [-C $source rev-parse HEAD]) != $REVISION { fail $'Source must be checked out at pinned revision ($REVISION)' }
    if (capture git [-C $source status --porcelain --untracked-files=no] | is-not-empty) { fail 'Source contains tracked changes; use a clean pinned checkout' }
}
export def record-sdk [install: path, receipt: path, origin: string] {
    if not ($install | path join include n64.mk | path exists) { fail 'The SDK is incomplete (missing include/n64.mk)' }
    let compiler_origin = $install | path join $COMPILER_MANIFEST
    let provenance = if ($compiler_origin | path exists) { $'; compiler: ((open $compiler_origin).origin)' } else { '' }
    write-json $receipt {format: 1, libdragon_revision: $REVISION, compiler: (compiler $install), origin: $'($origin)($provenance)', files: (fingerprints $install)}
}
export def record-compiler [install: path, origin: string] {
    write-json ($install | path join $COMPILER_MANIFEST) {compiler: (compiler $install), origin: $origin, files: (fingerprints $install)}
}
export def verify [install: path, receipt: path] {
    let installed = $install | path join $MANIFEST
    let path = if ($installed | path exists) { $installed } else { $receipt }
    if not ($path | path exists) { fail 'SDK has no identity receipt' }
    let expected = open $path
    if $expected.format? != 1 or $expected.libdragon_revision? != $REVISION { fail $'SDK receipt does not identify pinned revision ($REVISION)' }
    if $expected.compiler? != (compiler $install) { fail 'SDK compiler identity changed' }
    let actual = fingerprints $install
    let recorded = $expected.files?
    if ($recorded | describe) !~ '^record' { fail 'SDK receipt has invalid file fingerprints' }
    if $actual != $recorded {
        let changed = ($actual | columns) | append ($recorded | columns) | uniq | sort | where {|key| ($actual | get --optional $key) != ($recorded | get --optional $key) }
        fail $'SDK contents differ from the receipt: ($changed | first 8 | str join ", ")'
    }
    print $'Verified libdragon ($REVISION | str substring 0..11), GCC ($GCC_VERSION) at ($install)'
}

def compare-source-files [source: path, install: path] {
    mut pairs = [{source: ($source | path join n64.mk), installed: ($install | path join include n64.mk)}]
    for name in (glob ($source | path join 'include/*.{h,inc}') | append ($source | path join include ucode.S)) {
        $pairs = $pairs | append {source: $name, installed: ($install | path join $TARGET include ($name | path basename))}
    }
    for name in [libcart/cart.h fatfs/diskio.h fatfs/ff.h fatfs/ffconf.h] {
        $pairs = $pairs | append {source: ($source | path join src $name), installed: ($install | path join $TARGET include $name)}
    }
    for name in [n64.ld rsp.ld dso.ld] { $pairs = $pairs | append {source: ($source | path join $name), installed: ($install | path join $TARGET lib $name)} }
    for pair in $pairs { if (digest $pair.source) != (digest $pair.installed) { fail $'Installed SDK file does not match pinned source: ($pair.installed)' } }
}
export def verify-source [install: path, source: path, receipt: path] {
    source-revision $source
    compiler $install | ignore
    compare-source-files $source $install
    with-temp sdk-verify {|scratch|
        let archive = $scratch | path join source.tar
        # Only this pinned, clean local git tree enters the extraction directory.
        command git [-C $source archive $REVISION -o $archive]
        let reference = $scratch | path join source
        mkdir $reference
        command tar [-xf $archive -C $reference]
        with-env {N64_INST: $install} { command make [-C $reference $'-j(jobs)' libdragon] }
        for name in [libdragon.a libdragonsys.a] {
            let expected = $scratch | path join reference.a
            let actual = $scratch | path join installed.a
            command ($install | path join bin mips64-elf-objcopy) [--enable-deterministic-archives ($reference | path join $name) $expected]
            command ($install | path join bin mips64-elf-objcopy) [--enable-deterministic-archives ($install | path join $TARGET lib $name) $actual]
            if (digest $expected) != (digest $actual) { fail $'($name) differs from a rebuild of pinned source' }
        }
    }
    record-sdk $install $receipt 'Existing SDK: headers/linker scripts and rebuilt runtime archives verified; compiler version/target checked; installed tools and compiler binaries fingerprinted'
    print $'Verified existing SDK without modifying it; wrote project receipt ($receipt)'
}

def main [action: string, --install: path, --receipt: path, --source: path, --origin: string = 'Built from pinned libdragon source'] {
    let destination = $install | default (sdk)
    let project_receipt = $receipt | default ($ROOT | path join .build libdragon-identity.json)
    match $action {
        revision => { print $REVISION }
        gcc-version => { print $GCC_VERSION }
        compiler => { compiler $destination | to json | print }
        record-compiler => { record-compiler $destination $origin }
        verify => { verify $destination $project_receipt }
        verify-source => { verify-source $destination $source $project_receipt }
        record => { source-revision $source; record-sdk $destination ($receipt | default ($destination | path join $MANIFEST)) $origin }
        _ => { fail $'Unknown SDK identity action: ($action)' }
    }
}
