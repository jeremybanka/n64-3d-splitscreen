# Build commands mirror the pinned SDK n64.mk; no project Makefile is generated.
# Third-party Makefiles remain responsible for their own SDK/Tiny3D libraries.
use common.nu *
use build-audio.nu [build-audio-files build-filesystem]
use verify-zig-abi.nu [check-zig-abi]
export const ROM = 'n64-3d-splitscreen'
const BUILD_SCRIPT = path self

def same-state [state: path, value: any, output: path] {
    ($output | path exists) and ($state | path exists) and ((open $state) == $value)
}
def check-content [content: string] {
    if $content not-in [meadow robot-courtyard] { fail '--content must be meadow or robot-courtyard' }
}
export def build-object [content: string = meadow] {
    check-content $content
    mkdir build
    print '[ZIG] src/scene.zig'
    command zig [build-obj -target mips64-freestanding-gnuabin32 -mcpu mips3+noabicalls -fno-PIC -O ReleaseSmall -fno-stack-check -femit-bin=build/scene.o.tmp --dep content -Mroot=src/scene.zig $'-Mcontent=src/content-($content).zig']
    command zig [run tools/patch_mips_abi.zig -- build/scene.o.tmp]
    command (tool objcopy) [--rename-section .mdebug.abiN32=.mdebug.abiO64 build/scene.o.tmp]
    check-zig-abi build/scene.o.tmp
    replace-if-changed build/scene.o.tmp build/scene.o
}

