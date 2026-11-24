extends Node
## Lobby codes. The front desk (--server) hands out codes and starts a room server for each lobby.
## Players ask the front desk to create or find a lobby, then join that room's port.

signal lobby_found(code: String, port: int) # client: the front desk sent us to a room
signal lobby_failed(reason: String) # client: the front desk couldn't help, or we couldn't reach it

# Declaring Default/Const variables
const FIRST_ROOM_PORT := 42070 # rooms use ports 42070-42089
const ROOM_COUNT := 20 # most lobbies running at once
const STATUS_PORT := 42068 # local-only port where rooms report READY / ALIVE
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" # no 0/O or 1/I, so codes are easy to read
const CODE_LEN := 5 # letters in a lobby code
const ASK_TIMEOUT := 5.0 # seconds a player waits for the front desk
const START_TIMEOUT := 10.0 # seconds a new room gets to say READY
const SILENT_TIMEOUT := 10.0 # seconds without ALIVE before the front desk forgets a room
const CHECK_TIME := 2.0 # seconds between front desk cleanups

# Declaring tracking variables
var _api: SceneMultiplayer # our own connection, kept apart from the game connection
var _peer: ENetMultiplayerPeer
var _status_udp: PacketPeerUDP # front desk: listens for room reports
var _rooms: Dictionary = {} # front desk: code -> {port, pid, players, ready, last_seen, waiting}
var _is_desk: bool = false # true when this game is the front desk
var _time_check: float = 0.0 # front desk: time since the last cleanup
var _asking: bool = false # client: waiting for the front desk to answer
var _ask_action: String = "" # client: "create" or "join"
var _ask_code: String = "" # client: the code we are looking for


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# giving this node its own multiplayer, so front desk calls never mix with the game
	_api = SceneMultiplayer.new()
	get_tree().set_multiplayer(_api, get_path())

	# client-side signals
	_api.connected_to_server.connect(_on_desk_connected)
	_api.connection_failed.connect(_on_desk_unreachable)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# only the front desk has rooms to look after
	if not _is_desk:
		return

	# reading every report the rooms sent
	while _status_udp.get_available_packet_count() > 0:
		_on_room_report(_status_udp.get_packet().get_string_from_utf8())

	# cleaning up every few seconds
	_time_check += delta
	if _time_check >= CHECK_TIME:
		_time_check = 0.0
		_check_rooms()


func _exit_tree() -> void:
	# stopping every room when the front desk closes
	if not _is_desk:
		return
	for code in _rooms:
		if OS.is_process_running(_rooms[code]["pid"]):
			OS.kill(_rooms[code]["pid"])


# ---------------- front desk ----------------

