class_name DummyTarget
extends StaticBody3D
## Training dummy: takes damage, shows its health, falls over at zero and stands back up
## after a delay.

@export var health_path: NodePath
@export var label_path: NodePath
@export var body_path: NodePath
@export var respawn_seconds: float = 2.0

var _health: HealthComponent
var _label: Label3D
var _body: Node3D
var _down_for := -1.0


func _ready() -> void:
	_health = get_node(health_path)
	_label = get_node(label_path)
	_body = get_node(body_path)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	_refresh()


func health() -> HealthComponent:
	return _health


func is_down() -> bool:
	return _down_for >= 0.0


var _shown_health := -1.0


func _process(_delta: float) -> void:
	# On clients health arrives by sync, not through the damage signals.
	if not is_equal_approx(_health.health, _shown_health):
		_refresh()


func _physics_process(delta: float) -> void:
	if _down_for < 0.0 or not multiplayer.is_server():
		return
	_down_for += delta
	if _down_for >= respawn_seconds:
		_down_for = -1.0
		_health.server_reset()
		_body.rotation = Vector3.ZERO
		_refresh()


func _on_damaged(_amount: float, _source: Node) -> void:
	_refresh()


func _on_died(_source: Node) -> void:
	_down_for = 0.0
	_body.rotation = Vector3(deg_to_rad(-80.0), 0.0, 0.0)
	_refresh()


func _refresh() -> void:
	_shown_health = _health.health
	_label.text = "%d" % ceili(_health.health)
	_label.modulate = Color(1, 0.3, 0.3) if _health.is_dead() else Color(1, 1, 1)
