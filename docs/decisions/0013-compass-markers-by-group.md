# 0013. Compass markers are nodes in a group

Status: accepted
Date: 2026-11-20
Issue or PR: #455

## Context
The compass strip (#455) shows things from several modules: the mission's objective and ride
(missions), the cars (car), the camp (the world's spawn) and the other players (player). Modules
may only talk through the EventBus or a small public API, and any of them may be switched off
or deleted. The strip lives in its own module, so it must not reach into the others, and they
must not depend on it.

## Decision
- A module that wants something on the compass puts a `Node3D` in the `compass_markers` group
  with a `compass_kind` meta (`"objective"`, `"car"`, ...) and, optionally, a `compass_label`
  meta. The strip reads the group every frame and skips hidden nodes, so a marker shows and
  goes with its node's visibility and lifetime. The kind picks the shape and the colour
  (`modules/compass/data/compass.json`).
- The base comes from `world.ready`'s spawn, the partners from the `players` group. A player's
  name now rides along with their spawn data, so every client has it as the `player_name` meta.
- Client side only: nothing new is sent apart from the name.

## Alternatives
- EventBus topics (`compass.marker_set` / `cleared`): a marker announced before the compass
  module subscribes is lost, and every module would have to announce removals too. The group
  needs neither, and costs one tree lookup a frame.
- A public API on the compass (`add_marker(node)`): the other modules would depend on the
  compass being loaded; with the group, deleting the compass leaves a group nobody reads.

## Consequences
- Missions tags its 3D markers and the car tags itself; new kinds (the harbour, #454; enemies
  heard, later) are a meta on a node plus a colour in the data.
- A node in the group that is far from anything visible still costs a distance and a bearing a
  frame; fine for a handful, revisit if a module puts hundreds there.
