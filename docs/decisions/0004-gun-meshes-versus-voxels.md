# 0004. Guns are hand-built low-poly meshes, everything else is voxels

Status: open
Date: 2026-11-12
Issue or PR: (none yet)

## Context
Guns and their parts are built as low-poly meshes in code (`GunPartMeshes`, `LowPoly`), with a
triangle budget per build. Everything else (terrain, buildings, cars, props, gear) is voxel
models from the voxel kit, with materials, the asset library and the breaking rules. New guns
(the launcher) were added to the mesh code by following the existing pattern, not by choice.

## Decision
Not made. Until it is, new gun parts follow `GunPartMeshes`.

## Alternatives
- Keep low-poly guns: finer detail up close (rails, optics), which voxels at a sensible size
  can't show.
- Voxel guns from the voxel kit: one art language, the asset library, materials (guns could
  take damage), but a held gun at 2-4 cm voxels needs many cells and may read worse up close.
- Hybrid: voxel bodies, mesh details (optics glass, rails).

## Consequences
Two art pipelines to maintain. Settle this before the guns work (#193) adds many more parts.
