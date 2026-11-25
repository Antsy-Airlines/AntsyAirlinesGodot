extends GdUnitTestSuite
## Lobby codes and the front desk bookkeeping: codes, free room ports, room reports and cleanup.

# Getting References for the scripts under test
const DeskScript := preload("res://scripts/network/lobby_directory.gd") # make_code and the constants

# Declaring tracking variables
var _saved_rooms: Dictionary # the rooms in the autoload before each test, put back after
var _pids: Array = [] # stand-in room processes started by the current test


func before_test() -> void:
	# working on an empty room list, so tests do not depend on each other
	_saved_rooms = LobbyDirectory._rooms
	LobbyDirectory._rooms = {}
	_pids = []


func after_test() -> void:
	LobbyDirectory._rooms = _saved_rooms
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)


func _stand_in() -> int:
	## This function starts a headless copy of the game to stand in for a room process, and gives its id
	## (on Linux Godot can only tell if its own child processes are running, so the test itself cannot stand in)
	var pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--quit-after", "3000"])
	assert_int(pid).is_greater(0)
	_pids.append(pid)
	return pid


func _room(port: int, ready: bool = true, pid: int = OS.get_process_id()) -> Dictionary:
	## This function makes a fake room entry like the front desk keeps
	# port: port of the room
	# ready: if the room already said READY
	# pid: process of the room (defaults to this test, fine when _check_rooms is not called)
	return {"port": port, "pid": pid, "players": 0, "ready": ready, "last_seen": Time.get_ticks_msec(), "waiting": []}


func test_make_code_shape() -> void:
	# checking a lot of codes, since they are random
	for i in 300:
		var code = DeskScript.make_code()
		assert_int(code.length()).is_equal(DeskScript.CODE_LEN)
		for letter in code:
			assert_bool(letter in DeskScript.CODE_LETTERS).is_true()


func test_make_code_skips_confusing_letters() -> void:
	# 0/O and 1/I look the same on screen, so they are never used
	for bad in ["0", "O", "1", "I"]:
		assert_bool(bad in DeskScript.CODE_LETTERS).is_false()


func test_new_code_never_repeats_a_running_room() -> void:
	# the same seed gives the same first code, so that code is made "taken" first
	seed(1234)
	var first = DeskScript.make_code()
	LobbyDirectory._rooms[first] = _room(42070)
	seed(1234)
	assert_str(LobbyDirectory._new_code()).is_not_equal(first)


func test_free_port_starts_at_the_first_room_port() -> void:
	assert_int(LobbyDirectory._free_port()).is_equal(DeskScript.FIRST_ROOM_PORT)


func test_free_port_fills_gaps() -> void:
	# rooms on the 1st and 3rd port: the 2nd is free
	LobbyDirectory._rooms["AAAAA"] = _room(DeskScript.FIRST_ROOM_PORT)
	LobbyDirectory._rooms["BBBBB"] = _room(DeskScript.FIRST_ROOM_PORT + 2)
	assert_int(LobbyDirectory._free_port()).is_equal(DeskScript.FIRST_ROOM_PORT + 1)


func test_free_port_gives_zero_when_all_are_used() -> void:
	for i in DeskScript.ROOM_COUNT:
		LobbyDirectory._rooms["R%04d" % i] = _room(DeskScript.FIRST_ROOM_PORT + i)
	assert_int(LobbyDirectory._free_port()).is_equal(0)


func test_room_report_marks_ready_and_counts_players() -> void:
	LobbyDirectory._rooms["ABCDE"] = _room(42070, false)
	LobbyDirectory._on_room_report("READY ABCDE 0")
	assert_bool(LobbyDirectory._rooms["ABCDE"]["ready"]).is_true()

	LobbyDirectory._on_room_report("ALIVE ABCDE 3")
	assert_int(LobbyDirectory._rooms["ABCDE"]["players"]).is_equal(3)


func test_room_report_ignores_junk_and_unknown_rooms() -> void:
	LobbyDirectory._rooms["ABCDE"] = _room(42070, false)
	for junk in ["", "HELLO", "READY", "READY ZZZZZ 1", "ALIVE abcde 2"]:
		LobbyDirectory._on_room_report(junk)
	assert_bool(LobbyDirectory._rooms["ABCDE"]["ready"]).is_false()
	assert_int(LobbyDirectory._rooms.size()).is_equal(1)


func test_check_rooms_forgets_closed_and_silent_rooms() -> void:
	# a room whose process is gone, and a healthy one
	LobbyDirectory._rooms["GONEE"] = _room(42070, true, 999999)
	LobbyDirectory._rooms["FINEE"] = _room(42072, true, _stand_in())

	LobbyDirectory._check_rooms()
	assert_array(LobbyDirectory._rooms.keys()).contains_exactly(["FINEE"])


func test_check_rooms_stops_a_room_that_went_quiet() -> void:
	# a stand-in room process that would run for a while on its own
	var pid = _stand_in()
	var quiet = _room(42071, true, pid)
	quiet["last_seen"] = Time.get_ticks_msec() - int(DeskScript.SILENT_TIMEOUT * 1000) - 1000
	LobbyDirectory._rooms["QUIET"] = quiet

	LobbyDirectory._check_rooms()
	assert_bool(LobbyDirectory._rooms.has("QUIET")).is_false()
	await await_millis(500)
	assert_bool(OS.is_process_running(pid)).is_false() # the stuck room was stopped


func test_check_rooms_gives_new_rooms_time_to_start() -> void:
	# a room that has not said READY yet is kept until START_TIMEOUT
	LobbyDirectory._rooms["NEWWW"] = _room(42070, false, _stand_in())
	LobbyDirectory._check_rooms()
	assert_bool(LobbyDirectory._rooms.has("NEWWW")).is_true()


func test_default_ports_without_launch_options() -> void:
	# the tests run without --desk-port / --status-port, so the normal ports are used
	assert_int(LobbyDirectory.desk_port()).is_equal(HighLevelNetworkHandler.PORT)
	assert_int(LobbyDirectory.status_port()).is_equal(DeskScript.STATUS_PORT)
