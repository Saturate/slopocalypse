# 0007. Maps are recipes of generated and tailored sites, stitched by roads

Status: accepted; generation order superseded by 0010
Date: 2026-11-17
Issue or PR: #331

## Context
The world is one hand-tuned strip (384 m by 3 km) along a single road, with ponds, towers
and lamps placed by distance down that road. The maintainer wants different maps (a grass
map, a random biome map), more road kinds and a city on every map, with both generated and
hand-made parts. One strip with one road can't hold a city or a road network, and placing
everything by "metres down the road" won't survive a second road.

## Decision
- A map is a **recipe** (data): size, biome mix, road kinds allowed, the sites it must have
  (tailored ones by name, generated ones by kind and count) and a seed. A grass map and a
  random map are two recipes. The server sends the recipe name and seed; every machine
  builds the same world from them.
- Maps are **open regions** (start 2 x 2 km), not strips.
- The generator works in order: place **sites** (tailored and generated: city, town,
  outpost, farm, start) as nodes, join them with a **road graph** of typed roads
  (highway, two-lane, city street, dirt track, bridge), then shape the **terrain** to it
  (pads under sites, roads cut in, water), then fill the rest with **biomes** and scatter.
- A **site** is a footprint, the pieces in it (voxel generators with parameters, props,
  spawns) and **connectors** (where roads join it, which kind, which way). Tailored sites
  are made in the Godot editor or written as data, and saved to the same data format;
  generated sites (city blocks, outposts) are produced in that format by code.
- The **city** is a generated site kind (street grid, blocks, multi-storey buildings,
  #220) that can take tailored blocks inside it. Every recipe has one unless it says not.
- Things now placed by road distance (lamps, towers, ponds) move to belong to sites or road
  kinds (lamps line city streets and highways, towers stand at farms and outposts).

## Alternatives
- Keep the strip, wider: keeps the journey feel and today's code, but a city and a road
  network still don't fit, and a second map shape would come later anyway.
- Fully generated, no tailored sites: simpler, but landmarks and set pieces that a person
  shapes by eye are what make places memorable.
- Fully hand-made maps in the editor: no replay variety, and every map costs a person days.

## Consequences
Easy: new maps are data; tailored set pieces drop into any map; road kinds own their look
and props. Hard: the stitching (roads into connectors, terrain blending around footprints)
is the risky part and needs a map preview tool to review. Today's start tunnel becomes a
tailored "start" site. Revisit if region size hurts streaming or server memory.
