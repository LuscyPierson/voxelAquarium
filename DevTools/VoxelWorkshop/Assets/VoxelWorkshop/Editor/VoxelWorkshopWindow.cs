using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace VoxelWorkshop.EditorTools
{
    /// <summary>
    /// The Voxel Workshop: build creatures and scenery for Voxel Aquarium out of blocks of different shapes,
    /// right in the Scene view, then save them straight into the app.
    /// </summary>
    public class VoxelWorkshopWindow : EditorWindow
    {
        enum Tool { Add, Paint, Erase, Pick }

        static readonly string[] ToolNames = { "Add (B)", "Paint (P)", "Erase (E)", "Pick (I)" };
        static readonly string[] ShapeNames = { "1 Cube", "2 Slab", "3 Slope", "4 Stair", "5 Pillar", "6 Ball", "7 Pyramid", "8 Coin" };

        /// <summary>Colours the app's own creatures and scenery use.</summary>
        static readonly int[] Palette =
        {
            0xFF7A1A, 0xFFA352, 0xFFD23A, 0xF2B33A, 0xE05A4A, 0xE84A7A, 0xF27BA8, 0xA55EEA,
            0x7A6EE0, 0x4A9AE0, 0x4FD1C5, 0x7AD8C0, 0x6AC46A, 0x8FCF9A, 0x2E5A4A, 0xC9D46A,
            0xF8F8F2, 0xCFF6FF, 0x8A7F70, 0x15151B, 0x8B5A2B, 0x6B4220, 0x5A4A32, 0xE8D3A2,
        };

        Tool tool;
        BlockShape shape;
        int turn;
        bool flip;
        bool mirror = true;
        bool tailPart;
        Color color = new Color32(0xFF, 0x7A, 0x1A, 0xFF);
        bool glow;
        string file;
        Vector2 scroll;
        WorkshopModel model;

        [MenuItem("Voxel Workshop/Open Workshop %#w")]
        public static void Open() => GetWindow<VoxelWorkshopWindow>("Voxel Workshop").Show();

        [MenuItem("Voxel Workshop/Show Workshop Folder")]
        static void Reveal()
        {
            Directory.CreateDirectory(WorkshopFiles.Folder);
            EditorUtility.RevealInFinder(WorkshopFiles.Folder + "/");
        }

        void OnEnable()
        {
            SceneView.duringSceneGui += OnScene;
            Undo.undoRedoPerformed += OnUndo;
        }

        void OnDisable()
        {
            SceneView.duringSceneGui -= OnScene;
            Undo.undoRedoPerformed -= OnUndo;
        }

        void OnUndo()
        {
            if (model != null) model.Rebuild();
            Repaint();
        }

        WorkshopModel Model()
        {
            if (model != null) return model;
            model = FindFirstObjectByType<WorkshopModel>();
            if (model == null)
            {
                model = new GameObject("Workshop Model").AddComponent<WorkshopModel>();
                Templates.Creature(model);
                EditorSceneManager.MarkSceneDirty(model.gameObject.scene);
            }
            return model;
        }

        // MARK: - Window

        void OnGUI()
        {
            var m = Model();
            scroll = EditorGUILayout.BeginScrollView(scroll);

            EditorGUILayout.LabelField(file == null ? "Not saved yet" : Path.GetFileName(file), EditorStyles.miniLabel);
            using (new EditorGUILayout.HorizontalScope())
            {
                if (GUILayout.Button("New Creature")) New(m, true);
                if (GUILayout.Button("New Decoration")) New(m, false);
            }
            using (new EditorGUILayout.HorizontalScope())
            {
                if (GUILayout.Button("Open…")) OpenFile(m);
                if (GUILayout.Button(new GUIContent("Save to App", "Saves into the app's Workshop folder; the app picks it up in a couple of seconds."))) Save(m, false);
                if (GUILayout.Button("Save As…")) Save(m, true);
            }
            using (new EditorGUILayout.HorizontalScope())
            {
                if (GUILayout.Button("Show Folder")) Reveal();
                using (new EditorGUI.DisabledScope(file == null || !File.Exists(file)))
                    if (GUILayout.Button("Remove from App") && EditorUtility.DisplayDialog("Remove from the app?",
                            $"Deletes {Path.GetFileName(file)} from the Workshop folder. The model stays here.", "Remove", "Cancel"))
                    {
                        File.Delete(file);
                        file = null;
                    }
            }

            Section("What it is");
            EditorGUI.BeginChangeCheck();
            var so = new SerializedObject(m);
            EditorGUILayout.PropertyField(so.FindProperty("itemName"), new GUIContent("Name"));
            EditorGUILayout.PropertyField(so.FindProperty("kind"));
            using (new EditorGUILayout.HorizontalScope())
            {
                EditorGUILayout.PrefixLabel("Worlds");
                Toggle(so, "inOcean", "Ocean");
                Toggle(so, "inSwamp", "Swamp");
                Toggle(so, "inRainforest", "Rainforest");
            }
            EditorGUILayout.PropertyField(so.FindProperty("voxelSize"), new GUIContent("Block Size in App"));
            if (m.kind == ItemKind.Creature)
            {
                EditorGUILayout.PropertyField(so.FindProperty("habitat"), new GUIContent("Moves", "Water swims; Air flies in the swamp and rainforest; Ground walks the floor."));
                EditorGUILayout.PropertyField(so.FindProperty("speed"));
                float lo = m.depthMin, hi = m.depthMax;
                EditorGUILayout.MinMaxSlider(new GUIContent("Height (low–high)"), ref lo, ref hi, 0, 1);
                so.FindProperty("depthMin").floatValue = lo;
                so.FindProperty("depthMax").floatValue = hi;
                EditorGUILayout.PropertyField(so.FindProperty("schooling"));
                EditorGUILayout.PropertyField(so.FindProperty("groupMin"), new GUIContent("Group Size Min"));
                EditorGUILayout.PropertyField(so.FindProperty("groupMax"), new GUIContent("Group Size Max"));
                EditorGUILayout.PropertyField(so.FindProperty("weight"), new GUIContent("How Often"));
            }
            else
            {
                EditorGUILayout.PropertyField(so.FindProperty("floorX"), new GUIContent("Floor Left–Right"));
                EditorGUILayout.PropertyField(so.FindProperty("floorZ"), new GUIContent("Floor Front–Back"));
                EditorGUILayout.PropertyField(so.FindProperty("turnDegrees"), new GUIContent("Turn"));
            }
            so.ApplyModifiedProperties();
            if (EditorGUI.EndChangeCheck()) m.Rebuild();

            Section("Tool");
            tool = (Tool)GUILayout.Toolbar((int)tool, ToolNames);
            shape = (BlockShape)GUILayout.SelectionGrid((int)shape, ShapeNames, 4);
            using (new EditorGUILayout.HorizontalScope())
            {
                if (GUILayout.Button($"Turn (R): {turn * 90}°")) turn = (turn + 1) % 4;
                flip = GUILayout.Toggle(flip, "Upside Down (F)", "Button");
            }
            using (new EditorGUILayout.HorizontalScope())
            {
                mirror = GUILayout.Toggle(mirror, new GUIContent("Mirror Left/Right (M)", "Builds both sides at once, across the centre line."), "Button");
                using (new EditorGUI.DisabledScope(m.kind != ItemKind.Creature))
                    tailPart = GUILayout.Toolbar(tailPart ? 1 : 0, new[] { "Body", "Tail (T)" }) == 1;
            }

            Section("Colour");
            using (new EditorGUILayout.HorizontalScope())
            {
                color = EditorGUILayout.ColorField(GUIContent.none, color, false, false, false, GUILayout.Width(60));
                glow = GUILayout.Toggle(glow, new GUIContent("Glows (G)", "Drawn at full brightness, unlit, like the anglerfish's lure."), "Button");
            }
            DrawPalette();

            Section("Model");
            EditorGUILayout.LabelField($"{m.blocks.Count} blocks");
            using (new EditorGUILayout.HorizontalScope())
            {
                if (GUILayout.Button("Frame in Scene")) Frame(m);
                if (GUILayout.Button("Clear") && EditorUtility.DisplayDialog("Clear the model?", "Removes every block. You can undo.", "Clear", "Cancel"))
                {
                    Undo.RecordObject(m, "Clear Blocks");
                    m.blocks.Clear();
                    m.Rebuild();
                }
            }

            EditorGUILayout.HelpBox(
                "In the Scene view: click to use the tool, drag to keep painting or erasing. Hold Alt (Option) and drag to orbit.\n" +
                "Creatures face +Z (the blue arrow). Mark the fin that wags as Tail; it should sit behind the body.\n" +
                "Ground is the grid at the bottom; blocks sit on it. Save to App and the aquarium rebuilds with it a moment later; " +
                "to see a creature right away, use Settings ▸ Developer ▸ spawn by name.",
                MessageType.None);
            EditorGUILayout.EndScrollView();
        }

        static void Section(string title)
        {
            EditorGUILayout.Space(6);
            EditorGUILayout.LabelField(title, EditorStyles.boldLabel);
        }

        static void Toggle(SerializedObject so, string prop, string label)
        {
            var p = so.FindProperty(prop);
            p.boolValue = GUILayout.Toggle(p.boolValue, label, "Button");
        }

        void DrawPalette()
        {
            const int perRow = 8;
            for (int row = 0; row < Palette.Length / perRow; row++)
            {
                var rect = GUILayoutUtility.GetRect(perRow * 26, 24);
                for (int i = 0; i < perRow; i++)
                {
                    int rgb = Palette[row * perRow + i];
                    var r = new Rect(rect.x + i * 26, rect.y + 2, 22, 20);
                    var c = FromRGB(rgb);
                    EditorGUI.DrawRect(r, c);
                    if (ToRGB(color) == rgb) EditorGUI.DrawRect(new Rect(r.x, r.yMax - 3, r.width, 3), Color.white);
                    if (Event.current.type == EventType.MouseDown && r.Contains(Event.current.mousePosition))
                    {
                        color = c;
                        Event.current.Use();
                        Repaint();
                    }
                }
            }
        }

        void New(WorkshopModel m, bool creature)
        {
            if (m.blocks.Count > 1 && !EditorUtility.DisplayDialog("Start something new?", "The blocks here will be replaced. Anything saved stays saved.", "New", "Cancel")) return;
            Undo.RecordObject(m, "New");
            if (creature) Templates.Creature(m); else Templates.Decoration(m);
            file = null;
            Frame(m);
        }

        void OpenFile(WorkshopModel m)
        {
            Directory.CreateDirectory(WorkshopFiles.Folder);
            var path = EditorUtility.OpenFilePanel("Open Workshop Item", WorkshopFiles.Folder, "json");
            if (string.IsNullOrEmpty(path)) return;
            Undo.RecordObject(m, "Open");
            WorkshopFiles.Open(m, path);
            file = path;
            Frame(m);
        }

        void Save(WorkshopModel m, bool ask)
        {
            if (m.blocks.Count == 0)
            {
                EditorUtility.DisplayDialog("Nothing to save", "Add some blocks first.", "OK");
                return;
            }
            var path = file;
            if (ask || path == null) path = Path.Combine(WorkshopFiles.Folder, WorkshopFiles.Slug(m.itemName) + ".json");
            if (ask)
            {
                Directory.CreateDirectory(WorkshopFiles.Folder);
                path = EditorUtility.SaveFilePanel("Save Workshop Item", WorkshopFiles.Folder, Path.GetFileName(path), "json");
                if (string.IsNullOrEmpty(path)) return;
            }
            try
            {
                WorkshopFiles.Save(m, path);
                file = path;
                ShowNotification(new GUIContent("Saved — the app will pick it up"));
            }
            catch (System.Exception e)
            {
                EditorUtility.DisplayDialog("Couldn't save", $"{e.Message}\n\nIf macOS asked whether Unity may access another app's data, allow it and try again.", "OK");
            }
        }

        static void Frame(WorkshopModel m)
        {
            var view = SceneView.lastActiveSceneView;
            if (view == null) return;
            var bounds = m.GetComponent<MeshRenderer>().bounds;
            if (bounds.size == Vector3.zero) bounds = new Bounds(m.transform.position, Vector3.one * 8);
            bounds.Expand(4);
            view.Frame(bounds, false);
        }

        // MARK: - Scene view

        struct Hit
        {
            public Vector3Int cell;
            public Vector3Int normal;
        }

        void OnScene(SceneView view)
        {
            if (model == null) model = FindFirstObjectByType<WorkshopModel>();
            if (model == null) return;
            var e = Event.current;
            var t = model.transform;
            Handles.matrix = t.localToWorldMatrix;
            DrawGrid();
            DrawFront();

            int id = GUIUtility.GetControlID(FocusType.Passive);
            if (e.type == EventType.Layout) HandleUtility.AddDefaultControl(id);

            if (e.type == EventType.KeyDown && !e.control && !e.command && Keys(e.keyCode))
            {
                e.Use();
                Repaint();
            }

            var ray = HandleUtility.GUIPointToWorldRay(e.mousePosition);
            var local = new Ray(t.InverseTransformPoint(ray.origin), t.InverseTransformDirection(ray.direction));
            if (Cast(local, out var hit))
            {
                var target = tool == Tool.Add ? hit.cell + hit.normal : hit.cell;
                Handles.color = tool == Tool.Erase ? new Color(1, 0.3f, 0.3f) : tool == Tool.Add ? color : Color.white;
                Handles.DrawWireCube(target, Vector3.one * 1.04f);
                if (mirror && target.x != 0)
                {
                    Handles.color = new Color(Handles.color.r, Handles.color.g, Handles.color.b, 0.35f);
                    Handles.DrawWireCube(new Vector3(-target.x, target.y, target.z), Vector3.one * 1.04f);
                }

                bool click = e.type == EventType.MouseDown && e.button == 0 && !e.alt;
                bool drag = e.type == EventType.MouseDrag && e.button == 0 && !e.alt && (tool == Tool.Paint || tool == Tool.Erase);
                if (click || drag)
                {
                    Apply(target);
                    e.Use();
                }
            }
            if (e.type == EventType.MouseMove) view.Repaint();
            Handles.matrix = Matrix4x4.identity;
        }

        bool Keys(KeyCode k)
        {
            switch (k)
            {
                case KeyCode.B: tool = Tool.Add; return true;
                case KeyCode.P: tool = Tool.Paint; return true;
                case KeyCode.E: tool = Tool.Erase; return true;
                case KeyCode.I: tool = Tool.Pick; return true;
                case KeyCode.R: turn = (turn + 1) % 4; return true;
                case KeyCode.F: flip = !flip; return true;
                case KeyCode.M: mirror = !mirror; return true;
                case KeyCode.G: glow = !glow; return true;
                case KeyCode.T: tailPart = !tailPart; return true;
            }
            if (k >= KeyCode.Alpha1 && k <= KeyCode.Alpha8)
            {
                shape = (BlockShape)(k - KeyCode.Alpha1);
                return true;
            }
            return false;
        }

        void Apply(Vector3Int unityCell)
        {
            var m = model;
            Undo.RecordObject(m, tool + " Block");
            var app = WorkshopModel.ToApp(unityCell);
            ApplyAt(m, app, false);
            if (mirror && app.x != 0) ApplyAt(m, new Vector3Int(-app.x, app.y, app.z), true);
            m.Rebuild();
            EditorUtility.SetDirty(m);
            Repaint();
        }

        void ApplyAt(WorkshopModel m, Vector3Int app, bool mirrored)
        {
            var existing = m.At(app);
            int t = (mirrored ? (4 - turn) % 4 : turn) | (flip ? 4 : 0);
            switch (tool)
            {
                case Tool.Add:
                    if (existing != null) return;
                    m.blocks.Add(new Block
                    {
                        x = app.x, y = app.y, z = app.z, rgb = ToRGB(color), glow = glow ? 160 : 0, shape = shape, turn = t,
                        tail = tailPart && m.kind == ItemKind.Creature,
                    });
                    break;
                case Tool.Paint:
                    if (existing == null) return;
                    existing.rgb = ToRGB(color);
                    existing.glow = glow ? 160 : 0;
                    break;
                case Tool.Erase:
                    if (existing != null) m.blocks.Remove(existing);
                    break;
                case Tool.Pick:
                    if (existing == null || mirrored) return;
                    color = FromRGB(existing.rgb);
                    glow = existing.glow >= 100;
                    shape = existing.shape;
                    turn = existing.turn & 3;
                    flip = (existing.turn & 4) != 0;
                    tailPart = existing.tail;
                    tool = Tool.Add;
                    break;
            }
        }

        /// <summary>Steps the ray through the grid (one block per unit) until it meets a block or the ground.</summary>
        bool Cast(Ray ray, out Hit hit)
        {
            hit = default;
            var occupied = new System.Collections.Generic.HashSet<Vector3Int>();
            foreach (var b in model.blocks) occupied.Add(WorkshopModel.ToUnity(new Vector3Int(b.x, b.y, b.z)));

            var o = ray.origin + Vector3.one * 0.5f;
            var d = ray.direction;
            var cell = Vector3Int.FloorToInt(o);
            var step = new Vector3Int(d.x > 0 ? 1 : -1, d.y > 0 ? 1 : -1, d.z > 0 ? 1 : -1);
            Vector3 tMax = default, tDelta = default;
            for (int a = 0; a < 3; a++)
            {
                if (Mathf.Abs(d[a]) < 1e-6f)
                {
                    tMax[a] = float.PositiveInfinity;
                    tDelta[a] = float.PositiveInfinity;
                    continue;
                }
                float next = step[a] > 0 ? cell[a] + 1 - o[a] : o[a] - cell[a];
                tMax[a] = next / Mathf.Abs(d[a]);
                tDelta[a] = 1 / Mathf.Abs(d[a]);
            }

            // The ground: the bottom of the y = 0 row of blocks.
            float groundT = d.y < 0 ? (-0.5f - ray.origin.y) / d.y : float.PositiveInfinity;
            var normal = Vector3Int.zero;
            float travelled = 0;
            for (int i = 0; i < 600 && travelled < 400; i++)
            {
                if (occupied.Contains(cell))
                {
                    hit = new Hit { cell = cell, normal = normal };
                    return true;
                }
                if (travelled > groundT) break;
                int axis = tMax.x < tMax.y ? (tMax.x < tMax.z ? 0 : 2) : (tMax.y < tMax.z ? 1 : 2);
                travelled = tMax[axis];
                cell[axis] += step[axis];
                tMax[axis] += tDelta[axis];
                normal = Vector3Int.zero;
                normal[axis] = -step[axis];
            }
            if (float.IsPositiveInfinity(groundT) || groundT < 0) return false;
            var p = ray.origin + d * groundT;
            // On the ground, the Add tool places right here (normal zero), the others have nothing to hit.
            hit = new Hit { cell = new Vector3Int(Mathf.RoundToInt(p.x), 0, Mathf.RoundToInt(p.z)), normal = Vector3Int.zero };
            if (tool != Tool.Add) return false;
            return true;
        }

        static void DrawGrid()
        {
            const int n = 16;
            Handles.color = new Color(1, 1, 1, 0.12f);
            for (int i = -n; i <= n + 1; i++)
            {
                Handles.DrawLine(new Vector3(i - 0.5f, -0.5f, -n - 0.5f), new Vector3(i - 0.5f, -0.5f, n + 0.5f));
                Handles.DrawLine(new Vector3(-n - 0.5f, -0.5f, i - 0.5f), new Vector3(n + 0.5f, -0.5f, i - 0.5f));
            }
            Handles.color = new Color(1, 0.85f, 0.3f, 0.35f);
            Handles.DrawLine(new Vector3(0, -0.5f, -n - 0.5f), new Vector3(0, -0.5f, n + 0.5f));
        }

        static void DrawFront()
        {
            Handles.color = new Color(0.3f, 0.6f, 1f, 0.8f);
            Handles.ArrowHandleCap(0, new Vector3(0, -0.5f, 17), Quaternion.LookRotation(Vector3.forward), 3, EventType.Repaint);
        }

        public static int ToRGB(Color c)
        {
            Color32 c32 = c;
            return c32.r << 16 | c32.g << 8 | c32.b;
        }

        public static Color FromRGB(int rgb) => new Color32((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb, 255);
    }
}
