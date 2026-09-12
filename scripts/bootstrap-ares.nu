use common.nu *
const VERSION = '147'
const SHA256 = '9d8376b5dde4869bc0613efe3a544471e120b6e4f0b02ebe0c34295b034df147'
def main [] {
    if $nu.os-info.name != macos { fail 'The pinned ares app bundle is only available on macOS.' }
    let downloads = $ROOT | path join .build downloads
    let archive = $downloads | path join $'ares-macos-universal-v($VERSION).zip'
    let install = $ROOT | path join .build emulators $'ares-v($VERSION)'
    let app = $install | path join ares.app
    if ($app | path join Contents MacOS ares | path exists) { print $'ares v($VERSION) is already installed at ($app)'; return }
    mkdir $downloads
    if not ($archive | path exists) {
        http get $'https://github.com/ares-emulator/ares/releases/download/v($VERSION)/ares-macos-universal.zip' | save --force $'($archive).part'
        mv --force $'($archive).part' $archive
    }
    let actual = digest $archive
    if $actual != $SHA256 { fail $'ares archive checksum mismatch: expected ($SHA256), found ($actual). Remove ($archive) and rerun just emulator-setup.' }
    with-temp ares-unpack {|scratch|
        command ditto [-x -k $archive $scratch]
        let unpacked = $scratch | path join $'ares-v($VERSION)' ares.app
        if not ($unpacked | path exists) { fail 'The ares archive did not contain the expected app bundle.' }
        mkdir $install
        mv $unpacked $app
    }
    print $'Installed ares v($VERSION) at ($app)'
}
