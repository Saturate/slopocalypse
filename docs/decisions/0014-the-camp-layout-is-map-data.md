# 0014. The camp's layout is map data; the camp module only builds it

Status: accepted
Date: 2026-11-21
Issue or PR: #420

## Context
Players start and respawn in a fenced camp with the mission board, the trader's stall, the
transport and their car inside. Four modules need those spots (world, missions, trader,
enemies), and the map itself needs the camp's pad before anything else is placed: the
earthworks level it, the highway leaves from its side, roads, sites, power lines and trees
keep off it. Before this, each module placed its things with its own offsets from the spawn,
laid out for a start tunnel the map no longer has.

## Decision
The world owns the layout. The map recipe's `settlements.camp.size` makes the camp a
settlement-like pad (`Settlements.camp_place`) that roads, sites and the earthworks treat
like a town's. `CampLayout` (world module, pure) lays out the fence, the gate and the named
spots on that pad from `world.json` `camp`; `WorldRoot` builds it and `world.ready` carries
it as `camp`. Missions, trader and enemies read their spots and the camp's area from it;
without one (a test that publishes `world.ready` by hand, the flat world) `CampLayout.of_ready`
lays one out round the spawn. The `camp` module only puts up the fence, the hut and the yards
from the layout, as the sites and power modules do for theirs.

## Alternatives
- A camp module owning the layout and publishing spots: every module placing things would
  depend on an optional module, and the map stages (pad, highway, clearances) would still
  need the size from somewhere in the world.
- Spots per module in each module's data: the old shape; nothing kept them inside one fence
  or off each other.

## Consequences
Turning the camp module off removes the fence and hut but leaves everything else where it
was. Base building (#31) grows from this layout: new pieces add spots or yards to it rather
than new offsets. The pad shifts the highway's start on every seed, so map tests hold the
highway to the pad's side, not the old camp point.
