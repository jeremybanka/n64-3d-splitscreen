use common.nu *
export def check-zig-abi [object: path] {
    let undefined = capture (tool nm) [-u $object]
    if ($undefined | is-not-empty) { fail $"Zig object has implicit external calls that bypass the audited ABI bridge:\n($undefined)" }
    if (capture (tool objdump) [-d $object]) =~ '[\s,]gp([\s,)]|$)' { fail 'Zig object uses $gp; compile with mips3+noabicalls and -fno-PIC.' }
    print 'Zig ABI: no implicit external calls; global-pointer register reserved'
}
def main [object: path = 'build/scene.o'] { check-zig-abi $object }
