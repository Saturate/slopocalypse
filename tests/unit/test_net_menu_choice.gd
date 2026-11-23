extends GdUnitTestSuite
## A menu choice's arguments (the benchmark's, the range's) last one session: leaving drops
## them and the feature flags they changed, so the next Solo or Join is a plain one.


func after_test() -> void:
	Net.extra_args.clear()
	Features.reload(OS.get_cmdline_user_args())


func test_leaving_forgets_the_menu_choice_and_its_flags() -> void:
	Net.extra_args = PackedStringArray(["--benchmark", "--bench=deaths", "--flags=car:off"])
	Features.reload(Net.session_args())
	assert_bool(Features.is_enabled(&"car")).is_false()
	Net.forget_menu_choice()
	assert_bool(Net.session_args().has("--benchmark")).is_false()
	assert_bool(Net.session_args().has("--bench=deaths")).is_false()
	assert_bool(Features.is_enabled(&"car")).is_true()
