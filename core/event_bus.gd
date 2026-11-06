class_name GameEventBus
extends Node
## Topic-based bus, registered as the `EventBus` autoload. Modules talk through topics so
## core never names a module and a deleted module leaves no dangling signal.

var _subscribers: Dictionary[StringName, Array] = {}


func subscribe(topic: StringName, handler: Callable) -> void:
	if not _subscribers.has(topic):
		_subscribers[topic] = []
	_subscribers[topic].append(handler)


func unsubscribe(topic: StringName, handler: Callable) -> void:
	if _subscribers.has(topic):
		_subscribers[topic].erase(handler)


func publish(topic: StringName, payload: Dictionary = {}) -> void:
	for handler: Callable in _subscribers.get(topic, []).duplicate():
		if handler.is_valid():
			handler.call(payload)
