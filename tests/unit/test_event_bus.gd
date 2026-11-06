extends GdUnitTestSuite

var _bus: GameEventBus
var _received: Array[Dictionary] = []


func before_test() -> void:
	_bus = auto_free(GameEventBus.new())
	_received.clear()


func _on_event(payload: Dictionary) -> void:
	_received.append(payload)


func test_subscriber_receives_payload() -> void:
	_bus.subscribe(&"car.entered", _on_event)
	_bus.publish(&"car.entered", {"peer": 2})
	assert_array(_received).is_equal([{"peer": 2}])


func test_unsubscribed_handler_gets_nothing() -> void:
	_bus.subscribe(&"car.entered", _on_event)
	_bus.unsubscribe(&"car.entered", _on_event)
	_bus.publish(&"car.entered", {})
	assert_array(_received).is_empty()


func test_topic_with_no_subscribers_is_fine() -> void:
	_bus.publish(&"nobody.listens", {})
	assert_array(_received).is_empty()
