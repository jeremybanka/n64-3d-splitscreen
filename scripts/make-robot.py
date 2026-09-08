"""Generate the alternate character source; never export or overwrite implicitly."""
import argparse
from pathlib import Path
import sys

import bpy

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--overwrite', action='store_true')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
if args.output.suffix != '.blend':
    parser.error('--output must be a .blend file')
if args.output.exists() and not args.overwrite:
    parser.error(f'{args.output} exists; choose a new path or explicitly pass --overwrite')
args.output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
collection = bpy.data.collections.new('Character')
bpy.context.scene.collection.children.link(collection)
materials = []
for index, (name, rgb) in enumerate([
        ('Steel shell', (195, 216, 226)), ('Player chest', (239, 137, 101)),
        ('Dark joints', (42, 59, 79)), ('Cyan display', (94, 218, 228))]):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*[c / 255 for c in rgb], 1)
    material['palette_index'] = index
    materials.append(material)


def box(name, position, size, material, part=0):
    bpy.ops.mesh.primitive_cube_add(size=2, location=position)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    obj.data.materials.append(materials[material])
    obj['animation_part'] = part
    for parent in list(obj.users_collection):
        parent.objects.unlink(obj)
    collection.objects.link(obj)


box('Chest', (0, 0, .95), (.36, .24, .40), 1)
box('Neck', (0, 0, 1.42), (.12, .12, .08), 2)
box('Head', (0, 0, 1.74), (.37, .28, .26), 0)
box('Display', (0, -.286, 1.76), (.26, .018, .11), 3)
box('Antenna', (0, 0, 2.12), (.035, .035, .12), 2, 3)
box('Antenna light', (0, 0, 2.28), (.075, .075, .06), 3, 3)
for side in (-1, 1):
    box(f'Arm {side}', (side * .48, 0, .98), (.10, .14, .32), 0, 1 if side < 0 else 2)
    box(f'Leg {side}', (side * .20, 0, .36), (.11, .12, .20), 2, 2 if side < 0 else 1)
    box(f'Foot {side}', (side * .20, -.08, .10), (.15, .22, .10), 0, 2 if side < 0 else 1)
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(args.output.resolve()))
print(f'Generated editable source at {args.output}; run export-mesh.py to update the ROM mesh')
