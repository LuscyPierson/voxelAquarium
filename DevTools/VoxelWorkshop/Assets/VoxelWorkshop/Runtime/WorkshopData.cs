using System;
using System.Collections.Generic;

namespace VoxelWorkshop
{
    /// <summary>The block shapes the app can draw. Same order as BlockShape in App/Voxels.swift.</summary>
    public enum BlockShape { Cube, Slab, Slope, Stair, Pillar, Ball, Pyramid, Coin }

    public enum ItemKind { Creature, Decoration }

    public enum Habitat { Water, Air, Ground }

    /// <summary>
    /// One block as the Workshop keeps it: in the app's own coordinates (x is mirrored from Unity's),
    /// with tail blocks marked and stored in the same space as the body.
    /// </summary>
    [Serializable]
    public class Block
    {
        public int x, y, z;
        public int rgb;
        public int glow;
        public BlockShape shape;
        /// <summary>Quarter turns about y (0–3), plus 4 when flipped upside down.</summary>
        public int turn;
        public bool tail;

        public Block Copy() => (Block)MemberwiseClone();
    }

    // The JSON the app reads (WorkshopItem in App/Workshop.swift).

    [Serializable]
    public class VoxelEntryJson
    {
        public int x, y, z;
        public int rgb;
        public int glow;
        public int shape;
        public int turn;
    }

    [Serializable]
    public class WorkshopItemJson
    {
        public string name;
        public string kind;
        public List<string> worlds = new();
        public float voxelSize;
        public List<VoxelEntryJson> body = new();
        public List<VoxelEntryJson> tail = new();

        public string habitat;
        public float speed;
        public float depthMin;
        public float depthMax;
        public bool schooling;
        public int groupMin;
        public int groupMax;
        public double weight;

        public float x;
        public float z;
        public float turn;
    }
}
