class_name MissionType
extends Node
## One kind of mission (Smash & Grab, Clean Sweep, ...), as a self-contained piece the
## missions module runs. Data names the script per mission template, so adding a kind is a
## new script and its entries in missions.json; the module never knows the kinds.
##
## The module makes one while a run is on, on the server and on every client. On the server
## it lays out its content in the zone (`server_open`), runs (`server_tick`), decides at the
## ride home whether the job is done (`server_done`) and cleans up (`server_close`). Its
## `status` dictionary goes to everyone whenever it calls `changed()`; clients use it for
## the HUD lines and markers.

## The missions module (zone, buildings, crates, riders; see its "For mission types"
## section).
var missions: Node
## The offer being run: its rolled values plus the template's own fields.
var mission: Dictionary = {}
## What the HUD and markers need, as the server last said.
var status: Dictionary = {}


## Server: put the mission's content in the zone.
func server_open() -> void:
	pass


func server_tick(_delta: float) -> void:
	pass


## Server, at the ride home: whether this ride completes the job (may hand in items).
func server_done(_riders: Array) -> bool:
	return false


## Server: the run is over; take away what this kind added (crates and buildings go with the
## module).
func server_close() -> void:
	pass


## Every instance, each physics tick while the run is on (a clock counting down).
func client_tick(_delta: float) -> void:
	pass


## The HUD lines under the mission's name for `player`.
func hud_lines(_player: Node3D) -> Array[String]:
	return []


## Markers seen through walls: `[{at: Vector3, text: String}]`.
func markers() -> Array:
	return []


## Server: sends `status` to everyone.
func changed() -> void:
	missions.call(&"type_changed")


func apply_status(new_status: Dictionary) -> void:
	status = new_status
