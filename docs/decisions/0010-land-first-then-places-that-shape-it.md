# 0010. The land comes first; settlements and roads are placed on it and shape it

Status: accepted
Date: 2026-11-20
Issue or PR: #331

## Context
Record 0007 placed sites first, joined them with roads, then bent the terrain to fit with
flat pads and blends. On today's map that order shows its cost: a city squared onto a
slope with metres of ramp to the road, mission sites dropped on city blocks, roads that
meet the city badly, steps where a flat pad meets a climbing road (playtest 2, #401, #403).
Every fix so far has been a special case in one module. The maintainer asked for the other
order: make the world, then fill it in from the land, and let towns and roads reshape the
hills the way real construction does.

## Decision
World generation runs in stages, each seeded and pure (server and clients build the same
world from a recipe name and seed), each reading the result of the ones before:
1. **Land**: height from noise and the recipe, flatter overall with long gentle hills;
   water collects in low ground; biomes.
2. **Zones**: the land is classified into areas (large flat lowland, valley, hilltop,
   forest, wetland) with a suitability per use.
3. **Settlements**: the city in the best large flat zone, towns in smaller ones, the
   player camp at an edge.
4. **Roads**: a road network joins the settlements, routed over the land with a cost for
   grade, curvature and earthworks. Roads **cut and fill**: the ground is cut down to the
   road with graded banks in hills and built up with embankments over dips; a tunnel where
   a cut would be deeper than a limit, a bridge where a fill would be higher or over water.
5. **Remoteness**: distance from the settlements along that network (#419).
6. **Places**: sites and props chosen by zone and remoteness (farms on open lowland,
   cabins in remote forest, antennas on hilltops, water towers at farms and towns,
   persistent mission sites #422), all claimed on one shared occupancy map so nothing
   overlaps.
7. **Settlement layout**: streets fitted to the zone's shape and the land, branching from
   where roads arrive, not a square grid; each plot and street is levelled on its own
   terrace with graded banks between them, so a town climbs a hill instead of flattening it.
8. **Fill**: trees, rocks, grass from a grass map (#329), and what lines roads (utility
   poles, signs, a name sign where a town starts).

Earthworks are part of the height function: a stage that shapes the land adds its cuts,
fills and terraces as data, and the terrain samples them, so collision and the drawn
ground always agree. Whole-map invariants (#415) run on the result.

Tailored sites from 0007 stay: a tailored site is placed in stage 6 like a generated one
and brings its own terraces.

## Alternatives
- Keep 0007's order (sites, roads, then terrain): settles placement before knowing the
  land, so every site needs pads and blends to fit, which is what playtest 2 found janky.
- Land first, but nothing reshapes it (settlements only where flat enough): simpler, but
  few spots qualify and roads would wind or climb unrealistically.

## Consequences
Easy: placement is correct by construction (every place checks the land and the
occupancy map); roads and towns look built rather than pasted. Hard: road routing and
earthworks are the risky part and need the map preview and invariants from the start; the
current square-grid city becomes one layout style among others and its generator is
reworked. Revisit if routing over a 2 x 2 km region is too slow to run at load.

Supersedes the generation order in 0007 (recipes, tailored sites and road kinds from 0007
stand).
