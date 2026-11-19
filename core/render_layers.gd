class_name RenderLayers
extends RefCounted
## Render (visual) layers that more than one module relies on, as bit values. Cameras and
## lights see every layer; nothing culls by layer except the decals noted here
## (docs/decisions/0009).

## Where everything is drawn unless it says otherwise.
const DEFAULT := 1
## Layer 20: people's meshes (players, soldiers, civilians, their gear and their ragdolls).
## Decals leave it alone, so blood on a wall or under a body never paints a person.
const NO_DECALS := 1 << 19
