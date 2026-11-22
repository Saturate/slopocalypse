# 0015. Ground tilts on gentle slopes; roads are strips, lanes are paint

Status: accepted
Date: 2026-11-21
Issue or PR: #498

## Context
The visible ground was voxel columns with flat tops stepping in whole voxels everywhere.
Gentle slopes read as rows of terraces with dark risers, and from above the map showed
contour lines. Roads and tracks are voxel models laid over that ground, so their edges sat
on steps with seams along them, and site yards were drawn as track strips with a raised
lip. Collision was already a smooth 1 m height map, so this is a drawing question only.

## Decision
- **Ground (Rust, `voxkit_core::heightfield`):** a column whose grade (from its four corner
  heights) is under `tilt_grade` tilts its top to the true height at its corners. Tilted
  neighbours share corners and meet with no wall. Steeper columns keep flat, stepped tops,
  so banks, cliffs and crater walls still read as blocks. Wherever two columns show
  different heights along a shared edge, a wall closes the gap, facing the lower side
  (split into two triangles where the two profiles cross). A step beside tilted ground
  whose middle stands over their shared edge is rounded up, so the two meet in a riser and
  not in a crevice.
- **Steep ground and shaded walls (#509):** stepped ground at least `ledge_grade` steep (0.5,
  a margin over the 0.45 the scatter keeps trees, rocks and grass under, as the two measure
  slope over different spans), clear of every way's band, not dug and not beside tilted
  ground steps in ledges `ledge` (0.5 m) and one voxel more tall, in an order set by the
  height alone so neighbouring tiles agree and the ledges read as uneven strata, rounded to
  the nearest ledge (at most 0.375 m off the ground walked on at a column's middle). Where
  ledges meet single steps the two can differ by a voxel. Detail levels whose voxel is
  already a ledge tall keep single steps, so the pattern changes at the first detail
  boundary. Wall faces get a share (`wall_light`, 0.35) of the sun's light as emission,
  less the more they face the sun, which `VoxelWorld` reads off the world's sun so it fades
  at dusk; screen-space occlusion had turned every riser on a steep slope near black
  (sampled RGB 9, 23, 0). Emission ignores shadows, so a wall in a tree's or a bridge's
  shadow still gets it.
- **Level ground stays cheap:** a tilted column whose four corners are equal is drawn with
  the steps and merged in two directions, so a level tile is still one quad. Sloping tilted
  tops merge into rectangles inside one height sample cell while every corner they cover
  lies on the rectangle's bilinear surface. A merged top gets a vertex wherever another
  top's corner meets its edge (fanned from its middle), so no T-junction draws a hairline
  crack, and sloping tops take smooth per-corner normals.
- **Looks:** sloping tilted tops carry vertex alpha 0; the shader keys their brightness
  variation by column (0.16 against 0.07 on flat tops), however gentle the slope. They get
  corner shading where a stepped neighbour stands over them, across tile edges too.
- **Beside strips and pads:** the mesher gets the ways over each tile as segments (8
  floats: two ends with heights, half width, kind) with a box each, so a column only
  measures the few near it. Within `band` metres of a road's or track's edge, and
  `pad_band` of a levelled pad (a site's, a town's, a mission building's), the ground tilts
  where gentler than `band_grade`. Corners within 1 m of a strip (the same at every level
  of detail, so neighbouring tiles agree) are held under the lowest strip over them: 2 cm
  under its edge, 30 cm under a paved road's middle so a pothole or a blast shows the bed's
  depth. On coarse tiles the ground along a track's edge comes up to 1 cm under its
  surface.
- **Road kinds:** highway and two-lane roads stay strips with kerbs and lines; potholes keep
  clear of the edge lines, go through the asphalt only (one flat level, #509), have a dark
  bed and a lighter rim of broken asphalt. Where a way
  ends, its strip ends square and the ground under it stops there. A track is a strip with
  no kerb and a straight edge; on fine tiles the ground comes up a few millimetres over
  that edge by a wandering amount (`track_fray`) and is painted as verge, so the ground
  draws the frayed edge and no side face of the strip shows. (Fraying the strip model
  itself left the ends of its ragged cells standing as dark notches.) Where a track runs
  onto another way, the earthworks cut its strip back until it clears that one's (at most
  30 m) and paint the rest of it into the ground, and a track that joins a road arrives
  level across that road's half width.
- **Lanes and yards:** a new `lane` kind and the site and camp yards (through the unchanged
  `SceneryScatter.set_yards_for`) are painted into the ground's own columns in exactly the
  track strip's soil, with darker rut cells, edges that wander out (`yard_fray`, smooth
  noise), corners rounded (`yard_round`) and a one-cell verge. The mesher marks painted
  columns in vertex alpha, and the shader draws them with the strip model's grain (0.1 m
  cells, the same brightness jitter, roughness and specular), so a track running into a
  yard shows no colour line. Craters keep their earth: a dug mask per height sample turns
  paint off.

