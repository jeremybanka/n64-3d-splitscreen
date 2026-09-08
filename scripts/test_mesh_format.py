"""Fast validation regressions; run without Blender or the N64 SDK."""
import unittest

from mesh_format import MeshError, packed_vertex_count, quantize_position, serialize_mesh, validate_mesh


class MeshValidationTests(unittest.TestCase):
    def setUp(self):
        self.vertices = [(0, 0, 0, 0), (256, 0, 0, 1), (0, 256, 0, 2)]
        self.faces = [(0, 1, 2, 0, 255)]
        self.colors = [0xffffffFF]

    def test_coordinate_convention_and_scale(self):
        self.assertEqual(quantize_position((1, -2, 3), 'head'), (256, 768, 512))
        for position in ((float('nan'), 0, 0), (128, 0, 0)):
            with self.assertRaisesRegex(MeshError, 'head'):
                quantize_position(position, 'head')

    def test_invalid_indices_material_tags_and_shades(self):
        for face, message in [((0, 1, 3, 0, 255), 'vertex index'),
                              ((0, 1, 2, 1, 255), 'material index'),
                              ((0, 1, 2, 0, 256), 'shade')]:
            with self.subTest(face=face), self.assertRaisesRegex(MeshError, message):
                validate_mesh(self.vertices, [face], self.colors)
        self.vertices[0] = (0, 0, 0, 4)
        with self.assertRaisesRegex(MeshError, 'animation_part'):
            validate_mesh(self.vertices, self.faces, self.colors)

    def test_degenerate_quantized_triangles(self):
        self.vertices[2] = (128, 0, 0, 0)
        with self.assertRaisesRegex(MeshError, 'degenerate after Q8'):
            validate_mesh(self.vertices, self.faces, self.colors)

    def test_world_motion_headroom(self):
        for vertex in ((30000, 0, 0, 0), (0, 32767, 0, 0), (0, -1, 0, 0)):
            with self.subTest(vertex=vertex), self.assertRaisesRegex(MeshError, 'rotation/movement|bob/hop'):
                validate_mesh([vertex, *self.vertices[1:]], self.faces, self.colors)

    def test_shadow_and_batch_padding_are_in_budget(self):
        self.assertEqual(validate_mesh(self.vertices, self.faces, self.colors), (20, 1))
        # Every face uses unique source vertices: sharing cannot hide overflow.
        vertices = self.vertices * 250
        faces = [(i * 3, i * 3 + 1, i * 3 + 2, 0, 255) for i in range(250)]
        self.assertGreater(packed_vertex_count(vertices, faces)[0], 768)
        with self.assertRaisesRegex(MeshError, '768 animated vertices'):
            validate_mesh(vertices, faces, self.colors)

    def test_index_capacity_counts_contact_shadow(self):
        with self.assertRaisesRegex(MeshError, '4096-index'):
            validate_mesh(self.vertices, self.faces * 1350, self.colors)

    def test_material_and_shade_splits_do_not_share_vertices(self):
        faces = self.faces + [(0, 1, 2, 1, 255), (0, 1, 2, 0, 200)]
        self.assertEqual(validate_mesh(self.vertices, faces, self.colors * 2), (26, 1))

    def test_serialization_is_deterministic_and_validates_first(self):
        result = serialize_mesh(self.vertices, self.faces, self.colors)
        self.assertIn('pub const colors = [_]u32{ 0xffffffff };', result)
        self.assertEqual(result, serialize_mesh(self.vertices, self.faces, self.colors))
        with self.assertRaisesRegex(MeshError, 'no mesh triangles'):
            serialize_mesh([], [], self.colors)


if __name__ == '__main__':
    unittest.main()
