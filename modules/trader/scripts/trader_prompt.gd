class_name TraderPrompt
extends CanvasLayer
## Client only, local player: "Trade" with the interact key on the prompt stack while looking
## at the trader's stall.

var trader: Node
var player: Node3D


func _exit_tree() -> void:
	PromptStack.of(get_tree()).clear_line(&"trader")


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		queue_free()
		return
	var prompts := PromptStack.of(get_tree())
	if bool(trader.call(&"at_stall", player)):
		prompts.set_line(&"trader", &"interact", "Trade", 1)
	else:
		prompts.clear_line(&"trader")
