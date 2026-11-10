extends GdUnitTestSuite
## Explosion bursts run whether or not anyone is looking (#196): GPU particles pause off
## screen, so a blast behind you would start from nothing when you turned round.


func _bursts(parent: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in parent.get_children():
		if child is CPUParticles3D or child is GPUParticles3D:
			out.append(child)
	return out


func test_an_explosion_bursts_with_particles_that_run_off_screen() -> void:
	var effects: ExplosionEffects = auto_free(ExplosionEffects.new())
	add_child(effects)
	var root := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var before := _bursts(root)
	EventBus.publish(&"explosion", {"position": Vector3(0, 0, 500), "radius": 2.0})
	var added := _bursts(root).filter(func(n: Node) -> bool: return not before.has(n))
	assert_int(added.size()).is_greater(0)
	for burst: Node in added:
		assert_bool(burst is CPUParticles3D).is_true()
		assert_bool((burst as CPUParticles3D).emitting).is_true()
		burst.queue_free()
