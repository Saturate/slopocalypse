# 0009. Layer 20 is bodies, which decals skip

Status: accepted
Date: 2026-11-19
Issue or PR: #385, #386

## Context
Blood is drawn with decals: splatter on walls behind a hit and pools under the dead. A decal
paints everything inside its box, so a pool would turn the body lying in it red, and a mark on
a wall would paint whoever stands against it or walks through it. Until now nothing in the
game used render layers or cull masks.

## Decision
Render layer 20 (`RenderLayers.NO_DECALS` in `core/render_layers.gd`) holds people: every
`GeometryInstance3D` under a player, soldier or civilian is moved onto it and off layer 1
as it enters the tree, gear given later included, and ragdolls copy those layers from the
body. Decals use a cull mask without layer 20. The gore module does the moving, so this costs
nothing when gore is off. A body has to join its group (`players`, `enemies`, `civilians`)
before it enters the tree for its meshes to be caught; both spawners do.

## Alternatives
- Thin decal boxes only: a pool still reaches the body lying in it, and a soldier against a
  wall is inside a wall mark's box.
- Moving bodies onto the layer on first hit, or when a pool spreads: gear added later and
  bystanders walking through a pool were still painted.
- Pools as flat meshes instead of decals: no painting problem, but they float or sink on
  uneven voxel ground.

## Consequences
Anything that later sets a camera's or a light's cull mask has to keep layer 20 in, or people
vanish from that view or go unlit. A mesh moved off a body (dropped gear) keeps layer 20 and
so never takes blood. New decals that should spare people use the same mask.
