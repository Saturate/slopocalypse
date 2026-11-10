extends GdUnitTestSuite
## Other modules can keep circles free of trees (mission buildings): loaded chunks rebuild
## without trees there, and the trees come back when the clearing goes.

const CONFIG := "res://modules/world/data/world.json"

var _scatter: SceneryScatter


func before_test() -> void:
	_scatter = auto_free(SceneryScatter.new())
	_scatter.config_path = CONFIG
	_scatter.set(&"_visual", false)
	_scatter.set_process(false)
	add_child(_scatter)
	_scatter.update_around([Vector3(0, 0, -150)], INF)


## Every standing tree's spot in the loaded chunks.
func _trees() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var all: Dictionary = _scatter.get(&"_trees")
	for i: int in all:
		for t: Dictionary in all[i]:
			out.append(t["at"])
	return out


func test_a_clearing_keeps_trees_out_and_lifting_it_brings_them_back() -> void:
	var trees := _trees()
	assert_int(trees.size()).is_greater(0)
	var centre := trees[0]
	var near := func(list: Array[Vector3]) -> int: return list.filter(func(t: Vector3) -> bool: return Vector2(t.x - centre.x, t.z - centre.z).length() < 10.0).size()
	assert_int(near.call(trees)).is_greater(0)
	_scatter.set_clearings([{"at": centre, "radius": 10.0}])
	assert_int(near.call(_trees())).is_equal(0)
	_scatter.set_clearings([])
	assert_int(near.call(_trees())).is_greater(0)
