class_name VoxelHeightGenerator
extends VoxelGeneratorScript
## Fills voxel blocks from TerrainHeights, so the voxel terrain, spawn placement and scenery
## share one height function. Runs on Voxel Tools' worker threads.
##
## Most blocks are entirely above or below the surface; those are filled in one call and
## only blocks that cross the surface pay for per-voxel work.

## Signed distance is clamped to this many voxels; beyond it the value carries no shape.
const SDF_CLAMP := 4.0

var heights: TerrainHeights
var _min_height := -INF
var _max_height := INF


func _init(terrain_heights: TerrainHeights = null) -> void:
	heights = terrain_heights
	if heights != null:
		_min_height = -heights.amplitude - 1.0
		_max_height = heights.amplitude + 1.0


func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_SDF


func _generate_block(out_buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var size := out_buffer.get_size()
	var stride := 1 << lod
	var bottom := float(origin.y)
	var top := float(origin.y + size.y * stride)
	if bottom > _max_height + SDF_CLAMP * stride:
		out_buffer.fill_f(SDF_CLAMP, VoxelBuffer.CHANNEL_SDF)
		return
	if top < _min_height - SDF_CLAMP * stride:
		out_buffer.fill_f(-SDF_CLAMP, VoxelBuffer.CHANNEL_SDF)
		return
	for z in size.z:
		var wz := float(origin.z + z * stride)
		for x in size.x:
			var wx := float(origin.x + x * stride)
			var h := heights.height_at(wx, wz)
			for y in size.y:
				var wy := float(origin.y + y * stride)
				# Distance above the surface in voxels of this LOD; negative is solid.
				var sdf := clampf((wy - h) / stride, -SDF_CLAMP, SDF_CLAMP)
				out_buffer.set_voxel_f(sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)
