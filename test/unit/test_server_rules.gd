extends GdUnitTestSuite
## Server bookkeeping that does not need a connection: launch options, ports and spawn slots.

# Declaring tracking variables
var _saved_slots: Dictionary # the slots in the autoload before each test, put back after
var _saved_port: int # the room port in the autoload before each test


func before_test() -> void:
	_saved_slots = HighLevelNetworkHandler._slots
	_saved_port = HighLevelNetworkHandler.room_port
	HighLevelNetworkHandler._slots = {}
	HighLevelNetworkHandler.room_port = 0


func after_test() -> void:
	HighLevelNetworkHandler._slots = _saved_slots
	HighLevelNetworkHandler.room_port = _saved_port


func test_missing_launch_options() -> void:
	assert_str(HighLevelNetworkHandler.get_arg("--surely-not-given=")).is_empty()
	assert_bool(HighLevelNetworkHandler.has_flag("--surely-not-given")).is_false()
	assert_bool(HighLevelNetworkHandler.is_server_launch()).is_false()


func test_port_falls_back_to_the_normal_port() -> void:
	# no --port while testing, and no room from the front desk
	assert_int(HighLevelNetworkHandler.get_port()).is_equal(HighLevelNetworkHandler.PORT)


func test_port_from_the_front_desk_wins() -> void:
	HighLevelNetworkHandler.room_port = 42077
	assert_int(HighLevelNetworkHandler.get_port()).is_equal(42077)


func test_free_slot_gives_the_lowest_unused() -> void:
	assert_int(HighLevelNetworkHandler._free_slot()).is_equal(0)

	HighLevelNetworkHandler._slots = {11: 0, 22: 1}
	assert_int(HighLevelNetworkHandler._free_slot()).is_equal(2)

	# a player in the middle left: their slot is reused first
	HighLevelNetworkHandler._slots = {11: 0, 33: 2}
	assert_int(HighLevelNetworkHandler._free_slot()).is_equal(1)


func test_limits_make_sense() -> void:
	# the proposal says 2-4 players, and the host can also start alone
	assert_int(HighLevelNetworkHandler.MAX_PLAYERS).is_equal(4)
	assert_int(HighLevelNetworkHandler.MIN_PLAYERS).is_equal(1)
