use std/assert
use common.nu *
use build.nu [build-rom ROM]
use verify-rom.nu [check-rom]
def main [] {
    cd $ROOT
    rm --recursive --force build $'($ROM).z64'
    mkdir build/roms
    let normal = {views: 4, autotour: 0, profile: 0, validate: 0, benchmark: 0, content: meadow, audio: 1}
    let variants = (1..4 | each {|views| {name: $'bunny-meadow-($views)-players', config: ($normal | update views $views)} }) | append [
        {name: bunny-meadow-validation, config: ($normal | merge {validate: 1, profile: 1, autotour: 1})}
        {name: bunny-meadow-benchmark, config: ($normal | update benchmark 1)}
        {name: bunny-meadow-benchmark-no-audio, config: ($normal | merge {benchmark: 1, audio: 0})}
        {name: robot-courtyard-4-players, config: ($normal | update content robot-courtyard)}
        {name: robot-courtyard-validation, config: ($normal | merge {content: robot-courtyard, validate: 1, profile: 1, autotour: 1})}
    ]
    for variant in $variants {
        print $'Building ($variant.name)'
        build-rom $variant.config
        check-rom
        cp $'($ROM).z64' $'build/roms/($variant.name).z64'
    }
    build-rom $normal
    check-rom
    let hashes = glob build/roms/*.z64 | sort | each {|file| {file: ($file | path basename), hash: (digest $file)} }
    assert equal ($hashes.hash | uniq | length) ($variants | length) 'Different ROM configurations unexpectedly have identical bytes'
    $hashes | each {|row| $'($row.hash)  ($row.file)' } | str join (char nl) | save --force build/roms/SHA256SUMS
    assert equal (digest $'($ROM).z64') (digest build/roms/bunny-meadow-4-players.z64) 'Default ROM must restore playable four-player settings'
    print $'PASS: ($variants | length) unique ROM variants; default restored'
}