Chosen: `tilt_grade` 0.34 at every level of detail (far tiles did not need their own),
`band` 4.0 m (the 1.5 m earthworks shoulder and a track's whole cut bank), `pad_band`
6 m, `band_grade` 1.3 (a track's 1.2 banks tilt; cliffs keep their steps).

## Alternatives
An evaluation branch (`eval-ground-roads`) drew the same six spots (farm, cabin, highway
climb, hillside, wide view, steep bank) four ways behind a switch, with two blind reviews
and the maintainer's pick:
- **A, as before:** terraces everywhere, roads as strips over them. The contour lines and
  edge seams were the problem.
- **B, tilt only beside roads:** fixed the seams, kept terraced hills everywhere else.
- **C, tilt everywhere and paint every road into the ground:** the smoothest ground, but
  painted asphalt lost its kerbs, lines and potholes at a distance, and lines on voxels
  coarser than a quarter metre were metres wide.
- **D, tilt everywhere, keep road strips:** picked. A review found its 4.5 m band smoothed
  steep banks next to stepped ground. With a 4.5 m band and a 0.5 cap, a row of dark
  triangular walls ran mid-slope along the band's edge on hillside tracks; with a 2 m band
  and a 1.0 cap the track's own bank stayed stepped beside a tilted shoulder and read as a
  dark slit. A band that takes in the whole track cut (4 m, cap 1.3) leaves neither.
Painting tracks too (as C) was rejected for the same reasons as paved roads at distance;
painting is kept for lanes and yards, which are subtle by design.

## Consequences
- Cost: sloping ground has more triangles than merged flat tops. The evaluation measured
  near tiles up to about 1 ms more mesh time on a worker thread, with 1.5 to 2.7 times the
  triangles; far tiles barely change. Merging level ground in two directions and sloping
  tops a sample cell at a time brought the open-country scenes under main.
- Where the grade crosses `tilt_grade`, columns switch between tilted and stepped, and
  small walls show along that line. That is the price of keeping steep ground stepped; a
  lower or higher threshold moves the line, it does not remove it.
- Nothing routes `lane` roads yet; the kind is drawn wherever a recipe makes one. Field
  lanes and footpaths are a later issue.
- Revisit if triangle counts start to matter for the frame budget, or if the step and tilt
  mix reads badly on a new recipe.

`tools/bench.ts`, reference Mac, main (e103f66) against this change, run alternately (frame
times in ms; a virtual machine took 60 to 100 % of a core throughout, so absolute numbers
run high):

| Scenario | Main: mean / p95 | This change: mean / p95 |
| --- | --- | --- |
| solo-city, run 1 | 26.87 / 35.26 | 25.46 / 32.20 |
| solo-city, run 2 | 32.25 / 50.89 | 23.98 / 35.40 |
| solo-city, run 3 | 28.57 / 50.25 | 24.57 / 33.01 |
| solo-walk | 8.83 / 14.01 | 9.26 / 15.73 |
| solo-drive | 9.06 / 14.61 | 10.17 / 19.28 |

Primitives drawn fall about 10 % in open country and stay level in the city. An earlier
city regression (about 2 ms) came from map generation: cutting tracks back where they run
onto other ways took 760 ms more per map build, done on the server and the client, so the
scenery's first chunk builds (100 to 250 ms each) ran past the bench's 10 s warm-up. The
search is now limited to the stretch near each track's end, and the map builds as fast as
before (1.46 s against 1.50 s on main).
