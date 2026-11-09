extends GdUnitTestSuite
## A rifle that kicked is remembered until it settles; when it is freed (a dead soldier's body
## is cleaned up) it is dropped quietly instead of failing to erase every frame.


func test_a_freed_rifle_is_forgotten_without_errors() -> void:
	var effects: ShotEffects = auto_free(ShotEffects.new())
	add_child(effects)
	var rifle := Node3D.new()
	add_child(rifle)
	effects.remember(rifle)
	assert_int(effects.kicked_count()).is_equal(1)
	rifle.free()
	# Any error here (the engine's typed-dictionary erase failure) fails the gate's log scan.
	for i in 3:
		effects.call(&"_process_tick", 0.016)
	assert_int(effects.kicked_count()).is_equal(0)


func test_a_kicked_rifle_settles_back_to_rest() -> void:
	var effects: ShotEffects = auto_free(ShotEffects.new())
	add_child(effects)
	var rifle: Node3D = auto_free(Node3D.new())
	add_child(rifle)
	effects.remember(rifle)
	rifle.position.z += 0.1
	for i in 120:
		effects.call(&"_process_tick", 0.016)
	assert_float(rifle.position.z).is_less(0.01)
