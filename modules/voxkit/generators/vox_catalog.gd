class_name VoxCatalog
extends RefCounted
## Every generator the kit has, and a sample scene that puts them together beside a road.


static func all() -> Array[VoxGenerator]:
	return [VoxRoad.new(), VoxPineTree.new(), VoxLeafTree.new(), VoxRock.new(), VoxShed.new(), VoxSupplyCrate.new(), VoxBarrel.new(), VoxTunnel.new(), VoxCar.new(), VoxGear.new(), VoxWall.new()]


## The roadside scene as [generator, params, transform] entries, laid out from a seed so it
## changes when rerolled.
static func roadside(seed: int) -> Array[Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array[Array] = []
	out.append([VoxRoad.new(), {"seed": seed, "length": 48.0, "curve": 0.3}, Transform3D.IDENTITY])
	out.append([VoxShed.new(), {"seed": seed}, Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-11.0, 0, 4.0))])
	out.append([VoxSupplyCrate.new(), {"seed": seed}, Transform3D(Basis(Vector3.UP, 0.3), Vector3(-7.6, 0, 7.4))])
	out.append([VoxSupplyCrate.new(), {"seed": seed + 1, "style": 1.0, "width": 0.8}, Transform3D(Basis(Vector3.UP, -0.2), Vector3(-7.4, 0, 8.6))])
	out.append([VoxBarrel.new(), {"seed": seed}, Transform3D(Basis.IDENTITY, Vector3(-7.8, 0, 0.4))])
	out.append([VoxBarrel.new(), {"seed": seed + 1, "paint": 3.0}, Transform3D(Basis.IDENTITY, Vector3(-7.1, 0, 1.0))])
	for i in 9:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * rng.randf_range(10.0, 22.0), 0, rng.randf_range(-22.0, 22.0))
		if side < 0.0 and absf(at.z - 4.0) < 6.0:
			at.z += 12.0
		var gen: VoxGenerator = VoxPineTree.new() if rng.randf() < 0.6 else VoxLeafTree.new()
		out.append([gen, {"seed": seed + 10 + i, "height": rng.randf_range(7.0, 12.0)}, Transform3D(Basis.IDENTITY, at)])
	for i in 6:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		out.append([VoxRock.new(), {"seed": seed + 30 + i, "width": rng.randf_range(0.6, 2.4)}, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(side * rng.randf_range(6.5, 16.0), 0, rng.randf_range(-22.0, 22.0)))])
	return out
