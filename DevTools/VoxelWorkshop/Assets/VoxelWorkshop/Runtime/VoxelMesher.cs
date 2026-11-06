using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace VoxelWorkshop
{
    /// <summary>
    /// Turns blocks into a mesh that looks like the app's: cubes join up (hidden faces dropped), shaped
    /// blocks stand alone. Shapes are built exactly as BlockShapes in App/Voxels.swift does, in the app's
    /// coordinates, then x is mirrored into Unity's.
    /// </summary>
    public static class VoxelMesher
    {
        struct Face
        {
            public Vector3[] points;
            public Vector3 normal;
        }

        static readonly Dictionary<int, List<Face>> Cache = new();

        public static Mesh Build(IEnumerable<Block> blocks, Mesh mesh = null)
        {
            mesh ??= new Mesh { name = "Voxel Workshop Model" };
            mesh.Clear();
            mesh.indexFormat = IndexFormat.UInt32;

            var cubes = new HashSet<Vector3Int>();
            var list = new List<Block>(blocks);
            foreach (var b in list)
                if (b.shape == BlockShape.Cube) cubes.Add(new Vector3Int(b.x, b.y, b.z));

            var verts = new List<Vector3>();
            var normals = new List<Vector3>();
            var colors = new List<Color32>();
            var tris = new List<int>();

            foreach (var b in list)
            {
                var centre = new Vector3(b.x, b.y, b.z);
                var color = ColorOf(b);
                IEnumerable<Face> faces = b.shape == BlockShape.Cube ? CubeFaces(b, cubes) : Faces(b.shape, b.turn);
                foreach (var f in faces)
                {
                    int start = verts.Count;
                    foreach (var p in f.points)
                    {
                        verts.Add(ToUnity(centre + p));
                        normals.Add(ToUnity(f.normal));
                        colors.Add(color);
                    }
                    for (int k = 1; k < f.points.Length - 1; k++)
                    {
                        tris.Add(start);
                        tris.Add(start + k);
                        tris.Add(start + k + 1);
                    }
                }
            }

            mesh.SetVertices(verts);
            mesh.SetNormals(normals);
            mesh.SetColors(colors);
            mesh.SetTriangles(tris, 0);
            mesh.RecalculateBounds();
            return mesh;
        }

        /// <summary>The app's x runs the other way from Unity's, as seen from the front.</summary>
        public static Vector3 ToUnity(Vector3 app) => new(-app.x, app.y, app.z);

        /// <summary>Block colour with the app's slight per-block brightness jitter; alpha 0 marks glowing blocks.</summary>
        static Color32 ColorOf(Block b)
        {
            float shade = 1 + (Hash(b.x, b.y, b.z) - 0.5f) * 2 * 0.06f;
            byte C(int v) => (byte)Mathf.Clamp(Mathf.RoundToInt(v * shade), 0, 255);
            return new Color32(C((b.rgb >> 16) & 0xFF), C((b.rgb >> 8) & 0xFF), C(b.rgb & 0xFF), (byte)(b.glow >= 100 ? 0 : 255));
        }

        static float Hash(int x, int y, int z)
        {
            unchecked
            {
                uint h = (uint)(x * 374761393 + y * 668265263 + z * 2147483647);
                h = (h ^ (h >> 13)) * 1274126177;
                h ^= h >> 16;
                return (h & 0xFFFFFF) / (float)0x1000000;
            }
        }

        static IEnumerable<Face> CubeFaces(Block b, HashSet<Vector3Int> cubes)
        {
            var p = new Vector3Int(b.x, b.y, b.z);
            foreach (var face in Faces(BlockShape.Cube, 0))
            {
                var n = Vector3Int.RoundToInt(face.normal);
                if (!cubes.Contains(p + n)) yield return face;
            }
        }

        static List<Face> Faces(BlockShape shape, int turn)
        {
            int key = (int)shape * 8 + (turn & 7);
            if (Cache.TryGetValue(key, out var cached)) return cached;
            float angle = (turn & 3) * Mathf.PI / 2;
            bool flip = (turn & 4) != 0;
            float cs = Mathf.Cos(angle), sn = Mathf.Sin(angle);
            Vector3 Move(Vector3 v)
            {
                var r = new Vector3(v.x * cs + v.z * sn, v.y, -v.x * sn + v.z * cs);
                return flip ? new Vector3(r.x, -r.y, r.z) : r;
            }

            var result = new List<Face>();
            foreach (var solid in Solids(shape))
            {
                var mid = Vector3.zero;
                int count = 0;
                foreach (var poly in solid)
                    foreach (var q in poly) { mid += q; count++; }
                mid = Move(mid / count);
                foreach (var poly in solid)
                {
                    var pts = poly.ConvertAll(Move).ToArray();
                    // Same rule as the app, in its right-handed space: the normal is the cross product of two edges.
                    var n = RightCross(pts[1] - pts[0], pts[2] - pts[0]).normalized;
                    var c = Vector3.zero;
                    foreach (var q in pts) c += q;
                    c /= pts.Length;
                    if (Vector3.Dot(n, c - mid) < 0)
                    {
                        System.Array.Reverse(pts);
                        n = -n;
                    }
                    result.Add(new Face { points = pts, normal = n });
                }
            }
            Cache[key] = result;
            return result;
        }

        static Vector3 RightCross(Vector3 a, Vector3 b) =>
            new(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

        static List<List<List<Vector3>>> Solids(BlockShape shape)
        {
            const float h = 0.5f;
            switch (shape)
            {
                case BlockShape.Slab: return new() { Box(new(-h, -h, -h), new(h, 0, h)) };
                case BlockShape.Coin: return new() { Prism(10, 0.42f, -h, -0.32f) };
                case BlockShape.Pillar: return new() { Prism(8, 0.26f, -h, h) };
                case BlockShape.Stair: return new() { Box(new(-h, -h, -h), new(h, 0, h)), Box(new(-h, 0, 0), new(h, h, h)) };
                case BlockShape.Slope:
                {
                    // Rises from the front (−z) to the back (+z).
                    Vector3 a = new(-h, -h, -h), b = new(h, -h, -h), c = new(h, -h, h), d = new(-h, -h, h), e = new(-h, h, h), f = new(h, h, h);
                    return new() { new() { new() { a, b, c, d }, new() { d, c, f, e }, new() { a, b, f, e }, new() { a, d, e }, new() { b, c, f } } };
                }
                case BlockShape.Pyramid:
                {
                    Vector3 a = new(-h, -h, -h), b = new(h, -h, -h), c = new(h, -h, h), d = new(-h, -h, h), top = new(0, h, 0);
                    return new() { new() { new() { a, b, c, d }, new() { a, b, top }, new() { b, c, top }, new() { c, d, top }, new() { d, a, top } } };
                }
                case BlockShape.Ball:
                {
                    var polys = new List<List<Vector3>>();
                    const int rings = 5, segs = 8;
                    Vector3 P(int i, int j)
                    {
                        float t = (float)i / rings * Mathf.PI, u = (float)j / segs * 2 * Mathf.PI;
                        return new Vector3(Mathf.Sin(t) * Mathf.Cos(u), Mathf.Cos(t), Mathf.Sin(t) * Mathf.Sin(u)) * 0.5f;
                    }
                    for (int i = 0; i < rings; i++)
                    for (int j = 0; j < segs; j++)
                    {
                        if (i == 0) polys.Add(new() { P(0, 0), P(1, j), P(1, j + 1) });
                        else if (i == rings - 1) polys.Add(new() { P(i, j), P(i, j + 1), P(rings, 0) });
                        else polys.Add(new() { P(i, j), P(i, j + 1), P(i + 1, j + 1), P(i + 1, j) });
                    }
                    return new() { polys };
                }
                default: return new() { Box(new(-h, -h, -h), new(h, h, h)) };
            }
        }

        static List<List<Vector3>> Box(Vector3 lo, Vector3 hi)
        {
            Vector3 V(bool x, bool y, bool z) => new(x ? hi.x : lo.x, y ? hi.y : lo.y, z ? hi.z : lo.z);
            return new()
            {
                new() { V(false, false, false), V(true, false, false), V(true, false, true), V(false, false, true) },
                new() { V(false, true, false), V(true, true, false), V(true, true, true), V(false, true, true) },
                new() { V(false, false, false), V(true, false, false), V(true, true, false), V(false, true, false) },
                new() { V(false, false, true), V(true, false, true), V(true, true, true), V(false, true, true) },
                new() { V(false, false, false), V(false, false, true), V(false, true, true), V(false, true, false) },
                new() { V(true, false, false), V(true, false, true), V(true, true, true), V(true, true, false) },
            };
        }

        static List<List<Vector3>> Prism(int sides, float radius, float y0, float y1)
        {
            var ring = new List<Vector2>();
            for (int i = 0; i < sides; i++)
            {
                float a = (float)i / sides * 2 * Mathf.PI;
                ring.Add(new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * radius);
            }
            var polys = new List<List<Vector3>>
            {
                ring.ConvertAll(r => new Vector3(r.x, y0, r.y)),
                ring.ConvertAll(r => new Vector3(r.x, y1, r.y)),
            };
            for (int i = 0; i < sides; i++)
            {
                Vector2 a = ring[i], b = ring[(i + 1) % sides];
                polys.Add(new() { new(a.x, y0, a.y), new(b.x, y0, b.y), new(b.x, y1, b.y), new(a.x, y1, a.y) });
            }
            return polys;
        }
    }
}
