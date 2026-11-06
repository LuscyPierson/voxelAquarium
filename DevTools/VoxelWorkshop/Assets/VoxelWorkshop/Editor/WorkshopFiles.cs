using System;
using System.IO;
using System.Linq;
using UnityEngine;

namespace VoxelWorkshop.EditorTools
{
    /// <summary>
    /// Saves and opens Workshop items as the JSON the app reads. The app watches its Workshop folder and
    /// rebuilds the world a couple of seconds after anything there changes.
    /// </summary>
    public static class WorkshopFiles
    {
        public static readonly string Folder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Personal),
            "Library/Group Containers/4BD53JYD4T.com.piersonluscy.voxelaquarium/Workshop");

        public static string Slug(string name)
        {
            var s = new string((name ?? "").ToLowerInvariant().Select(c => char.IsLetterOrDigit(c) ? c : '-').ToArray()).Trim('-');
            while (s.Contains("--")) s = s.Replace("--", "-");
            return s.Length == 0 ? "untitled" : s;
        }

        public static void Save(WorkshopModel m, string path)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, JsonUtility.ToJson(ToJson(m), true));
        }

        public static void Open(WorkshopModel m, string path) => FromJson(m, JsonUtility.FromJson<WorkshopItemJson>(File.ReadAllText(path)));

        public static WorkshopItemJson ToJson(WorkshopModel m)
        {
            var j = new WorkshopItemJson
            {
                name = m.itemName,
                kind = m.kind == ItemKind.Creature ? "creature" : "decor",
                voxelSize = m.voxelSize,
                habitat = m.habitat.ToString().ToLowerInvariant(),
                speed = m.speed,
                depthMin = Mathf.Min(m.depthMin, m.depthMax),
                depthMax = Mathf.Max(m.depthMin, m.depthMax),
                schooling = m.schooling,
                groupMin = Mathf.Min(m.groupMin, m.groupMax),
                groupMax = Mathf.Max(m.groupMin, m.groupMax),
                weight = m.weight,
                // The app's x runs the other way from Unity's, and so does its turning.
                x = -m.floorX,
                z = m.floorZ,
                turn = -m.turnDegrees,
            };
            if (m.inOcean) j.worlds.Add("ocean");
            if (m.inSwamp) j.worlds.Add("swamp");
            if (m.inRainforest) j.worlds.Add("rainforest");

            bool creature = m.kind == ItemKind.Creature;
            var body = m.blocks.Where(b => !creature || !b.tail).ToList();
            // The app hangs the tail off the back of the body: tail z 0 is the row just behind the body.
            int back = body.Count > 0 ? body.Min(b => b.z) - 1 : 0;
            foreach (var b in m.blocks)
            {
                bool tail = creature && b.tail;
                var e = new VoxelEntryJson { x = b.x, y = b.y, z = tail ? b.z - back : b.z, rgb = b.rgb, glow = b.glow, shape = (int)b.shape, turn = b.turn };
                (tail ? j.tail : j.body).Add(e);
            }
            return j;
        }

        public static void FromJson(WorkshopModel m, WorkshopItemJson j)
        {
            m.itemName = j.name;
            m.kind = j.kind == "decor" ? ItemKind.Decoration : ItemKind.Creature;
            m.inOcean = j.worlds.Contains("ocean");
            m.inSwamp = j.worlds.Contains("swamp");
            m.inRainforest = j.worlds.Contains("rainforest");
            m.voxelSize = j.voxelSize > 0 ? j.voxelSize : 0.07f;
            m.habitat = j.habitat switch { "air" => Habitat.Air, "ground" => Habitat.Ground, _ => Habitat.Water };
            m.speed = j.speed > 0 ? j.speed : 1;
            m.depthMin = j.depthMin;
            m.depthMax = j.depthMax > 0 ? j.depthMax : 0.8f;
            m.schooling = j.schooling;
            m.groupMin = Mathf.Max(1, j.groupMin);
            m.groupMax = Mathf.Max(m.groupMin, j.groupMax);
            m.weight = j.weight > 0 ? (float)j.weight : 2;
            m.floorX = -j.x;
            m.floorZ = j.z;
            m.turnDegrees = -j.turn;

            m.blocks.Clear();
            int back = j.body.Count > 0 ? j.body.Min(e => e.z) - 1 : 0;
            foreach (var e in j.body) m.blocks.Add(Block(e, false, 0));
            foreach (var e in j.tail ?? new()) m.blocks.Add(Block(e, true, back));
            m.Rebuild();
        }

        static Block Block(VoxelEntryJson e, bool tail, int offset) => new()
        {
            x = e.x, y = e.y, z = e.z + offset, rgb = e.rgb, glow = e.glow, shape = (BlockShape)e.shape, turn = e.turn, tail = tail,
        };
    }
}
