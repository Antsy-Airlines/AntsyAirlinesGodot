extends GdUnitTestSuite
## Usernames: the name check on the title screen and the server adding " 2", " 3" for names already taken.

# Getting References for the scripts under test
const TitleScreenScript := preload("res://scripts/ui/title_screen.gd") # check_name, MAX_NAME_LEN
const NetScript := preload("res://scripts/network/high_level_network_handler.gd") # unique_name


func test_check_name_accepts_normal_names() -> void:
	# letters, numbers, spaces, _ and - are all fine
	for good in ["aseel332", "Sam", "big_bob", "x-wing", "Two Words"]:
		assert_str(TitleScreenScript.check_name(good)).is_empty()


func test_check_name_rejects_empty_and_spaces() -> void:
	assert_str(TitleScreenScript.check_name("")).is_equal("Please enter a username.")
	assert_str(TitleScreenScript.check_name("    ")).is_equal("Please enter a username.")


func test_check_name_trims_spaces_before_checking() -> void:
	# spaces around the name do not count towards the length
	var padded = "  " + "a".repeat(TitleScreenScript.MAX_NAME_LEN) + "  "
	assert_str(TitleScreenScript.check_name(padded)).is_empty()


func test_check_name_length_limit() -> void:
	# exactly the max is fine, one more is not
	var max_len = TitleScreenScript.MAX_NAME_LEN
	assert_str(TitleScreenScript.check_name("a".repeat(max_len))).is_empty()
	assert_str(TitleScreenScript.check_name("a".repeat(max_len + 1))).contains("at most")


func test_check_name_rejects_odd_characters() -> void:
	for bad in ["sam!", "<b>hi</b>", "tab\there", "émile", "a.b"]:
		assert_str(TitleScreenScript.check_name(bad)).contains("Use only")


func test_unique_name_keeps_a_free_name() -> void:
	assert_str(NetScript.unique_name("Sam", ["Alex", "Kim"])).is_equal("Sam")
	assert_str(NetScript.unique_name("Sam", [])).is_equal("Sam")


func test_unique_name_adds_numbers() -> void:
	assert_str(NetScript.unique_name("Sam", ["Sam"])).is_equal("Sam 2")
	assert_str(NetScript.unique_name("Sam", ["Sam", "Sam 2"])).is_equal("Sam 3")
	assert_str(NetScript.unique_name("Sam", ["Sam", "Sam 2", "Sam 3"])).is_equal("Sam 4")


func test_unique_name_ignores_upper_and_lower_case() -> void:
	# "sam" and "Sam" are the same person on screen, so they must differ
	assert_str(NetScript.unique_name("Sam", ["sam"])).is_equal("Sam 2")
	assert_str(NetScript.unique_name("SAM", ["Sam", "sam 2"])).is_equal("SAM 3")


func test_unique_name_stays_under_the_max_length() -> void:
	# a full-length name gets cut so " 2" still fits
	var max_len = TitleScreenScript.MAX_NAME_LEN
	var long_name = "abcdefghijklmnopqrstuvwxyz".left(max_len)
	var result = NetScript.unique_name(long_name, [long_name])
	assert_int(result.length()).is_less_equal(max_len)
	assert_str(result).ends_with(" 2")
	assert_str(TitleScreenScript.check_name(result)).is_empty()
