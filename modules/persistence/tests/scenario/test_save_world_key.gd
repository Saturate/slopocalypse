extends GdUnitTestSuite
## A save belongs to one world (#472): a save for another world, or from before saves knew
## their world, is moved aside and a fresh one starts; one for this world is kept.

const PERSISTENCE := "res://modules/persistence/persistence_module.gd"

var _dir := ""
var _world: FakeWorld


## Stands in for the world module: says which world this server plays.
class FakeWorld extends Node:
	var key := ""

	func map_key() -> String:
		return key

	func world_state_owner() -> String:
		return "world"

	func world_state_version() -> int:
		return 3

	func server_world_state() -> Dictionary:
		return {"digs": []}

	func server_restore_world_state(_version: int, _data: Variant) -> void:
		pass


func before_test() -> void:
	_dir = "user://test_save_world_key_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	_world = auto_free(FakeWorld.new())
	_world.add_to_group(&"world_map")
	add_child(_world)


func after_test() -> void:
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


func _saves(path: String, key: String) -> Node:
	_world.key = key
	var saves: Node = auto_free((load(PERSISTENCE) as GDScript).new())
	saves.set(&"enabled", false)
	add_child(saves)
	assert_bool(saves.call(&"start", path)).is_true()
	return saves


func _put_world(saves: Node) -> void:
	var store: SaveStore = saves.get(&"store")
	assert_bool(store.save_world({"loot": [], "crates": []})).is_true()


func test_a_save_from_before_saves_knew_their_world_is_moved_aside() -> void:
	var path := _dir.path_join("world.db")
	var old := _saves(path, "flat")
	_put_world(old)
	old.set(&"store", null)
	# Same file, opened by a server that plays a generated map.
	var saves := _saves(path, "map:grassland:abc:1")
	saves.call(&"_check_map")
	var aside := Array(DirAccess.get_files_at(_dir)).filter(func(f: String) -> bool: return f.begins_with("world.db.old-"))
	assert_int(aside.size()).is_equal(1)
	var store: SaveStore = saves.get(&"store")
	assert_bool(store.load_world().is_empty()).is_true()
	assert_str(str(bytes_to_var(store.load_part("map")["data"]))).is_equal("map:grassland:abc:1")


func test_a_save_for_this_world_is_kept() -> void:
	var path := _dir.path_join("world.db")
	var first := _saves(path, "map:grassland:abc:1")
	first.call(&"_check_map")
	_put_world(first)
	first.set(&"store", null)
	var again := _saves(path, "map:grassland:abc:1")
	again.call(&"_check_map")
	assert_bool((again.get(&"store") as SaveStore).load_world().is_empty()).is_false()
	assert_int(Array(DirAccess.get_files_at(_dir)).filter(func(f: String) -> bool: return f.begins_with("world.db.old-")).size()).is_equal(0)


func test_a_fresh_save_just_records_its_world() -> void:
	var saves := _saves(_dir.path_join("world.db"), "flat")
	saves.call(&"_check_map")
	assert_str(str(bytes_to_var((saves.get(&"store") as SaveStore).load_part("map")["data"]))).is_equal("flat")


## The map builds on a worker thread before the world loads (#515): a save in between (the
## only player cancels while it builds) must not write an empty world over the saved one.
func test_nothing_is_saved_before_the_world_is_loaded() -> void:
	var saves := _saves(_dir.path_join("world.db"), "map:grassland:abc:1")
	_world.add_to_group(&"world_state")
	var store: SaveStore = saves.get(&"store")
	var digs := {"digs": [[1.0, 2.0, 3.0, 2.0]]}
	assert_bool(store.save_part("world", 3, var_to_bytes(digs))).is_true()
	assert_bool(saves.call(&"server_save_world")).is_true()
	assert_dict(bytes_to_var(store.load_part("world")["data"])).is_equal(digs)
	saves.call(&"server_load_world")
	saves.call(&"server_save_world")
	assert_dict(bytes_to_var(store.load_part("world")["data"])).is_equal({"digs": []})
