extends SceneTree
## Test bot: one player in its own Godot process, driven by the network tests through files.
## The test writes "<io>/<bot>_<n>.cmd" with one command, the bot runs it and answers in "<io>/<bot>_<n>.out" with its state as JSON.
## Started by test/helpers/net_suite.gd like: godot --headless -s res://test/net/net_bot.gd --io=<folder> --bot=<name> --host=127.0.0.1

# Declaring Default/Const variables
const LOBBY_SCENE := "res://scenes/levels/lobby.tscn" # where a player waits and plays
const IDLE_LIMIT := 90.0 # seconds without a command before the bot closes itself (in case the test died)
const HEAVY_GAP := 1.5 # metres from a heavy crate to stand when grabbing it
const LIGHT_GAP := 1.0 # metres from a light crate to stand when picking it up

# Declaring tracking variables
var _net: Node # the HighLevelNetworkHandler autoload
var _desk: Node # the LobbyDirectory autoload
var _io: String = "" # folder the commands and answers go through
var _bot: String = "" # our name, used in the file names
var _next: int = 1 # number of the next command to run
var _time_idle: float = 0.0 # seconds since the last command
var _found: String = "" # lobby code the front desk sent us to
var _failed: String = "" # reason the front desk gave when it could not help
var _refused: String = "" # message the title screen showed after we were sent back
var _is_set_up: bool = false # true after the first frame


# Called every frame. Returning true closes the bot.
func _process(delta: float) -> bool:
	# setting up on the first frame, once the autoloads are in the tree
	if not _is_set_up:
		_set_up()

	# closing if the test stopped talking to us
	_time_idle += delta
	if _time_idle > IDLE_LIMIT:
		return true

	# remembering why the server sent us back to the title screen
	if current_scene != null and current_scene.name == "TitleScreen":
		var msg = current_scene.get_node("%Message").text
		if msg != "":
			_refused = msg

	# Guard case for no new command yet
	var path = "%s/%s_%d.cmd" % [_io, _bot, _next]
	if not FileAccess.file_exists(path):
		return false

	# running the command and answering with our state
	var line = FileAccess.get_file_as_string(path).strip_edges()
	DirAccess.remove_absolute(path)
	_time_idle = 0.0
	var stop = _run(line.split(" ", false))
	_answer(_next)
	_next += 1
	return stop


func _set_up() -> void:
	## This function finds the autoloads and reads our launch options
	_is_set_up = true
	_net = root.get_node("HighLevelNetworkHandler")
	_desk = root.get_node("LobbyDirectory")
	_io = _net.get_arg("--io=")
	_bot = _net.get_arg("--bot=")
	_net.username = _bot

	# hearing back from the front desk the same way the title screen does
	_desk.lobby_found.connect(_on_lobby_found)
	_desk.lobby_failed.connect(func(reason): _failed = reason)


func _run(parts: PackedStringArray) -> bool:
	## This function runs one command from the test, and says if the bot should close
	# parts: the command and its arguments
	# Guard case for an empty command
	if parts.is_empty():
		return false

	# a new question to the front desk forgets the last answer
	if parts[0] in ["create", "join", "oldjoin"]:
		_found = ""
		_failed = ""

	match parts[0]:
		"state": # nothing to do, the answer is our state
			pass
		"user": # user <name with spaces>: the name we join with
			_net.username = " ".join(parts.slice(1))
		"connect": # connect <port>: join a room directly, without the front desk
			_net.room_port = parts[1].to_int()
			change_scene_to_file(LOBBY_SCENE)
		"create": # ask the front desk for a new lobby
			_desk.create_lobby()
		"join": # join <code>: ask the front desk for a lobby
			_desk.join_lobby(parts[1] if parts.size() > 1 else "")
		"oldjoin": # oldjoin <code>: ask like an out of date game would
			_join_as_old_version(parts[1] if parts.size() > 1 else "")
		"start": # ask the server to start (only the host is allowed)
			_net.request_start()
		"tp": # tp <x> <y> <z> <yaw>: move our player
			_tp(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()), parts[4].to_float())
		"near": # near <crate> <side>: stand beside a crate facing it, side -1 is its -x side
			_stand_near(parts[1], parts[2].to_float())
		"press": # press E
			_press_interact()
		"leave": # leave the lobby on purpose
			_net.leave_lobby()
		"quit":
			return true
	return false


