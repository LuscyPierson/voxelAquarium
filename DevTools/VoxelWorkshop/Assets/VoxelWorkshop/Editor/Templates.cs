using UnityEngine;

namespace VoxelWorkshop.EditorTools
{
    /// <summary>Starting points for something new, so there's always a block to build on.</summary>
    public static class Templates
    {
        /// <summary>A plain little fish, facing +z, with a wagging tail fin behind it.</summary>
        public static void Creature(WorkshopModel m)
        {
            m.itemName = "New Creature";
            m.kind = ItemKind.Creature;
            m.inOcean = true;
            m.inSwamp = m.inRainforest = false;
            m.voxelSize = 0.07f;
            m.habitat = Habitat.Water;
            m.blocks.Clear();
            const int orange = 0xFF9A3A, belly = 0xFFD7A0, black = 0x15151B;
            for (int z = 0; z <= 8; z++)
            {
                float t = (z - 4) / 4.6f;
                float r = Mathf.Sqrt(Mathf.Max(0, 1 - t * t));
                int half = Mathf.RoundToInt(r * 3.2f), wide = Mathf.RoundToInt(r * 1.6f);
                for (int y = -half; y <= half; y++)
                for (int x = -wide; x <= wide; x++)
                    m.blocks.Add(new Block { x = x, y = y + 3, z = z, rgb = y < -half / 2 ? belly : orange });
            }
            foreach (var b in m.blocks)
                if (b.z == 7 && b.y == 4 && Mathf.Abs(b.x) == 1) b.rgb = black;
            for (int z = -3; z <= -1; z++)
            for (int y = z; y <= -z; y++)
                m.blocks.Add(new Block { x = 0, y = y + 3, z = z, rgb = orange, tail = true });
            m.Rebuild();
        }

        /// <summary>A small coral to start a decoration from.</summary>
        public static void Decoration(WorkshopModel m)
        {
            m.itemName = "New Decoration";
            m.kind = ItemKind.Decoration;
            m.inOcean = true;
            m.inSwamp = m.inRainforest = false;
            m.voxelSize = 0.06f;
            m.floorX = 0;
            m.floorZ = 1;
            m.turnDegrees = 0;
            m.blocks.Clear();
            for (int y = 0; y < 4; y++) m.blocks.Add(new Block { x = 0, y = y, z = 0, rgb = 0xF27BA8, shape = BlockShape.Pillar });
            m.blocks.Add(new Block { x = 0, y = 4, z = 0, rgb = 0xFF9FC4, shape = BlockShape.Ball });
            m.Rebuild();
        }
    }
}
