class_name PhysicsLayers
extends RefCounted
## Collision layers that more than one module relies on, as bit values.

## Things you can see through or not: everything solid, on the default layer.
const SOLID := 1
## Blocks eyes but not bodies or bullets: tree crowns and foliage. Guards' sight rays look
## for it; walking, driving and shooting go straight through.
const SIGHT := 2
## Every layer a bullet should stop at.
const BULLETS := 0xFFFFFFFF & ~SIGHT
