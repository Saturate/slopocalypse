extends GdUnitTestSuite
## Proves the Rust extension loads and GDScript gets the value the pure crate's tests pin.


func test_rust_double_through_extension() -> void:
	var rules := ExampleRules.new()
	assert_int(rules.double(21)).is_equal(42)
