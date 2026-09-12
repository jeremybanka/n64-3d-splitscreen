use common.nu *
def main [] {
    cd $ROOT
    for script in (glob scripts/*.nu) {
        if not (nu-check --debug $script) { fail $'Nu parse check failed: ($script)' }
    }
    # Blender's bpy API is the approved Python language boundary; it cannot be
    # imported by host Nu. Its integration check belongs to the asset workflow.
    command $nu.current-exe [--no-config-file scripts/test-sdk-identity.nu]
    command $nu.current-exe [--no-config-file scripts/test-mesh-format.nu]
    command $nu.current-exe [--no-config-file scripts/make-audio.nu --check]
    command $nu.current-exe [--no-config-file scripts/test-performance.nu]
    print 'PASS: native Nu scripts parse; SDK, mesh and audio fixtures pass'
}
