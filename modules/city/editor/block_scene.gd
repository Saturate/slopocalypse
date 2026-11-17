@tool
class_name BlockScene
extends Node3D
## The editor side of a hand-made city block (#339): put `BlockPiece` and `BlockMarker`
## children under this, shape them by eye with their generators shown live, then press Save
## to write `modules/city/data/blocks/<block_name>.json`. Load rebuilds the children from that
## file, so a block written as data by hand or by an agent opens here too.

@export var block_name := "new_block"
## Metres across x and z inside the pavement; the block's middle is this node's origin.
@export var size := Vector2(33.0, 33.0)
@export var tags: PackedStringArray = []
@export_tool_button("Save block", "Save") var save_button := save_block
@export_tool_button("Load block", "Load") var load_button := load_block


## The block these children describe.
func to_block() -> CityBlock:
	var b := CityBlock.new()
	b.name = block_name
	b.size = size
	for t in tags:
		b.tags.append(t)
	for child in get_children():
		if child is BlockPiece:
			var p := child as BlockPiece
			b.pieces.append({"generator": p.generator, "params": p.params.duplicate(), "at": p.position, "yaw": snappedf(p.rotation_degrees.y, 0.01), "vary": Array(p.vary)})
		elif child is BlockMarker:
			var m := child as BlockMarker
			b.markers.append({"kind": m.kind, "at": m.position, "yaw": snappedf(m.rotation_degrees.y, 0.01)})
	return b


## Replaces the children with `b`'s pieces and markers.
func show_block(b: CityBlock) -> void:
	for child in get_children():
		if child is BlockPiece or child is BlockMarker:
			remove_child(child)
			child.queue_free()
	block_name = b.name
	size = b.size
	tags = PackedStringArray(b.tags)
	var owner_node := owner if owner != null else self
	for i in b.pieces.size():
		var p: Dictionary = b.pieces[i]
		var piece := BlockPiece.new()
		piece.name = "%s%d" % [str(p["generator"]).trim_prefix("Vox"), i]
		piece.generator = p["generator"]
		piece.params = (p["params"] as Dictionary).duplicate()
		piece.vary = PackedStringArray(p["vary"])
		piece.position = p["at"]
		piece.rotation_degrees.y = float(p["yaw"])
		add_child(piece)
		piece.owner = owner_node
	for i in b.markers.size():
		var m: Dictionary = b.markers[i]
		var marker := BlockMarker.new()
		marker.name = "%s%d" % [str(m["kind"]).capitalize(), i]
		marker.kind = m["kind"]
		marker.position = m["at"]
		marker.rotation_degrees.y = float(m["yaw"])
		add_child(marker)
		marker.owner = owner_node


func save_block() -> void:
	var path := CityBlock.FOLDER + block_name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % path)
		return
	file.store_string(JSON.stringify(to_block().to_data(), " ") + "\n")
	print("Saved city block %s" % path)


func load_block() -> void:
	var b := CityBlock.load_named(block_name)
	if b != null:
		show_block(b)
