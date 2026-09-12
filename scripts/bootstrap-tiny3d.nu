use common.nu *
const REVISION = 'ec557373e986b5e041cc102a7ff787eb07921937'
def main [] {
    let source = tiny3d
    with-env {N64_INST: (sdk)} {
        if not ($source | path join .git | path exists) {
            command git [clone --no-checkout --filter=blob:none https://github.com/HailToDodongo/tiny3d.git $source]
            command git [-C $source sparse-checkout set src]
        }
        if (capture git [-C $source rev-parse HEAD]) != $REVISION {
            command git [-C $source fetch --depth 1 origin $REVISION]
            command git [-C $source -c filter.lfs.required=false -c filter.lfs.smudge= -c filter.lfs.process= checkout --detach $REVISION]
        }
        command make [-C $source $'-j(jobs)']
    }
}
