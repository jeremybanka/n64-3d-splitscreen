"""Optional integration suite, run by `make test-models` with Blender installed."""
import hashlib
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('export_mesh', ROOT / 'scripts/export-mesh.py')
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class BlenderExportTests(unittest.TestCase):
    def setUp(self):
        bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'assets/robot.blend'))
        self.collection = bpy.data.collections['Character']

    def run_export(self, source, output):
        previous = sys.argv
        try:
            sys.argv = ['blender', '--', '--source', str(source), '--collection', 'Character', '--output', str(output)]
            exporter.main()
        finally:
            sys.argv = previous

    def test_sources_are_preserved_and_checked_in_exports_are_reproducible(self):
        for name in ('rabbit', 'robot'):
            source = ROOT / f'assets/{name}.blend'
            before = hashlib.sha256(source.read_bytes()).digest()
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / 'mesh.zig'
                self.run_export(source, output)
                first = output.read_bytes()
                self.run_export(source, output)
                self.assertEqual(first, output.read_bytes())
                self.assertEqual(first, (ROOT / f'src/generated/{name}.zig').read_bytes())
            self.assertEqual(before, hashlib.sha256(source.read_bytes()).digest())

    def test_per_face_material_slots(self):
        obj = self.collection.objects['Chest']
        extra = self.collection.objects['Head'].data.materials[0]
        obj.data.materials.append(extra)
        obj.data.polygons[0].material_index = 1
        bpy.context.view_layer.update()
        _, faces, _ = exporter.export_collection(self.collection)
        # The first object alphabetically is an antenna; inspect the distinct
        # source vertices belonging to the chest rather than export order.
        obj_names = sorted(self.collection.all_objects, key=lambda item: item.name)
        base = sum(len(item.data.vertices) for item in obj_names[:obj_names.index(obj)])
        chest_faces = [face for face in faces if base <= face[0] < base + len(obj.data.vertices)]
        self.assertEqual(sorted(face[3] for face in chest_faces).count(0), 2)
        self.assertEqual(sorted(face[3] for face in chest_faces).count(1), 10)

    def test_negative_scale_preserves_outward_winding(self):
        # An isolated cube has a known outward normal: triangle normal must
        # point away from its center even after reflection.
        obj = self.collection.objects['Chest']
        for other in list(self.collection.objects):
            if other != obj:
                self.collection.objects.unlink(other)
        obj.data.materials[0]['palette_index'] = 0
        obj.scale.x *= -1
        bpy.context.view_layer.update()
        vertices, faces, colors = exporter.export_collection(self.collection)
        exporter.validate_mesh(vertices, faces, colors)
        center = Vector((0, round(.95 * 256), 0))
        for face in faces:
            a, b, c = [Vector(vertices[index][:3]) for index in face[:3]]
            self.assertGreater((b - a).cross(c - a).dot((a + b + c) / 3 - center), 0)

    def test_palette_errors_and_zero_scale_are_actionable(self):
        material = self.collection.objects['Chest'].data.materials[0]
        for value, message in ((None, 'palette_index'), (0, 'shared by different colors'), (8, 'contiguous')):
            with self.subTest(value=value):
                if value is None:
                    del material['palette_index']
                else:
                    material['palette_index'] = value
                with self.assertRaisesRegex(exporter.MeshError, message):
                    exporter.export_collection(self.collection)
                material['palette_index'] = 1
        self.collection.objects['Chest'].scale.x = 0
        bpy.context.view_layer.update()
        with self.assertRaisesRegex(exporter.MeshError, 'zero/non-finite scale'):
            exporter.export_collection(self.collection)

    def test_export_failure_preserves_previous_output(self):
        del self.collection.objects['Chest']['animation_part']
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / 'invalid.blend', Path(directory) / 'mesh.zig'
            bpy.ops.wm.save_as_mainfile(filepath=str(source))
            output.write_text('previous valid output')
            with self.assertRaisesRegex(exporter.MeshError, 'Chest animation_part'):
                self.run_export(source, output)
            self.assertEqual(output.read_text(), 'previous valid output')


suite = unittest.defaultTestLoader.loadTestsFromTestCase(BlenderExportTests)
if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():
    raise RuntimeError('Blender exporter integration tests failed')