func _on_lobby_found(code: String, port: int) -> void:
	## This function goes to the lobby the front desk gave, like the title screen does
	# code: the lobby code
	# port: the room port
	_found = code
	_net.room_port = port
	change_scene_to_file(LOBBY_SCENE)


func _join_as_old_version(code: String) -> void:
	## This function asks the front desk for a lobby with a game version that is too old
	# code: the lobby code
	# swapping the normal question for one with version 0
	_desk._api.connected_to_server.disconnect(_desk._on_desk_connected)
	_desk._api.connected_to_server.connect(func(): _desk._ask.rpc_id(1, "join", code, 0))
	_desk.join_lobby(code)


func _me() -> Node3D:
	## This function gives our own player (or null)
	if current_scene == null:
		return null
	return current_scene.get_node_or_null(str(root.multiplayer.get_unique_id()))


func _tp(pos: Vector3, yaw_deg: float) -> void:
	## This function moves our player somewhere, facing a direction
	# pos: where its feet go
	# yaw_deg: 90 faces +x, -90 faces -x
	var me = _me()
	if me == null:
		return
	me.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)
	me.velocity = Vector3.ZERO


func _stand_near(crate_name: String, side: float) -> void:
	## This function moves our player beside a crate, facing it
	# crate_name: like "Crate1"
	# side: -1 for the crate -x side (facing +x), 1 for its +x side (facing -x)
	var crate = _cargo().get_node("Crates/" + crate_name)
	var gap = HEAVY_GAP if crate.heavy else LIGHT_GAP
	_tp(crate.global_position + Vector3(gap * side, 0.05, 0), -90.0 * side)


func _press_interact() -> void:
	## This function presses and lets go of E, through the normal input path
	for down in [true, false]:
		var ev = InputEventAction.new()
		ev.action = "interact"
		ev.pressed = down
		Input.parse_input_event(ev)


func _cargo() -> Node:
	## This function gives the cargo manager once the airport is loaded (or null)
	if current_scene == null:
		return null
	return current_scene.get_node_or_null("Airport/Cargo")


func _answer(num: int) -> void:
	## This function writes our state for the test (to a temp file first, so it is never read half written)
	# num: the command number we answer
	var tmp = "%s/%s_%d.tmp" % [_io, _bot, num]
	var file = FileAccess.open(tmp, FileAccess.WRITE)
	file.store_string(JSON.stringify(_state()))
	file.close()
	DirAccess.rename_absolute(tmp, "%s/%s_%d.out" % [_io, _bot, num])


func _state() -> Dictionary:
	## This function collects everything the tests look at on this computer
	var s = {
		"id": root.multiplayer.get_unique_id(),
		"scene": str(current_scene.name) if current_scene != null else "",
		"code": _net.room_code,
		"host": _net.host_id,
		"count": _net.player_count,
		"started": _net.is_started,
		"slot": _net.my_slot,
		"found": _found,
		"failed": _failed,
		"refused": _refused,
		"players": {},
		"crates": {},
		"loaded": -1,
		"prompt": "",
		"speed": 1.0,
	}

	# every player we can see: name and where they stand
	if current_scene != null:
		for node in current_scene.get_children():
			if node is CharacterBody3D:
				s["players"][str(node.name)] = {"name": node.username, "pos": _vec(node.global_position)}

	# Guard case for no airport yet
	var cargo = _cargo()
	if cargo == null:
		return s

	# every crate as this computer sees it
	for crate in cargo.get_node("Crates").get_children():
		s["crates"][str(crate.name)] = {
			"holder": crate.holder_id,
			"helper": crate.helper_id,
			"lifted": crate.is_lifted(),
			"loaded": crate.loaded,
			"pos": _vec(crate.global_position),
		}
	s["loaded"] = cargo._loaded_count()
	s["prompt"] = cargo._prompt
	var me = _me()
	if me != null:
		s["speed"] = me.speed_mul
	return s


func _vec(v: Vector3) -> Array:
	## This function turns a position into a JSON friendly list
	# v: the position
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
