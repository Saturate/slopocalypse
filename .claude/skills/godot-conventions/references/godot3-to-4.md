# Godot 3 names that models still produce

Use the right-hand column. Godot 4.7 rejects or silently misbehaves with the left.

| Godot 3 | Godot 4.7 |
| --- | --- |
| `Spatial`, `KinematicBody`, `KinematicBody2D` | `Node3D`, `CharacterBody3D`, `CharacterBody2D` |
| `translation` | `position` |
| `move_and_slide(velocity, up)` | set `velocity`, set `up_direction`, call `move_and_slide()` |
| `onready var`, `export var`, `tool` | `@onready var`, `@export var`, `@tool` |
| `yield(obj, "signal")` | `await obj.signal` |
| `connect("sig", obj, "method")` | `sig.connect(method)` (Callable) |
| `emit_signal("sig", a)` | `sig.emit(a)` |
| `instance()` | `instantiate()` |
| `setget` | `var x: int: set = _set_x, get = _get_x` |
| `rand_range`, `deg2rad`, `stepify` | `randf_range`, `deg_to_rad`, `snapped` |
| `File`, `Directory` | `FileAccess`, `DirAccess` |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` |
| `PoolStringArray`, `PoolVector3Array` | `PackedStringArray`, `PackedVector3Array` |
| `funcref(obj, "m")` | `obj.m` (Callable) |
| `JSON.parse(text).result` | `JSON.parse_string(text)` or `JSON.new().parse(text)` then `.data` |
| `get_tree().change_scene("res://x.tscn")` | `get_tree().change_scene_to_file("res://x.tscn")` |
| `master`, `puppet`, `remote` RPC keywords | `@rpc("authority", "call_remote", "reliable")` |
| `get_network_master()` | `get_multiplayer_authority()` |
| `VisualServer`, `PhysicsServer` | `RenderingServer`, `PhysicsServer3D` |
