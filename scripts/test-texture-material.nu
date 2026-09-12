use std/assert
use make-texture.nu convert
use texture-workload.nu check-texture-workload
const root = path self ..

def main [] {
    assert equal (convert (open --raw ($root | path join assets/textures/ground.ppm))) (open --raw ($root | path join src/generated/ground_texture.h))
    let red = ('P3 16 16 255 ' + (1..256 | each { '255 0 0' } | str join ' '))
    assert equal ((convert $red) | parse --regex '0xf801' | length) 256
    for invalid in ['P3 32 16 255' 'P3 16 16 255 0 0 0' ('P3 16 16 255 ' + (1..256 | each { '256 0 0' } | str join ' ')) 'P3 16 16 255 NaN'] {
        assert error { convert $invalid }
    }
    let row = 'PERF views=4 phase=0 fps=60 cpu_us=1 submit_us=1 triangles=42'
    assert str contains (check-texture-workload ($row + ' textured=1 content=robot-courtyard') on robot-courtyard) 'textured=1'
    assert str contains (check-texture-workload $row legacy) 'Historical'
    for capture in [$row ($row + ' textured=0 content=meadow') ($row + " textured=1 content=meadow\n" + $row + ' textured=0 content=meadow')] {
        assert error { check-texture-workload $capture on }
    }
    assert error { check-texture-workload ($row + ' textured=0 content=meadow') legacy }
    print 'Texture: source identity, RGBA5551 packing, invalid pixels and workload isolation pass'
}
