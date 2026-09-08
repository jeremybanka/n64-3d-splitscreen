"""Export one explicit collection from an existing .blend without saving it.

blender --background --python-exit-code 1 --python scripts/export-mesh.py -- \
    --source assets/rabbit.blend --collection Character --output src/generated/rabbit.zig
"""
import argparse
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mesh_format import MeshError, integer, quantize_position, serialize_mesh, validate_mesh


def export_collection(collection):
    objects = sorted(collection.all_objects, key=lambda obj: obj.name)
    if not objects:
        raise MeshError(f"collection {collection.name!r} is empty")
    vertices, faces, palette = [], [], {}
    light = Vector((-.35, -.6, .8)).normalized()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        if obj.type != 'MESH':
            raise MeshError(f"{obj.name}: only mesh objects belong in the export collection (found {obj.type})")
        part = integer(obj.get('animation_part'), 0, 3, f"{obj.name} animation_part")
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        try:
            if not mesh.vertices or not mesh.polygons:
                raise MeshError(f"{obj.name}: mesh has no faces")
            determinant = evaluated.matrix_world.to_3x3().determinant()
            if not math.isfinite(determinant) or abs(determinant) < 1e-10:
                raise MeshError(f"{obj.name}: transform has zero/non-finite scale")
            base = len(vertices)
            for vertex in mesh.vertices:
                position = evaluated.matrix_world @ vertex.co
                vertices.append((*quantize_position(position, f"{obj.name} vertex {vertex.index}"), part))
            mesh.calc_loop_triangles()
            normal_matrix = evaluated.matrix_world.to_3x3().inverted().transposed()
            for tri in mesh.loop_triangles:
                if tri.material_index >= len(mesh.materials) or mesh.materials[tri.material_index] is None:
                    raise MeshError(f"{obj.name} triangle {tri.index}: missing material in slot {tri.material_index}")
                material = mesh.materials[tri.material_index]
                # Evaluation can cache custom properties separately from the
                # authoring datablock; metadata belongs to that original source.
                index = integer(material.original.get('palette_index'), 0, 254, f"{material.name} palette_index")
                channels = tuple(material.diffuse_color)
                if not all(math.isfinite(c) and 0 <= c <= 1 for c in channels):
                    raise MeshError(f"{material.name}: viewport diffuse color channels must be finite and in 0..1")
                if channels[3] != 1:
                    raise MeshError(f"{material.name}: only opaque materials are supported; set viewport alpha to 1")
                color = sum(round(c * 255) << shift for c, shift in zip(channels, (24, 16, 8, 0)))
                if index in palette and palette[index] != color:
                    raise MeshError(f"{material.name}: palette_index {index} is shared by different colors; assign a unique index")
                palette[index] = color
                normal = (normal_matrix @ tri.normal).normalized()
                shade = round(255 * (.64 + .36 * max(0, normal.dot(light))))
                ids = tuple(base + i for i in tri.vertices)
                if determinant < 0:
                    ids = (ids[0], ids[2], ids[1])
                faces.append((*ids, index, shade))
        finally:
            evaluated.to_mesh_clear()
    if sorted(palette) != list(range(len(palette))):
        raise MeshError(f"palette_index values must be contiguous from zero; found {sorted(palette)}")
    colors = [palette[i] for i in range(len(palette))]
    return vertices, faces, colors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--collection', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    source, output = args.source.resolve(), args.output.resolve()
    if not source.is_file() or source.suffix != '.blend':
        raise MeshError(f"source must be an existing .blend file: {source}")
    if output.suffix != '.zig' or output == source:
        raise MeshError("output must be a separate .zig file; the source is never overwritten")
    bpy.ops.wm.open_mainfile(filepath=str(source))
    collection = bpy.data.collections.get(args.collection)
    if collection is None:
        raise MeshError(f"collection {args.collection!r} not found; available: {', '.join(bpy.data.collections.keys())}")
    vertices, faces, colors = export_collection(collection)
    count, batches = validate_mesh(vertices, faces, colors)
    result = serialize_mesh(vertices, faces, colors)
    output.parent.mkdir(parents=True, exist_ok=True)
    # Validation completes before touching a previously successful export.
    temporary = output.with_suffix('.zig.tmp')
    temporary.write_text(result)
    temporary.replace(output)
    print(f"Exported {len(vertices)} vertices / {len(faces)} triangles; {count}/768 packed animated vertices, {batches}/64 batches -> {output}")


if __name__ == '__main__':
    try:
        main()
    except MeshError as error:
        print(f"Mesh export failed: {error}", file=sys.stderr)
        raise SystemExit(1)
