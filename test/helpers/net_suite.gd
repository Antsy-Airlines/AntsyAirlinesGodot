extends GdUnitTestSuite
## Base for the network tests: starts real servers and bot players as their own Godot processes,
## sends the bots commands and reads back what each one sees. Every process is stopped after each test.
## Waiting only uses gdUnit await_millis, since awaiting other objects confuses gdUnit.

# Declaring Default/Const variables
const BOT_SCRIPT := "res://test/net/net_bot.gd" # the bot player
const DESK_PORT := 42150 # test front desk, away from the real one (42069)
const STATUS_PORT := 42151 # where test rooms report to the test front desk
const ROOM_PORT := 42160 # test rooms started without the front desk
const START_WAIT := 20.0 # seconds a new process gets to start answering
const STEP_WAIT := 10.0 # seconds to wait for something to happen over the network

# Declaring tracking variables
var _io: String = "" # folder for this test: commands, answers and logs
var _pids: Array = [] # every process this test started
var _seq: Dictionary = {} # bot name -> number of its last command


func before() -> void:
	# clearing folders from older runs (not this one), so only the latest logs are kept for looking into failures
	var root = OS.get_user_data_dir().path_join("net_tests")
	if DirAccess.dir_exists_absolute(root):
		for sub in DirAccess.get_directories_at(root):
			if not sub.begins_with("%d_" % OS.get_process_id()):
				_remove_folder(root.path_join(sub))


