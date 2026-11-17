extends GdUnitTestSuite
## A block opened in the editor tool and saved again is the same block.


func test_every_block_round_trips_through_the_editor_scene() -> void:
	for n in CityBlock.names():
		var block := CityBlock.load_named(n)
		var scene: BlockScene = auto_free(BlockScene.new())
		add_child(scene)
		scene.show_block(block)
		var back := scene.to_block()
		assert_str(JSON.stringify(back.to_data())).override_failure_message("block %s" % n).is_equal(JSON.stringify(block.to_data()))
