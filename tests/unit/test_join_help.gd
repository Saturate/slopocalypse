extends GdUnitTestSuite
## A failed join says what to check, naming the address and port tried (#414).


func test_the_help_names_the_address_and_the_udp_port() -> void:
	var help := Net.join_help("203.0.113.5", 7790)
	assert_str(help).contains("203.0.113.5:7790").contains("UDP port 7790")


func test_the_help_lists_several_things_to_check() -> void:
	assert_int(Net.join_help("example.org", 7777).split("\n").size()).is_greater_equal(4)
