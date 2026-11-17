@tool
class_name BlockMarker
extends Node3D
## A point in a hand-made city block: a door or passage (kept clear of street furniture) or a
## spawn point for guards and loot.

@export_enum("door", "passage", "spawn") var kind := "spawn"
