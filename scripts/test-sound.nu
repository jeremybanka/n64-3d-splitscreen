use common.nu *

# The host fixture drives the production C adapter with stateful stream cursors.
# Runtime decoder/RSP correctness is still checked by booting the benchmark ROM.
def main [] {
    cd $ROOT
    with-temp sound-test {|scratch|
        for audio in [0 1] {
            let output = $scratch | path join $'sound-($audio)'
            command zig [cc -std=c11 -Wall -Werror $'-DAUDIO=($audio)' -Itests/audio -Isrc tests/audio/sound-test.c src/sound.c -o $output]
            command $output
        }
    }
}
