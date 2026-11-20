extends GdUnitTestSuite
## A client joins only on the server's own build (#397).


func test_the_same_build_joins() -> void:
	assert_str(Net.build_mismatch("0.9.1", 3, "0.9.1", 3)).is_empty()


func test_another_version_is_told_to_update_naming_both() -> void:
	var why := Net.build_mismatch("0.9.2", 3, "0.9.1", 3)
	assert_str(why).contains("0.9.2").contains("0.9.1").contains("Update")


func test_a_different_protocol_on_the_same_version_is_refused() -> void:
	assert_str(Net.build_mismatch("0.9.2", 4, "0.9.2", 3)).is_not_empty()


func test_the_version_claim_sorts_after_every_other_net_rpc() -> void:
	# Godot numbers a node's RPCs in name order: a new one sorting before `_hello` or
	# `_kicked` would shift them and older clients could not be told to update.
	var rpcs: Dictionary = (load("res://core/net.gd") as Script).get_rpc_config()
	# As text: StringNames themselves do not sort alphabetically.
	var names: Array[String] = []
	for key: Variant in rpcs.keys():
		names.append(str(key))
	names.sort()
	assert_str(names.back()).is_equal("_version")