func start_desk() -> void:
	## This function turns this game into the front desk that hands out lobby codes
	var port = HighLevelNetworkHandler.PORT
	_peer = ENetMultiplayerPeer.new()
	var err = _peer.create_server(port)
	if err != OK:
		push_error("Front desk failed to open port %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	_api.multiplayer_peer = _peer

	# listening for room reports from this computer only
	_status_udp = PacketPeerUDP.new()
	_status_udp.bind(STATUS_PORT, "127.0.0.1")

	_is_desk = true
	print("[desk] front desk listening on UDP port %d (rooms on %d-%d)" % [port, FIRST_ROOM_PORT, FIRST_ROOM_PORT + ROOM_COUNT - 1])


@rpc("any_peer", "call_remote", "reliable")
func _ask(action: String, code: String, version: int) -> void:
	## This function runs on the front desk when a player wants to create or join a lobby
	# action: "create" or "join"
	# code: the lobby code for "join"
	# version: the player's GAME_VERSION
	var id = _api.get_remote_sender_id()

	# Guard case for a game that isn't the front desk
	if not _is_desk:
		return

	# checking the player runs the same version as the servers
	if version != HighLevelNetworkHandler.GAME_VERSION:
		_send_fail(id, "Your game is out of date. Please update.")
		return

	if action == "create":
		_create_room(id)
	elif action == "join":
		_find_room(id, code.strip_edges().to_upper())


func _create_room(id: int) -> void:
	## This function starts a new room server with a fresh code
	# id: the player who asked for it
	var port = _free_port()

	# Guard case for when every port is taken
	if port == 0:
		_send_fail(id, "All lobbies are busy, try again soon.")
		return
	var code = _new_code()

	# starting the room as its own copy of the game
	var args = []
	if not OS.has_feature("template"): # running from the editor, so pointing at the project folder
		args += ["--path", ProjectSettings.globalize_path("res://")]
	args += ["--headless", "--room", "--port=%d" % port, "--code=%s" % code]
	var pid = OS.create_process(OS.get_executable_path(), args)

	# if the room process didn't start at all
	if pid == -1:
		_send_fail(id, "Couldn't start a lobby. Please try again.")
		return

	# remembering the room; the player gets the port once it says READY
	_rooms[code] = {
		"port": port,
		"pid": pid,
		"players": 0,
		"ready": false,
		"last_seen": Time.get_ticks_msec(),
		"waiting": [id],
	}
	print("[desk] starting room %s on port %d (pid %d)" % [code, port, pid])


func _find_room(id: int, code: String) -> void:
	## This function sends a player to the room with this code, or says why it can't
	# id: the player who asked
	# code: the code they typed, already uppercase
	if code.length() != CODE_LEN:
		_send_fail(id, "Please enter a %d-character code." % CODE_LEN)
		return

	# checking the room exists and has space
	if not _rooms.has(code) or not _rooms[code]["ready"]:
		_send_fail(id, "No lobby with code %s." % code)
		return
	if _rooms[code]["players"] >= HighLevelNetworkHandler.MAX_PLAYERS:
		_send_fail(id, "This lobby is full.")
		return

	_answer_ok.rpc_id(id, code, _rooms[code]["port"])


func _on_room_report(msg: String) -> void:
	## This function updates a room from its "READY CODE players" or "ALIVE CODE players" message
	# msg: the text the room sent
	var parts = msg.split(" ")

	# Guard case for messages we don't understand or rooms we don't know
	if parts.size() < 3 or not _rooms.has(parts[1]):
		return
	var room = _rooms[parts[1]]
	room["last_seen"] = Time.get_ticks_msec()
	room["players"] = parts[2].to_int()

	# the first report means the room is listening, so sending the waiting players there
	if not room["ready"]:
		room["ready"] = true
		print("[desk] room %s ready" % parts[1])
		for id in room["waiting"]:
			if id in _api.get_peers(): # if they are still waiting
				_answer_ok.rpc_id(id, parts[1], room["port"])
		room["waiting"].clear()


func _check_rooms() -> void:
	## This function forgets rooms that closed, went silent, or never started
	var now = Time.get_ticks_msec()

	for code in _rooms.keys():
		var room = _rooms[code]
		var time_quiet = (now - room["last_seen"]) / 1000.0
		var limit = SILENT_TIMEOUT if room["ready"] else START_TIMEOUT

		# if the room is still fine
		if OS.is_process_running(room["pid"]) and time_quiet < limit:
			continue

		# telling anyone still waiting that it didn't work
		for id in room["waiting"]:
			_send_fail(id, "Couldn't start a lobby. Please try again.")

		# stopping it if it is stuck, then forgetting it
		if OS.is_process_running(room["pid"]):
			OS.kill(room["pid"])
		_rooms.erase(code)
		print("[desk] room %s closed" % code)


func _free_port() -> int:
	## This function gives the first room port nobody is using, or 0 if all are taken
	var used = _rooms.values().map(func(r): return r["port"])
	for i in ROOM_COUNT:
		if not (FIRST_ROOM_PORT + i) in used:
			return FIRST_ROOM_PORT + i
	return 0


func _new_code() -> String:
	## This function makes a random code that no running room has
	var code = make_code()
	while _rooms.has(code):
		code = make_code()
	return code


static func make_code() -> String:
	## This function makes a random lobby code like "K7QXM"
	var code = ""
	for i in CODE_LEN:
		code += CODE_LETTERS[randi() % CODE_LETTERS.length()]
	return code


func _send_fail(id: int, reason: String) -> void:
	## This function tells a player why the front desk can't help
	# id: the player
	# reason: message for the title screen
	if id in _api.get_peers(): # if they are still connected
		_answer_fail.rpc_id(id, reason)


# ---------------- player side ----------------

func create_lobby() -> void:
	## This function asks the front desk for a brand new lobby
	_ask_desk("create", "")


func join_lobby(code: String) -> void:
	## This function asks the front desk where the lobby with this code is
	# code: the code a friend shared
	_ask_desk("join", code)


func _ask_desk(action: String, code: String) -> void:
	## This function connects to the front desk and asks it for a lobby
	# action: "create" or "join"
	# code: the lobby code for "join"

	# Guard case for asking twice at the same time
	if _asking:
		return
	_asking = true
	_ask_action = action
	_ask_code = code

	# connecting to the front desk with our own connection
	var host = HighLevelNetworkHandler.get_host()
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_client(host, HighLevelNetworkHandler.PORT) != OK:
		_finish_fail("Can't reach the server.")
		return
	_api.multiplayer_peer = _peer

	# giving up if the front desk doesn't answer in time
	var time_left = get_tree().create_timer(ASK_TIMEOUT)
	time_left.timeout.connect(_on_ask_timeout.bind(_peer))


func _on_desk_connected() -> void:
	# asking our question as soon as we are connected
	_ask.rpc_id(1, _ask_action, _ask_code, HighLevelNetworkHandler.GAME_VERSION)


func _on_desk_unreachable() -> void:
	_finish_fail("Can't reach the server.")


func _on_ask_timeout(old_peer: ENetMultiplayerPeer) -> void:
	## This function gives up when the front desk takes too long
	# old_peer: the connection that started the timer

	# if this timer is from an older question, or we already got an answer
	if old_peer != _peer or not _asking:
		return
	_finish_fail("Can't reach the server.")


@rpc("authority", "call_remote", "reliable")
func _answer_ok(code: String, port: int) -> void:
	## This function runs on the player when the front desk found or made the lobby
	# code: the lobby code
	# port: the room's port to join
	_asking = false
	_close_desk.call_deferred() # hanging up after this call finishes
	lobby_found.emit(code, port)


@rpc("authority", "call_remote", "reliable")
func _answer_fail(reason: String) -> void:
	## This function runs on the player when the front desk can't help
	# reason: message for the title screen
	_finish_fail(reason)


func _finish_fail(reason: String) -> void:
	## This function stops asking and reports the problem
	# reason: message for the title screen
	_asking = false
	_close_desk.call_deferred()
	lobby_failed.emit(reason)


func _close_desk() -> void:
	## This function hangs up on the front desk
	if _peer == null or _is_desk:
		return
	var old_peer = _peer
	_peer = null
	_api.multiplayer_peer = OfflineMultiplayerPeer.new()
	old_peer.close()
