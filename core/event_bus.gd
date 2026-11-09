class_name GameEventBus
extends Node
## Topic-based bus, registered as the `EventBus` autoload. Modules talk through topics so
## core never names a module and a deleted module leaves no dangling signal.
##
## Every handler call is a profile zone (`event/<topic>/<handler's script>`), so the perf log
## shows what each module's reaction to an event costs.

var _subscribers: Dictionary[StringName, Array] = {}
## Zone name per handler, worked out once when it subscribes.
var _zones: Dictionary[Callable, StringName] = {}


func subscribe(topic: StringName, handler: Callable) -> void:
	if not _subscribers.has(topic):
		_subscribers[topic] = []
	_subscribers[topic].append(handler)
	_zones[handler] = _zone_for(topic, handler)


func unsubscribe(topic: StringName, handler: Callable) -> void:
	if _subscribers.has(topic):
		_subscribers[topic].erase(handler)


func publish(topic: StringName, payload: Dictionary = {}) -> void:
	for handler: Callable in _subscribers.get(topic, []).duplicate():
		if handler.is_valid():
			var prof := Prof.start()
			handler.call(payload)
			Prof.stop(_zones.get(handler, &"event/other"), prof)


static func _zone_for(topic: StringName, handler: Callable) -> StringName:
	var who := "?"
	var target := handler.get_object()
	if target != null and target.get_script() is Script:
		var path := (target.get_script() as Script).resource_path
		# modules/<id>/... names the module; anything else (core, tests) its file.
		var parts := path.trim_prefix("res://").split("/")
		who = parts[1] if parts.size() > 2 and parts[0] == "modules" else path.get_file().get_basename()
	return StringName("event/%s/%s" % [topic, who])
