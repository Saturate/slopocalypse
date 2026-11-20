extends Node3D
## Capture setup: a few items lying on flat ground by the spawn, seen from standing height a
## couple of metres away, the leftmost lit up as the one a press would pick up (#424).

const WORLD := "res://modules/world/scenes/world.tscn"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const ITEMS: Array[String] = ["mag_pistol_15", "grp_ar_std", "muz_flash", "medkit", "bar_ar_14"]


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	add_child((load(WEAPONS) as GDScript).new())
	var inventory: Node = (load(INVENTORY) as GDScript).new()
	add_child(inventory)
	var spawn := (world.get_node("SpawnPoint") as Marker3D).global_position
	# Where the loot capture's pile lies: flat, open ground.
	var centre := Vector3(3.0, spawn.y, -4.2)
	var first: LootItem = null
	for i in ITEMS.size():
		var x := centre.x + (i - 2) * 0.55
		var z := centre.z + (0.25 if i % 2 == 0 else -0.25)
		var at: Vector3 = inventory.call(&"_on_ground", Vector3(x, spawn.y, z))
		var loot: LootItem = inventory.call(&"server_spawn_loot", ITEMS[i], at)
		if first == null:
			first = loot
	await get_tree().process_frame
	if first.has_method(&"set_targeted"):
		first.call(&"set_targeted", true)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	var ground: Vector3 = inventory.call(&"_on_ground", centre)
	camera.global_position = ground + Vector3(0.0, 1.7, 2.2)
	camera.look_at(ground)
