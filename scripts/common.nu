# Shared native Nu utilities. External arguments remain list elements (no shell).
export const ROOT = path self | path dirname | path dirname
export def sdk [] { $env.N64_INST? | default ($ROOT | path join .build libdragon) | path expand --no-symlink }
export def tiny3d [] { $env.TINY3D_DIR? | default ($ROOT | path join .build tiny3d) | path expand --no-symlink }
export def jobs [] { $env.JOBS? | default '4' | into string }
export def tool [name: string] { sdk | path join bin $'mips64-elf-($name)' }
export def fail [message: string] { error make {msg: $message} }
export def capture [program: string, args: list = []] {
    let result = do { ^$program ...$args } | complete
    if $result.exit_code != 0 { fail $"($program) failed [($result.exit_code)]:\n($result.stderr)($result.stdout)" }
    $result.stdout | str trim
}
export def command [program: string, args: list = []] {
    let result = do { ^$program ...$args } | complete
    if ($result.stdout | is-not-empty) { print --no-newline $result.stdout }
    if ($result.stderr | is-not-empty) { print --stderr --no-newline $result.stderr }
    if $result.exit_code != 0 { fail $'($program) failed [($result.exit_code)]' }
}
export def digest [file: path] { open --raw $file | hash sha256 }
export def write-json [file: path, value: any] {
    mkdir ($file | path dirname)
    $value | to json --indent 2 | save --force $'($file).tmp'
    mv --force $'($file).tmp' $file
}
# Content comparison makes no-op builds preserve object, ELF and ROM mtimes.
export def replace-if-changed [temporary: path, output: path] {
    if ($output | path exists) and (digest $temporary) == (digest $output) { rm $temporary } else { mv --force $temporary $output }
}
export def with-temp [prefix: string, body: closure] {
    mkdir ($ROOT | path join .build)
    let scratch = mktemp --directory --tmpdir-path ($ROOT | path join .build) $'($prefix).XXXXXX'
    try {
        let result = do $body $scratch
        rm --recursive --force $scratch
        $result
    } catch {|err|
        rm --recursive --force $scratch
        error make $err
    }
}
