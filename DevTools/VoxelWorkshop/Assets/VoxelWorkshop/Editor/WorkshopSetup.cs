using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace VoxelWorkshop.EditorTools
{
    /// <summary>Opens the Workshop scene and window when the project opens, and holds batch-mode checks.</summary>
    [InitializeOnLoad]
    public static class WorkshopSetup
    {
        const string ScenePath = "Assets/VoxelWorkshop/Workshop.unity";

        static WorkshopSetup()
        {
            if (Application.isBatchMode) return;
            EditorApplication.delayCall += () =>
            {
                if (string.IsNullOrEmpty(EditorSceneManager.GetActiveScene().path) && File.Exists(ScenePath))
                    EditorSceneManager.OpenScene(ScenePath);
                if (!SessionState.GetBool("VoxelWorkshop.opened", false))
                {
                    SessionState.SetBool("VoxelWorkshop.opened", true);
                    VoxelWorkshopWindow.Open();
                }
            };
        }

        [MenuItem("Voxel Workshop/Rebuild Workshop Scene")]
        public static void CreateScene()
        {
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            var model = new GameObject("Workshop Model").AddComponent<WorkshopModel>();
            Templates.Creature(model);
            RenderSettings.ambientLight = new Color(0.7f, 0.8f, 0.85f);
            var cam = new GameObject("Camera").AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color32(0x62, 0xC2, 0xDE, 0xFF);
            cam.transform.position = new Vector3(-14, 9, -12);
            cam.transform.LookAt(new Vector3(0, 3, 3));
            EditorSceneManager.SaveScene(scene, ScenePath);
        }

        /// <summary>
        /// Batch check: builds every shape plus the starter fish, renders a picture of it, and saves its JSON.
        /// Unity -batchmode -projectPath . -executeMethod VoxelWorkshop.EditorTools.WorkshopSetup.Check -out &lt;folder&gt;
        /// </summary>
        public static void Check()
        {
            var args = System.Environment.GetCommandLineArgs();
            string dir = args[System.Array.IndexOf(args, "-out") + 1];
            var model = new GameObject("Check").AddComponent<WorkshopModel>();
            Templates.Creature(model);
            int i = 0;
            foreach (BlockShape s in System.Enum.GetValues(typeof(BlockShape)))
            {
                model.blocks.Add(new Block { x = -8 + i * 2, y = 0, z = 12, rgb = 0x4A9AE0 + i * 0x101000, shape = s, turn = 1 });
                model.blocks.Add(new Block { x = -8 + i * 2, y = 0, z = 15, rgb = 0xE05A4A + i * 0x000F10, shape = s, turn = 4 });
                i++;
            }
            model.blocks.Add(new Block { x = 3, y = 3, z = 4, rgb = 0xFFF2A8, glow = 160, shape = BlockShape.Ball });
            model.Rebuild();
            WorkshopFiles.Save(model, Path.Combine(dir, "check.json"));

            var cam = new GameObject("Cam").AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color32(0x62, 0xC2, 0xDE, 0xFF);
            cam.transform.position = new Vector3(-12, 12, -10);
            cam.transform.LookAt(new Vector3(0, 1, 6));
            var rt = new RenderTexture(1200, 800, 24);
            cam.targetTexture = rt;
            cam.Render();
            RenderTexture.active = rt;
            var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
            File.WriteAllBytes(Path.Combine(dir, "check.png"), tex.EncodeToPNG());
            Debug.Log("Workshop check written to " + dir);
        }
    }
}
