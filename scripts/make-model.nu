use model-recipes.nu [rabbit-scene robot-scene]
use blender.nu write-source

# Generate original sample geometry at an explicit path; never export implicitly.
def main [model: string, --output: path, --overwrite, --preview: path] {
    if $output == null { error make '--output is required' }
    let scene = match $model { rabbit => (rabbit-scene), robot => (robot-scene), _ => { error make 'choose rabbit or robot' } }
    write-source $scene $output --overwrite=$overwrite --preview $preview
}