func _remove_folder(path: String) -> void:
	## This function deletes a folder and everything inside it
	# path: the folder
	# Guard case for a folder that is not there
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_folder(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func before_test() -> void:
	# a fresh folder for each test, so old answers never get read
	_io = OS.get_user_data_dir().path_join("net_tests").path_join("%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(_io)
	_pids = []
	_seq = {}


func after_test() -> void:
	# stopping rooms the front desk started (on Windows is_process_running only knows our own processes, so no check)
	for pid in _desk_room_pids():
		OS.kill(pid)

	# then everything we started
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	await await_millis(300) # giving the ports time to free up


func _launch(args: Array, log_name: String) -> int:
	## This function starts a headless copy of the game and gives its process id
	# args: launch options
	# log_name: name of its log file in the test folder
	var base = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", _log_path(log_name)]
	var pid = OS.create_process(OS.get_executable_path(), base + args)
	assert_int(pid).override_failure_message("could not start %s" % log_name).is_greater(0)
	_pids.append(pid)
	return pid


func _log_path(log_name: String) -> String:
	## This function gives where a process writes its log
	# log_name: name given to _launch
	return _io.path_join(log_name + ".log")


func _read_log(log_name: String) -> String:
	## This function reads what a process printed so far
	# log_name: name given to _launch
	var path = _log_path(log_name)
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _wait_log(log_name: String, text: String, timeout: float = START_WAIT) -> bool:
	## This function waits until a process prints some text, and says if it did
	# log_name: name given to _launch
	# text: what to wait for
	# timeout: seconds to give up after
	var end = Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < end:
		if _read_log(log_name).contains(text):
			return true
		await await_millis(100)
	return false


func _wait_exit(pid: int, timeout: float) -> bool:
	## This function waits for a process to close on its own, and says if it did
	# pid: the process
	# timeout: seconds to give up after
	var end = Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < end:
		if not OS.is_process_running(pid):
			return true
		await await_millis(100)
	return false


func _start_room(port: int = ROOM_PORT, extra: Array = []) -> int:
	## This function starts a lobby room server and waits until it listens
	# port: the room port
	# extra: more launch options, like --empty-timeout=2
	var log_name = "room_%d_%d" % [port, _pids.size()]
	var pid = _launch(["--room", "--port=%d" % port, "--code=TESTS", "--status-port=%d" % STATUS_PORT] + extra, log_name)
	var up = await _wait_log(log_name, "waiting for players")
	assert_bool(up).override_failure_message("room on port %d did not start" % port).is_true()
	return pid


func _start_desk() -> int:
	## This function starts the front desk and waits until it listens
	var pid = _launch(["--server", "--desk-port=%d" % DESK_PORT, "--status-port=%d" % STATUS_PORT], "desk")
	var up = await _wait_log("desk", "front desk listening")
	assert_bool(up).override_failure_message("front desk did not start").is_true()
	return pid


func _desk_room_pids() -> Array:
	## This function finds the rooms the front desk started, from its log
	var pids = []
	var found = RegEx.create_from_string("\\(pid (\\d+)\\)")
	for m in found.search_all(_read_log("desk")):
		pids.append(m.get_string(1).to_int())
	return pids


func _start_bot(bot: String) -> int:
	## This function starts a bot player and waits until it answers
	# bot: its name (also its username until changed with "user")
	var pid = _launch(["-s", BOT_SCRIPT, "--io=" + _io, "--bot=" + bot, "--host=127.0.0.1", "--desk-port=%d" % DESK_PORT], bot)
	var s = await _send(bot, "state", START_WAIT)
	assert_bool(s.is_empty()).override_failure_message("bot %s did not start" % bot).is_false()
	return pid


func _send(bot: String, cmd: String, timeout: float = STEP_WAIT) -> Dictionary:
	## This function gives a bot one command and returns its state after running it ({} if it never answered)
	# bot: which bot
	# cmd: the command, like "press" or "tp -90 0.5 -20 90"
	# timeout: seconds to give up after
	_seq[bot] = _seq.get(bot, 0) + 1
	var num = _seq[bot]

	# writing to a temp file and renaming it, so the bot never reads half a command
	var tmp = _io.path_join("%s_%d.tmp_cmd" % [bot, num])
	var file = FileAccess.open(tmp, FileAccess.WRITE)
	file.store_string(cmd)
	file.close()
	DirAccess.rename_absolute(tmp, _io.path_join("%s_%d.cmd" % [bot, num]))

	# waiting for the answer
	var out = _io.path_join("%s_%d.out" % [bot, num])
	var end = Time.get_ticks_msec() + int(timeout * 1000)
	while not FileAccess.file_exists(out) and Time.get_ticks_msec() < end:
		await await_millis(30)
	if not FileAccess.file_exists(out):
		return {}
	var s = JSON.parse_string(FileAccess.get_file_as_string(out))
	return s if s is Dictionary else {}


func _wait_for(bot: String, check: Callable, timeout: float = STEP_WAIT) -> Dictionary:
	## This function asks a bot for its state until check(state) is true, and returns the last state
	# bot: which bot
	# check: func(state) -> bool
	# timeout: seconds to give up after
	var end = Time.get_ticks_msec() + int(timeout * 1000)
	var s = {}
	while Time.get_ticks_msec() < end:
		s = await _send(bot, "state")
		if not s.is_empty() and check.call(s):
			return s
		await await_millis(100)
	return s


func _joined(bot: String, port: int = ROOM_PORT) -> Dictionary:
	## This function starts a bot, joins it to a room directly and waits until it is in
	# bot: its name
	# port: the room port
	await _start_bot(bot)
	await _send(bot, "connect %d" % port)
	var s = await _wait_for(bot, func(st): return st.host != 0 and st.players.has(str(int(st.id))))
	assert_bool(s.is_empty()).override_failure_message("%s did not join" % bot).is_false()
	return s


func _crate(s: Dictionary, crate_name: String) -> Dictionary:
	## This function gives one crate from a bot state (a crate nobody holds at 0,0,0 if there is no airport yet)
	# s: a bot state
	# crate_name: like "Crate1"
	var none = {"holder": -1, "helper": -1, "lifted": false, "loaded": false, "pos": [0, 0, 0]}
	return s.get("crates", {}).get(crate_name, none)
