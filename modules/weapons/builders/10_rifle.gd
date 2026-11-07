extends SceneTree
## Builds modules/weapons/scenes/rifle.tscn: the rifle's logic node. It sits at the
## holder's camera so shots follow the aim. It has no mesh: the one visible rifle is held
## in the body's hands (see the weapons module), and shot effects come from its muzzle.

const OUT := "res://modules/weapons/scenes/rifle.tscn"


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "Rifle"
	root.set_script(load("res://modules/weapons/scripts/hitscan_weapon.gd"))
	root.set("weapon_id", "rifle")

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)
