class_name HealthComponent
extends Node
## Health for anything that can be damaged: players, dummies, enemies, cars. Only the
## server changes it; clients learn about it through replicated events.

signal damaged(amount: float, source: Node)
signal died(source: Node)

@export var max_health: float = 100.0

var health: float = 0.0


func _ready() -> void:
	health = max_health


func is_dead() -> bool:
	return health <= 0.0


## Server only. Returns the damage actually dealt (clamped at zero health).
func server_apply_damage(amount: float, source: Node = null) -> float:
	if is_dead() or amount <= 0.0:
		return 0.0
	var dealt := minf(amount, health)
	health -= dealt
	damaged.emit(dealt, source)
	if is_dead():
		died.emit(source)
	return dealt


func server_reset() -> void:
	health = max_health


## Server only: sets health outright (a saved player coming back), with no damage or death
## signals. Clamped to (0, max]: nobody is restored dead.
func server_set(amount: float) -> void:
	health = clampf(amount, minf(1.0, max_health), max_health)


## Server only. Returns the health actually restored (never past max, never the dead).
func server_heal(amount: float) -> float:
	if is_dead() or amount <= 0.0:
		return 0.0
	var healed := minf(amount, max_health - health)
	health += healed
	return healed


## Finds the HealthComponent on a hit collider or its ancestors; hit shapes are often
## children of the entity that owns the health.
static func find_on(node: Node) -> HealthComponent:
	var current := node
	while current != null:
		for child in current.get_children():
			if child is HealthComponent:
				return child
		current = current.get_parent()
	return null
