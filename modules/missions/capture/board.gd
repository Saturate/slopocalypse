extends Node
## Capture setup: the mission board with three offers, the middle one chosen.


class FakeMissions:
	extends Node
	var offers: Array = [
		{"site": {"index": 3, "kind": "water_tower"}, "codename": "Copper Kettle", "type_name": "Smash & Grab", "place": "Water tower", "objective": "Grab the drive from the pump huts by the water tower before the strike levels them.", "distance": 640, "time_limit": 180, "payout": 120},
		{"site": {"index": 0, "kind": "farm"}, "codename": "Quiet Harbour", "type_name": "Clean Sweep", "place": "Farmstead", "objective": "Clear the farm of soldiers and bring back what they guard.", "distance": 910, "guards": 8, "payout": 160},
		{"site": {"index": 9, "kind": "antenna"}, "codename": "Grey Lantern", "type_name": "Smash & Grab", "place": "Radio mast", "objective": "A courier hid a drive at the mast. Get it out before the drones arrive.", "distance": 1200, "time_limit": 240, "payout": 200},
	]
	var current: Dictionary = {}
	var state := "home"

	func request_choose(_index: int) -> void:
		pass


func _ready() -> void:
	var missions := FakeMissions.new()
	missions.current = missions.offers[1]
	add_child(missions)
	var screen := MissionBoardScreen.new()
	screen.missions = missions
	add_child(screen)
	screen.call(&"_refresh")
	(screen.get(&"_root") as Control).visible = true
