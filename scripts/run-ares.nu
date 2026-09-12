use common.nu *
def main [] {
    let app = $ROOT | path join .build emulators ares-v147 ares.app
    let rom = $ROOT | path join n64-3d-splitscreen.z64
    if not ($app | path join Contents MacOS ares | path exists) { fail 'ares v147 is not installed; run just emulator-setup.' }
    if not ($rom | path exists) { fail $'Missing ROM: ($rom)' }
    # v148 removed macOS OpenGL. Metal presentation flickered on this machine,
    # including with stock libdragon example ROMs; preserve the tested backend.
    command /usr/bin/open [-na $app --args --setting 'Video/Driver=OpenGL 3.2' --setting 'General/HomebrewMode=true' $rom]
}
