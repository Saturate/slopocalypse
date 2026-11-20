# 0012. The generated map is the played world

Status: accepted
Date: 2026-11-20
Issue or PR: #472

## Context
Decision 0010 builds a map land first (terrain, zones, settlements, roads with earthworks,
sites), but only the preview and the admin map viewer used it; the game still played a
3 km strip with one road along -z, a start tunnel and everything placed "metres along the
road". The maintainer decided to scrap the strip rather than keep two worlds. Two questions
decided how: is the generated height cheap enough for voxel streaming and scenery, and is
building the map fast enough to do at load on the server and on every client.

## Decision
- The generated map replaces the strip. The strip's data and code (RoadPath, TerrainHeights,
  StartTunnel, RoadStages, along-the-road Remoteness, `road_point`) are removed once nothing
  reads them.
- Server and clients each build the map from (recipe, seed) at load, on a worker thread. The
  server tells clients the recipe and seed; no layout is sent.
- The height is live: `Earthworks.height` over `WorldLand`, no baked grid. Measured
  (reference machine, 50,000 random samples): the strip's height 2.5 µs a sample; the
  generated land 1.0 µs; with earthworks 3.0 to 4.3 µs. A whole map builds in 1.3 to 1.4 s
  (both shipped recipes, 2 km square).
- A save records its map key (recipe name, recipe hash, seed); a save for another map is set
  aside, never applied. No migration of strip saves.

## Alternatives
- **Keep the strip alongside:** two worlds to maintain, and the strip would hold back every
  system that places things (missions, towers, lamps) on "metres along the road".
- **Bake a height grid at load (2 m, cached by recipe and seed):** faster lookups, but 1M
  samples to build per map and a cache to invalidate; not needed at under 2x the strip's cost.
- **Height in Rust:** rule 9 fits (must match on server and clients, hot path), and it is the
  next step if streaming shows the cost; not needed yet.

## Consequences
Easy: one world; every placing system reads settlements, sites, roads and remoteness from the
map. Hard: the ground contract changes (`road_point` goes), scenery and saves move to 2D
chunk ids, and captures, tests and benchmarks that hard-code strip positions are rewritten.
Revisit the live height if voxel streaming or scenery placement shows it in profiles, or if
maps grow past 2 km.
