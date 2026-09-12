use common.nu *
use sdk-identity.nu *
def main [--verify-source: path] {
    let install = sdk
    let source = $ROOT | path join .build libdragon-src
    let receipt = $ROOT | path join .build libdragon-identity.json
    if $verify_source != null { verify-source $install $verify_source $receipt; return }
    if ([include/n64.mk mips64-elf/lib/libdragon.a mips64-elf/include/libdragon.h .n64-template-sdk.json] | any {|name| $install | path join $name | path exists }) {
        try { verify $install $receipt } catch {|err|
            fail $"($err.msg)\nRefusing to overwrite or silently reuse the SDK at ($install).\nFor an unmarked SDK: nu scripts/bootstrap-libdragon.nu --verify-source /path/to/clean/pinned/libdragon-source\nThis rebuilds runtime archives in temporary project storage and compares them.\nIf incompatible, choose a new empty N64_INST directory and rerun setup. Keep the old installation until its other projects have migrated."
        }
        return
    }
    let gcc = $install | path join bin mips64-elf-gcc
    if ($gcc | path exists) { compiler $install | ignore }
    mkdir ($ROOT | path join .build)
    if not ($source | path join .git | path exists) { command git [clone https://github.com/DragonMinded/libdragon.git $source] }
    if (capture git [-C $source status --porcelain --untracked-files=no] | is-not-empty) { fail $'SDK source has tracked changes: ($source); preserve them before setup.' }
    command git [-C $source fetch origin $REVISION]
    command git [-C $source checkout --detach $REVISION]
    with-env {N64_INST: $install, BUILD_PATH: ($ROOT | path join .build libdragon-toolchain-build), DOWNLOAD_PATH: ($ROOT | path join .build downloads), JOBS: (jobs)} {
        if not ($gcc | path exists) {
            command ($source | path join tools build-toolchain.sh)
            record-compiler $install $'Built from libdragon ($REVISION) tools/build-toolchain.sh'
        }
        compiler $install | ignore
        cd $source
        command './build.sh'
        source-revision $source
        record-sdk $install ($install | path join $MANIFEST) 'Built from pinned libdragon source'
    }
}
