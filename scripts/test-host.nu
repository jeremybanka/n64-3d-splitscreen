# SDK/Blender-free asset and gameplay checks. Just supplies pinned tools on PATH.
def main [--optimize: string = Debug] {
    if $optimize not-in [Debug ReleaseSmall] { error make '--optimize must be Debug or ReleaseSmall' }
    let root = $env.FILE_PWD | path dirname
    cd $root
    ^nu --no-config-file scripts/test-mesh-format.nu
    ^nu --no-config-file scripts/test-texture-material.nu
    ^nu --no-config-file scripts/test-collision-workload.nu
    ^nu --no-config-file scripts/test-material.nu
    for content in [meadow robot-courtyard] {
        ^zig test -O $optimize --dep content -Mroot=src/scene.zig $'-Mcontent=src/content-($content).zig'
    }
}
