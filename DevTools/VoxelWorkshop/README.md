# Voxel Workshop

A developer-only Unity project (Unity 6000.6.7f1) for making creatures and decorations for Voxel Aquarium out of
blocks of different shapes. It lives outside the Xcode project's App, Shared and Widget folders, so none of it is
ever part of the app build.

Open this folder in Unity Hub. The Workshop window opens on its own (or **Voxel Workshop ▸ Open Workshop**, ⇧⌘W).

- Scene view: click to use the tool, drag to keep painting or erasing, Alt-drag to orbit.
- Keys: B add, P paint, E erase, I pick · 1–8 shape · R turn · F upside down · M mirror · G glow · T tail.
- Shapes: cube, slab, slope, stair, pillar, ball, pyramid, coin (the same ones the app draws, App/Voxels.swift).
- **Save to App** writes JSON into the app's Workshop folder
  (`~/Library/Group Containers/4BD53JYD4T.com.piersonluscy.voxelaquarium/Workshop`). The running app notices within
  a couple of seconds and rebuilds the world with it. **Remove from App** deletes the file again.
- Creatures face +Z. Blocks marked Tail wag; keep them behind the body. Decorations sit on the floor at the
  position set in the window.

The app side is App/Workshop.swift.
