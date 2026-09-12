use common.nu *
use build.nu [ROM]
use verify-zig-abi.nu [check-zig-abi]
export def check-rom [] {
    let rom = $ROOT | path join $'($ROM).z64'
    let elf = $ROOT | path join build $'($ROM).elf'
    if (open --raw $rom | bytes at 0..3) != 0x[80 37 12 40] { fail 'Unexpected N64 ROM byte order/magic' }
    if (capture (tool readelf) [-h $elf]) !~ o64 { fail 'Linked ELF is not marked with the libdragon O64 ABI' }
    check-zig-abi ($ROOT | path join build scene.o)
    print 'ROM header: big-endian N64 (80 37 12 40)'
    command (tool size) [$elf]
    print $'(digest $rom)  ($rom)'
}
def main [] { check-rom }
