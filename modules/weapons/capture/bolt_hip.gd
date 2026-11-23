extends "res://modules/weapons/capture/bolt_scope.gd"
## Capture setup: the bolt-action in first person, one shot from the hip and the bolt being
## worked after it, frame by frame: the right hand leaves the grip for the bolt knob, the
## handle turns up, slides back and forward, turns down, and the hand goes back.


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	_player.intent().fire = _ticks > 20 and _ticks < 24
