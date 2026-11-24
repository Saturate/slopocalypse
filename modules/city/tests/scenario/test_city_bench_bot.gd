extends GdUnitTestSuite
## `--bot=city` is the solo-city benchmark's walk: the server keeps that player alive, or
## the city's soldiers shoot it, it respawns at the start and they pile up round it, and the
## bench measures that instead of the walk.

const PLAYER := "res://modules/player/scenes/player.tscn"
const CITY := "res://modules/city/city_module.gd"


func after_test() -> void:
	Net.extra_args.clear()


func _spawn(args: PackedStringArray) -> PlayerController:
	Net.extra_args = args
	add_child(auto_free((load(CITY) as GDScript).new()))
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	return player


func test_the_bench_walker_cannot_be_killed() -> void:
	var player := _spawn(PackedStringArray(["--bot=city"]))
	assert_bool(HealthComponent.find_on(player).invulnerable).is_true()


func test_without_the_bench_walk_players_can_be_killed() -> void:
	var player := _spawn(PackedStringArray(["--start=city"]))
	assert_bool(HealthComponent.find_on(player).invulnerable).is_false()
