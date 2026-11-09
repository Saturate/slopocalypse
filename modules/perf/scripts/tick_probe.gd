extends Node
## Runs last in every physics tick (highest priority) and tells the perf module, which marks
## the tick's start on `physics_frame`: the time between is all nodes' _physics_process.

## Set by the perf module before this enters the tree.
var perf: Node


func _physics_process(_delta: float) -> void:
	perf.call(&"physics_nodes_done")
