class_name RenderLayers
extends RefCounted
## Render (visual) layers that more than one module relies on, as bit values. Cameras and
## lights see every layer; nothing culls by layer except the decals and lights noted here
## (docs/decisions/0009, 0018).

## Layer 1, Godot's own default: named so code moving something off it says which layer it
## leaves rather than clearing a bare bit.
const DEFAULT := 1
## Layer 19: your own arms and what they hold, in first person, and nothing else. A light
## at your own chest (your glowstick) leaves it out: a hand's width from the gun, it would
## wash it out in flat colour. Decals leave it alone too, like people.
const FIRST_PERSON := 1 << 18
## Layer 20: people's meshes (players, soldiers, civilians, their gear and their ragdolls).
## Decals leave it alone, so blood on a wall or under a body never paints a person.
const NO_DECALS := 1 << 19
