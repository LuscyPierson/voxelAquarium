using System.Collections.Generic;
using UnityEngine;

namespace VoxelWorkshop
{
    /// <summary>
    /// The thing being made: its blocks and how it behaves in the app. One block is one Unity unit here;
    /// <see cref="voxelSize"/> sets how big a block is in the app. Edit it from the Voxel Workshop window.
    /// </summary>
    [ExecuteAlways]
    [RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
    public class WorkshopModel : MonoBehaviour
    {
        public string itemName = "New Creature";
        public ItemKind kind = ItemKind.Creature;
        public bool inOcean = true, inSwamp, inRainforest;
        [Tooltip("Size of one block in the app. Creatures are usually 0.05–0.09, scenery 0.05–0.1.")]
        public float voxelSize = 0.07f;

        [Header("Creature")]
        public Habitat habitat = Habitat.Water;
        [Range(0.2f, 3f)] public float speed = 1;
        [Range(0, 1)] public float depthMin = 0.2f;
        [Range(0, 1)] public float depthMax = 0.8f;
        public bool schooling;
        [Range(1, 12)] public int groupMin = 1;
        [Range(1, 12)] public int groupMax = 2;
        [Tooltip("How often it visits, next to the built-in creatures (most are 1–9).")]
        [Range(0.2f, 10f)] public float weight = 2;

        [Header("Decoration")]
        [Tooltip("Across the floor, as you look at the app: about −12 (left edge) to 12 (right edge).")]
        public float floorX;
        [Tooltip("Into the scene: about −1.5 (front) to 4 (back).")]
        public float floorZ = 1;
        [Range(-180, 180)] public float turnDegrees;

        public List<Block> blocks = new();

        Mesh mesh;

        void OnEnable() => Rebuild();

        void OnValidate()
        {
#if UNITY_EDITOR
            UnityEditor.EditorApplication.delayCall += () => { if (this != null) Rebuild(); };
#endif
        }

        public Block At(Vector3Int app) => blocks.Find(b => b.x == app.x && b.y == app.y && b.z == app.z);

        public void Rebuild()
        {
            mesh = VoxelMesher.Build(blocks, mesh);
            GetComponent<MeshFilter>().sharedMesh = mesh;
            var r = GetComponent<MeshRenderer>();
            if (r.sharedMaterial == null || r.sharedMaterial.shader.name != "VoxelWorkshop/VertexColor")
            {
                var shader = Shader.Find("VoxelWorkshop/VertexColor");
                if (shader != null) r.sharedMaterial = new Material(shader) { name = "Voxel Workshop" };
            }
        }

        /// <summary>Unity grid cell → the app's block coordinates (x runs the other way).</summary>
        public static Vector3Int ToApp(Vector3Int unity) => new(-unity.x, unity.y, unity.z);
        public static Vector3Int ToUnity(Vector3Int app) => new(-app.x, app.y, app.z);
    }
}
