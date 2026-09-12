use common.nu *
use sdk-identity.nu [record-compiler]
const IMAGE = 'ghcr.io/dragonminded/libdragon@sha256:c5de552d54d6b80bf8a8f14ed88b2d77d55a08930919d8644649811279e08117'
def main [] {
    if $nu.os-info.name != linux or $nu.os-info.arch != x86_64 { fail 'CI compiler setup requires Linux x86_64; use just setup locally.' }
    let install = sdk
    command docker [pull $IMAGE]
    let container = capture docker [create $IMAGE]
    try {
        mkdir $install
        command docker [cp $'($container):/n64_toolchain/.' $'($install)/']
        record-compiler $install $IMAGE
    } catch {|err|
        command docker [rm $container]
        error make $err
    }
    command docker [rm $container]
}