export def build-rom [config: record] {
    let content = $config.content? | default meadow
    check-content $content
    let audio = $config.audio? | default 1
    if $audio not-in [0 1] { fail '--audio must be 0 or 1' }
    let install = sdk
    $env.N64_INST = $install
    let tiny = tiny3d
    if not ($install | path join include n64.mk | path exists) { fail $'libdragon is not installed at ($install); run just setup' }
    if not ($tiny | path join t3d.mk | path exists) { fail 'Tiny3D is not installed; run just setup' }
    let library = $tiny | path join build libt3d.a
    # Let the upstream recipe track its own sources; a no-op does not touch its archive.
    with-env {N64_INST: $install} { command make [-C $tiny $'-j(jobs)'] }
    mkdir build
    $config | to json | save --force build/settings.tmp
    replace-if-changed build/settings.tmp build/settings.json
    let implementation = [($BUILD_SCRIPT) ($ROOT | path join scripts common.nu)] | each {|file| digest $file }
    let include = $install | path join mips64-elf include
    let lib = $install | path join mips64-elf lib
    let flags = [
        # t3d.mk resolves its own path and retains this double slash. Preserve
        # that spelling because header debug paths enter the ROM symbol table.
        -march=vr4300 -mtune=vr4300 -mabi=o64 $'-I($include)' $'-I($tiny | path expand)//src'
        -falign-functions=32 -ffunction-sections -fdata-sections -g $'-ffile-prefix-map=($env.PWD)='
        -ffast-math -ftrapping-math -fno-associative-math -DN64 -O2 -Wall -Werror
        -Wno-error=deprecated-declarations -fdiagnostics-color=always
        -Wno-error=unused-variable -Wno-error=unused-but-set-variable -Wno-error=unused-function
        -Wno-error=unused-parameter -Wno-error=unused-but-set-parameter -Wno-error=unused-label
        -Wno-error=unused-local-typedefs -Wno-error=unused-const-variable -ftrivial-auto-var-init=pattern -std=gnu17
        $'-DINITIAL_VIEWS=($config.views)' $'-DAUTOTOUR=($config.autotour)'
        $'-DPROFILE=($config.profile)' $'-DBENCHMARK=($config.benchmark)' $'-DAUDIO=($audio)'
    ] | append (if $config.validate == 1 { [-DRDPQ_VALIDATE] } else { [] })
    mut objects = []
    for source in (glob src/*.c | sort) {
        let relative = $source | path relative-to $env.PWD
        let object = $'build/($source | path parse | get stem).o'
        let state = $'($object).json'
        # GCC discovers transitive headers on every invocation, including new
        # imports; the preprocessed bytes include source locations for debug info.
        let input = capture (tool gcc) ([-E] | append $flags | append $relative)
        let compiler = [gcc as] | each {|name| digest (tool $name) }
        let identity = {implementation: $implementation, compiler: ($compiler | append (digest (capture (tool gcc) [-print-prog-name=cc1]))), flags: $flags, input: ($input | hash sha256)}
        if not (same-state $state $identity $object) {
            print $'[CC] ($relative)'
            command (tool gcc) ([-c] | append $flags | append [-o $'($object).tmp' $relative])
            replace-if-changed $'($object).tmp' $object
            write-json $state $identity
        }
        $objects = $objects | append $object
    }
    build-object $content
    $objects = $objects | append build/scene.o
    let elf = $'build/($ROM).elf'
    let link_flags = [
        -lc -mabi=o64 '-Wl,-g' $'-Wl,-L($lib)' '-Wl,-ldragon' '-Wl,-lm' '-Wl,-ldragonsys'
        '-Wl,-Tn64.ld' '-Wl,--gc-sections' '-Wl,--wrap,__do_global_ctors' $'-Wl,-Map=build/($ROM).map'
    ]
    # libc/libm, libgcc, startup objects and linker specs are inputs too. Cover
    # the SDK library tree and the compiler's selected runtime directory, so
    # replacing a runtime archive cannot silently reuse an older ELF.
    let runtime = capture (tool g++) [-mabi=o64 -print-libgcc-file-name] | path dirname
    let libraries = glob ($lib | path join '**/*') --follow-symlinks | append (glob ($runtime | path join '**/*.{a,o,ld,specs}') --follow-symlinks) | where {|p| ($p | path expand | path type) != dir } | sort | uniq
    let dependencies = $objects | append $library | append $libraries
    let link_tools = [g++ ld] | each {|name| digest (tool $name) }
    let identity = {implementation: $implementation, linker: ($link_tools | append (digest (capture (tool g++) [-print-prog-name=collect2]))), flags: $link_flags, specs: (capture (tool g++) [-dumpspecs] | hash sha256), dependencies: ($dependencies | each {|p| {path: $p, hash: (digest $p)} })}
    if not (same-state $'($elf).json' $identity $elf) {
        print $'[LD] ($elf)'
        command (tool g++) ([-o $'($elf).tmp'] | append $objects | append $library | append $link_flags)
        replace-if-changed $'($elf).tmp' $elf
        write-json $'($elf).json' $identity
        command (tool size) [-G $elf]
    }
    let audio_files = if $audio == 1 { build-audio-files } else { [] }
    let filesystem = if ($audio_files | is-empty) { null } else { build-filesystem $audio_files $'build/($ROM).dfs' }
    let rom = $'($ROM).z64'
    let packaging = [n64sym n64elfcompress n64tool ed64romconfig] | each {|name| {name: $name, hash: (digest ($install | path join bin $name))} }
    let identity = {implementation: $implementation, elf: (digest $elf), strip: (digest (tool strip)), tools: $packaging, filesystem: (if $filesystem == null { null } else { digest $filesystem })}
    if not (same-state build/rom.json $identity $rom) {
        print $'[Z64] ($rom)'
        command ($install | path join bin n64sym) [$elf $'($elf).sym']
        cp --force $elf $'($elf).stripped'
        command (tool strip) [-s $'($elf).stripped']
        command ($install | path join bin n64elfcompress) [-o build -c 1 $'($elf).stripped']
        let temporary = $'($ROM).tmp.z64'
        let assets = if $filesystem == null { [--align 8] } else { [--align 16 $filesystem] }
        command ($install | path join bin n64tool) ([--title 'BUNNY MEADOW' --toc --output $temporary --align 256 $'($elf).stripped' --align 8 $'($elf).sym'] | append $assets)
        command ($install | path join bin ed64romconfig) [--savetype none --regionfree --controller1 n64 --controller2 n64 --controller3 n64 --controller4 n64 $temporary]
        replace-if-changed $temporary $rom
        write-json build/rom.json $identity
    }
}

def main [action: string = 'rom', --views: int = 4, --autotour: int = 0, --profile: int = 0, --validate: int = 0, --benchmark: int = 0, --content: string = meadow, --audio: int = 1] {
    # Arguments are checked before any build output is touched.
    if $views not-in [1 2 3 4] { fail '--views must be 1, 2, 3, or 4' }
    for value in [$autotour $profile $validate $benchmark $audio] { if $value not-in [0 1] { fail 'Build switches must be 0 or 1' } }
    check-content $content
    cd $ROOT
    match $action {
        object => { build-object $content }
        rom => { build-rom {views: $views, autotour: $autotour, profile: $profile, validate: $validate, benchmark: $benchmark, content: $content, audio: $audio} }
        clean => { rm --recursive --force build $'($ROM).z64' }
        _ => { fail $'Unknown build action: ($action)' }
    }
}
