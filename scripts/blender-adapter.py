"""The sole Python exception: translate JSON to/from Blender's bpy API.

Nushell owns commands, recipes, tests, mesh validation and final asset writes.
This bridge only opens/saves Blender files, applies declarative scene data,
and extracts evaluated mesh/transform/material data. It runs inside Blender.
"""
import json
import sys

import bpy
from mathutils import Vector


def extract(request):
    bpy.ops.wm.open_mainfile(filepath=request['source'])
    collection = bpy.data.collections.get(request['collection'])
    result = {'collection': request['collection'], 'found': collection is not None,
              'available': list(bpy.data.collections.keys()), 'objects': []}
    if collection is None:
        return result
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in collection.all_objects:
        record = {'name': obj.name, 'type': obj.type, 'animation_part': obj.get('animation_part')}
        result['objects'].append(record)
        if obj.type != 'MESH':
            continue
        evaluated = obj.evaluated_get(depsgraph)
        matrix = evaluated.matrix_world.to_3x3()
        record['determinant'] = matrix.determinant()
        mesh = evaluated.to_mesh()
        try:
            record['positions'] = [list(evaluated.matrix_world @ v.co) for v in mesh.vertices]
            record['triangles'] = []
            mesh.calc_loop_triangles()
            normal_matrix = matrix.inverted_safe().transposed()
            for tri in mesh.loop_triangles:
                material = mesh.materials[tri.material_index] if tri.material_index < len(mesh.materials) else None
                record['triangles'].append({
                    'vertices': list(tri.vertices), 'normal': list((normal_matrix @ tri.normal).normalized()),
                    'material_index': tri.material_index,
                    'material': None if material is None else {
                        'name': material.name, 'palette_index': material.original.get('palette_index'),
                        'color': list(material.diffuse_color),
                    },
                })
        finally:
            evaluated.to_mesh_clear()
    return result


def create(request):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    collection = bpy.data.collections.new(request['scene']['collection'])
    scene.collection.children.link(collection)
    materials = []
    for data in request['scene']['materials']:
        material = bpy.data.materials.new(data['name'])
        material.diffuse_color = data['color']
        material.use_nodes = True
        shader = material.node_tree.nodes['Principled BSDF']
        shader.inputs['Base Color'].default_value = data['color']
        shader.inputs['Roughness'].default_value = data.get('roughness', .82)
        if data.get('palette_index') is not None:
            material['palette_index'] = data['palette_index']
        materials.append(material)
    for data in request['scene']['objects']:
        if data['shape'] == 'sphere':
            bpy.ops.mesh.primitive_uv_sphere_add(segments=data['segments'], ring_count=data['rings'], radius=1)
            obj = bpy.context.object
        elif data['shape'] == 'cube':
            bpy.ops.mesh.primitive_cube_add(size=2)
            obj = bpy.context.object
        else:
            mesh = bpy.data.meshes.new(data['name'])
            mesh.from_pydata(data['vertices'], [], data['faces'])
            mesh.update()
            obj = bpy.data.objects.new(data['name'], mesh)
            scene.collection.objects.link(obj)
        obj.name = data['name']
        obj.location = data['position']
        obj.scale = data['scale']
        obj.rotation_euler = data['rotation']
        for index in data['materials']:
            obj.data.materials.append(materials[index])
        for index, slot in enumerate(data.get('polygon_materials', [])):
            obj.data.polygons[index].material_index = slot
        if data.get('animation_part') is not None:
            obj['animation_part'] = data['animation_part']
        if data.get('export', True):
            for parent in list(obj.users_collection):
                parent.objects.unlink(obj)
            collection.objects.link(obj)
    studio = request['scene'].get('studio')
    if studio:
        bpy.ops.object.camera_add(location=studio['camera_position'])
        camera = bpy.context.object
        camera.rotation_euler = (Vector(studio['camera_target']) - camera.location).to_track_quat('-Z', 'Y').to_euler()
        camera.data.type = 'ORTHO'
        camera.data.ortho_scale = studio['camera_scale']
        scene.camera = camera
        bpy.ops.object.light_add(type='AREA', location=studio['light_position'])
        bpy.context.object.data.energy = studio['light_energy']
        bpy.context.object.data.shape = 'DISK'
        bpy.context.object.data.size = studio['light_size']
        scene.render.engine = 'CYCLES'
        scene.cycles.samples = studio['samples']
        scene.render.resolution_x, scene.render.resolution_y = studio['resolution']
        scene.render.resolution_percentage = 100
        scene.world = bpy.data.worlds.new('World')
        scene.world.color = studio['world_color']
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=request['output'])
    if request.get('preview'):
        scene.render.filepath = request['preview']
        bpy.ops.render.render(write_still=True)
    return {'saved': request['output']}


request_path, response_path = sys.argv[sys.argv.index('--') + 1:]
with open(request_path, encoding='utf-8') as stream:
    request = json.load(stream)
result = {'extract': extract, 'create': create}[request['action']](request)
with open(response_path, 'w', encoding='utf-8') as stream:
    json.dump(result, stream)
