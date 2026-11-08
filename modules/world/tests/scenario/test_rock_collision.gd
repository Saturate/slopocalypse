extends GdUnitTestSuite
## Rocks collide where you see them: a hull the shape of the rock, not a ball that stuck up
## well above it (players walked on air and caught on nothing). Stones lower than a step get
## no collision so feet clear them.

const SCRIPT := "res://modules/world/scripts/scenery_scatter.gd"


func test_rock_collision_hugs_the_rock_and_skips_pebbles() -> void:
	var scatter: SceneryScatter = auto_free((load(SCRIPT) as GDScript).new())
	add_child(scatter)
	var heights := TerrainHeights.new(Data.load_json(scatter.config_path))
	var hulls := 0
	for shape: CollisionShape3D in scatter.get_node("SceneryCollision").get_children():
		if shape.shape is SphereShape3D:
			fail("rocks should not use sphere collision")
			return
		if not shape.shape is ConvexPolygonShape3D:
			continue
		hulls += 1
		var top := -INF
		var bottom := INF
		for p: Vector3 in (shape.shape as ConvexPolygonShape3D).points:
			top = maxf(top, p.y)
			bottom = minf(bottom, p.y)
		var ground := heights.height_at(shape.position.x, shape.position.z)
		assert_float(shape.position.y + top - ground).is_greater_equal(SceneryScatter.STEP_OVER_HEIGHT - 0.001)
		# Sunk into the ground, so nothing slips under the edge.
		assert_float(shape.position.y + bottom).is_less(ground + 0.05)
	assert_int(hulls).is_greater(10)
