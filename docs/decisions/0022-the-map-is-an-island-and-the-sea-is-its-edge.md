# 0022. The map is an island and the sea is its edge

Status: accepted
Date: 2026-11-24
Issue or PR: #454

## Context
The maintainer wants a persistent home island, with missions played on islands reached by
boat (#454, part 2). The generated map (0010, 0012) was a 2 km square of land with invisible
walls at its edge. The island needs a coast that every stage before it can live with: ponds,
zones, settlements, roads, sites and power all read the land and its water, and the camp
now has to stand by the sea with room for a jetty.

## Decision
- A recipe's optional `coast` section shapes the height itself (`WorldLand.land_height`): a
  noisy coastline (a rounded square wobbled by noise), lowland settling towards a beach just
  over the sea and hills ending in low cliffs, then the ground falling to a sea floor, plus
  islets in a ring offshore. The map square grows to 2600 m so the island keeps about the
  land the 2 km map had.
- The sea is water like a pond: `WorldLand.water_level` gives the sea's level wherever the
  ground is below it and joined to the map's edge under water (a flood over the pond
  survey grid). Zones, the router, sites, power and the scenery already keep off water, so
  they keep off the sea with no rule of their own. The band `wet_distance` wide along the
  whole shore is wetland, as round a pond: roads pay to run along it and farms and sites keep
  off the beach. Land the main island does not reach is
  an `islet` zone that no use lists.
- Shore kinds are biome fields: `sand` (new, gentle ground just over the sea along the
  coast) and `rock` (now also every steep shore).
- The camp stands a set distance from the sea, and the first good camp spot with a harbour
  spot in reach wins. The harbour (root on the waterline, facing out to sea, jetty length
  to water deep enough, footprint) is map data (`Settlements.harbour`, `MapShape.harbour`,
  `world.ready` `harbour`); its footprint is reserved from roads, sites, power and trees.
  The harbour module puts the jetty, a boat shed, props and the moored boat up there from
  the map on every machine, as the camp module does its fence, all inside that footprint.
- The sea is drawn by the pond water shader with its own look (`world.json` `water.sea`)
  over the sea's own cells and out past the map, and swimming works as in ponds. Past
  `depth_limit` metres of sea a swimmer's sea stamina drains, then their health: the sea,
  not a wall, is where the world ends. The walls stay as a backstop under the water.

## Alternatives
- **A sea plane at a fixed height with no land change:** the land would need to be low at
  its edge anyway, and nothing would make beaches or keep the camp near the water.
- **A separate coast stage after the land:** every stage samples `land_height`, so a coast
  that is not in the height would disagree with collision, zones and the drawn ground.
- **Stamina for everything (sprinting too):** a larger system than the edge needs; the sea
  stamina is one value on the body and can grow into that later.

## Consequences
Easy: the sea needs no special case in placement, and the trip islands (#454 part 2) are the
same recipe section on a smaller map. Hard: every seed's world changes and old saves are set
aside (the recipe hash is in the save key); a hollow inland below sea level is dry ground or
a pond, never sea. Revisit if islands need river mouths or harbours along the coast (towns'
jetties), which would want the coastline as data rather than a field.
