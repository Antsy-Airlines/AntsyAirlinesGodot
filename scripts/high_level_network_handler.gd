extends Node

signal player_joined(id: int, user_name: String) # server: a player passed the name check
signal player_left(id: int) # server: a player with a name left
signal lobby_joined(code: String) # client: the server let us in, code is the lobby code ("" if none)
signal room_state_changed(host: int, count: int, started: bool) # client: host, player count or start changed
signal game_started # everyone: the host started the game, time to load the airport

const PORT: int = 42069
## Fallback used when no --host arg and no ANTSY_HOST env var is present.
## Point this at your EC2 Elastic IP (or a domain pointing at it) before shipping builds.
const DEFAULT_HOST: String = "localhost" # change to "localhost for local testing w/ multiple run instances
# !EC2 instance changes public api when you stop/start it

# Declaring title screen variables
const TITLE_SCENE: String = "res://scenes/title_screen.tscn" # where players go back to when the connection breaks
const CONNECT_TIMEOUT: float = 5.0 # seconds to wait for the server before giving up
const KICK_DELAY: float = 2.0 # seconds before kicking a refused player, so the reason reaches them first

# Declaring lobby room variables
const MAX_PLAYERS: int = 4 # most players allowed in one lobby (the game is for 2-4 friends)
const MIN_PLAYERS: int = 2 # players needed before the host can start
const EMPTY_TIMEOUT: float = 60.0 # seconds a room can stay empty before it shuts down
const GAME_VERSION: int = 1 # raise this when servers and players must update together
const STATUS_TIME: float = 2.0 # seconds between a room's ALIVE reports to the front desk

var peer: ENetMultiplayerPeer
var username: String = "" # name typed on the title screen
var last_error: String = "" # message the title screen shows after we get sent back
var room_code: String = "" # code of this lobby (server: from --code, client: sent on join)
var room_port: int = 0 # client only: room port the front desk sent us to (0 = use --port / PORT)
var host_id: int = 0 # peer who can start the game (the room's creator, or the next player if they leave)
var player_count: int = 0 # client: how many players are in the lobby
var is_started: bool = false # true once the host started the game
var my_slot: int = 0 # client: which airport spawn point is ours
var _names: Dictionary = {} # server only: peer id -> username
var _slots: Dictionary = {} # server only: peer id -> spawn slot
var _is_room: bool = false # server only: started with --room, so it closes when empty
var _time_empty: float = 0.0 # server only: how long the room has had nobody in it
var _status_udp: PacketPeerUDP # room only: sends READY / ALIVE to the front desk
var _time_status: float = 0.0 # room only: time since the last ALIVE report


func _ready() -> void:
	# Server-side signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Client-side signals
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# only lobby rooms shut down on their own
	if not _is_room:
		return

	# telling the front desk we are still alive and how full we are
	_time_status += delta
	if _time_status >= STATUS_TIME:
		_time_status = 0.0
		_send_status("ALIVE")

	# counting how long nobody has been in the room
	if not _names.is_empty():
		_time_empty = 0.0
		return
	_time_empty += delta

	if _time_empty >= EMPTY_TIMEOUT:
		print("[room %s] empty for %.0f s, shutting down" % [room_code, EMPTY_TIMEOUT])
		get_tree().quit()


func start_server() -> void:
	var port: int = get_port()

	# remembering if this server is a lobby room and what its code is
	_is_room = has_flag("--room")
	room_code = get_arg("--code=").to_upper()

	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port)
	if err != OK:
		push_error("Failed to create server on port %d: %s" % [port, error_string(err)])
		get_tree().quit(1) # a room that can't listen is useless, so closing it
		return
	multiplayer.multiplayer_peer = peer
	print("Server listening on UDP port %d" % port)
	if _is_room:
		print("[room %s] waiting for players (max %d)" % [room_code, MAX_PLAYERS])

		# telling the front desk this room is listening
		_status_udp = PacketPeerUDP.new()
		_status_udp.set_dest_address("127.0.0.1", LobbyDirectory.STATUS_PORT)
		_send_status("READY")


func _send_status(kind: String) -> void:
	## This function sends "KIND CODE players" to the front desk on this computer
	# kind: "READY" when the room starts, "ALIVE" every few seconds after
	var msg = "%s %s %d" % [kind, room_code, _names.size()]
	_status_udp.put_packet(msg.to_utf8_buffer())


func start_client() -> void:
	var host: String = get_host()
	var port: int = get_port()
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(host, port)
	if err != OK:
		push_error("Failed to create client for %s:%d: %s" % [host, port, error_string(err)])
		_back_to_title.call_deferred("Can't reach the server.")
		return
	multiplayer.multiplayer_peer = peer
	print("Client connecting to %s:%d" % [host, port])

	# giving up if the server doesn't answer in time
	var time_left = get_tree().create_timer(CONNECT_TIMEOUT)
	time_left.timeout.connect(_on_connect_timeout.bind(peer))


## Resolve which server to connect to, in priority order:
##   1. --host=<address> on the command line
##   2. ANTSY_HOST environment variable
##   3. DEFAULT_HOST const
func get_host() -> String:
	var args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--host="):
			return arg.trim_prefix("--host=")

	var env_host: String = OS.get_environment("ANTSY_HOST")
	if not env_host.is_empty():
		return env_host

	return DEFAULT_HOST


func get_port() -> int:
	## This function gives the room port from the front desk, then --port=<number>, then the normal PORT
	# if the front desk sent us to a room
	if room_port != 0:
		return room_port

	var port_arg = get_arg("--port=")

	# if no port was given or it isn't a number
	if not port_arg.is_valid_int():
		return PORT

	return port_arg.to_int()


func get_arg(key: String) -> String:
	## This function finds a --key=value argument and gives back the value ("" if missing)
	# key: the start of the argument, like "--code="
	var args = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with(key):
			return arg.trim_prefix(key)
	return ""


func has_flag(flag: String) -> bool:
	## This function says if a plain flag like "--room" was on the command line
	# flag: the flag to look for
	return flag in OS.get_cmdline_args() + OS.get_cmdline_user_args()


func is_server_launch() -> bool:
	## This function says if the game was started as a server (--server or --room)
	return has_flag("--server") or has_flag("--room")


func leave_lobby() -> void:
	## This function leaves the lobby on purpose and goes back to the title screen
	print("[client] leaving the lobby")
	_back_to_title("")


func _on_peer_connected(id: int) -> void:
	print("[server] peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	print("[server] peer %d disconnected" % id)

	# if they never got a name, there is no player to remove
	if not _names.has(id):
		return
	_names.erase(id)
	_slots.erase(id) # their spawn point is free again
	player_left.emit(id)

	# handing the host to the player who has been here longest
	if id == host_id:
		host_id = _names.keys()[0] if not _names.is_empty() else 0
		print("[server] host left, new host is %d" % host_id)
	_send_room_state()


func _on_connected_to_server() -> void:
	print("[client] connected, my id is %d" % multiplayer.get_unique_id())
	_request_join.rpc_id(1, username) # asking the server to let us in with our name


@rpc("any_peer", "call_remote", "reliable")
func _request_join(user_name: String) -> void:
	## This function runs on the server when a client sends its username
	# user_name: the name the client typed on the title screen
	var id = multiplayer.get_remote_sender_id()

	# Guard case for a client that already joined
	if _names.has(id):
		return

	# checking if there is space left in the lobby
	if _names.size() >= MAX_PLAYERS:
		_refuse(id, "This lobby is full (%d players)." % MAX_PLAYERS)
		return

	# checking the name with the same rules as the title screen
	var name_err = TitleScreen.check_name(user_name)
	if name_err != "":
		_refuse(id, name_err)
		return

	# giving the player a name nobody else has
	var final_name = unique_name(user_name.strip_edges(), _names.values())
	_names[id] = final_name
	_slots[id] = _free_slot()

	# the first player in made the room, so they are the host
	if host_id == 0:
		host_id = id
	print("[server] peer %d joined as %s (%d/%d)" % [id, final_name, _names.size(), MAX_PLAYERS])

	_join_accepted.rpc_id(id, room_code, _slots[id], is_started) # telling the player which lobby they are in
	player_joined.emit(id, final_name)
	_send_room_state()


@rpc("authority", "call_remote", "reliable")
func _join_accepted(code: String, slot: int, started: bool) -> void:
	## This function runs on the client when the server lets it in
	# code: the lobby code to show on screen ("" for a server without one)
	# slot: our spawn point in the airport
	# started: true if the game already started, so we go straight to the airport
	room_code = code
	my_slot = slot
	lobby_joined.emit(code)

	# a late joiner skips the waiting room
	if started:
		is_started = true
		game_started.emit()


func _free_slot() -> int:
	## This function finds the lowest spawn slot nobody is using
	for slot in MAX_PLAYERS:
		if not slot in _slots.values():
			return slot
	return 0


func _send_room_state() -> void:
	## This function tells every player who the host is, how many are in, and if the game started
	_room_state.rpc(host_id, _names.size(), is_started)


@rpc("authority", "call_remote", "reliable")
func _room_state(host: int, count: int, started: bool) -> void:
	## This function runs on the client when the lobby changes
	# host: peer id of the host
	# count: players in the lobby
	# started: true once the game started
	host_id = host
	player_count = count
	room_state_changed.emit(host, count, started)


func is_host() -> bool:
	## This function says if we are the one who can start the game
	return host_id != 0 and host_id == multiplayer.get_unique_id()


func request_start() -> void:
	## This function asks the server to start the game (only works for the host)
	_request_start.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_start() -> void:
	## This function runs on the server when the host presses Start
	var id = multiplayer.get_remote_sender_id()

	# Guard case for someone who isn't the host, or a game that already started
	if id != host_id or is_started:
		return

	# Guard case for too few players
	if _names.size() < MIN_PLAYERS:
		print("[server] start refused, only %d player(s)" % _names.size())
		return

	print("[room %s] host %d started the game with %d players" % [room_code, id, _names.size()])
	_start_game.rpc()
	_send_room_state()


@rpc("authority", "call_local", "reliable")
func _start_game() -> void:
	## This function runs on everyone (server too) when the game starts
	is_started = true
	game_started.emit()


@rpc("authority", "call_remote", "reliable")
func _join_refused(reason: String) -> void:
	## This function runs on the client when the server won't let it in
	# reason: what to tell the player on the title screen
	print("[client] join refused: %s" % reason)
	_back_to_title(reason)


func _refuse(id: int, reason: String) -> void:
	## This function tells a client why it can't join, then kicks it
	# id: the peer to refuse
	# reason: message for that player
	_join_refused.rpc_id(id, reason)

	# kicking later so the reason arrives first
	await get_tree().create_timer(KICK_DELAY).timeout
	if multiplayer.get_peers().has(id):
		multiplayer.multiplayer_peer.disconnect_peer(id)


static func unique_name(wanted: String, taken: Array) -> String:
	## This function adds " 2", " 3"... to a name until nobody else has it
	# wanted: the checked name the player asked for
	# taken: names already in the lobby

	# comparing in lowercase so "aseel" and "Aseel" count as the same
	var taken_lower = taken.map(func(n): return n.to_lower())
	var final_name = wanted
	var num = 2

	while final_name.to_lower() in taken_lower:
		var suffix = " %d" % num
		final_name = wanted.left(TitleScreen.MAX_NAME_LEN - suffix.length()) + suffix # keeping it under the max length
		num += 1

	return final_name


func _on_connection_failed() -> void:
	print("[client] CONNECTION FAILED to %s:%d" % [get_host(), get_port()])
	_back_to_title.call_deferred("Can't reach the server.")


func _on_server_disconnected() -> void:
	print("[client] server disconnected")
	_back_to_title.call_deferred("Lost connection to the server.")


func _on_connect_timeout(old_peer: ENetMultiplayerPeer) -> void:
	## This function gives up on a connection that is taking too long
	# old_peer: the connection that started the timer

	# if this timer is from an older try, or we already connected
	if old_peer != peer:
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return

	print("[client] gave up after %.0f s" % CONNECT_TIMEOUT)
	_back_to_title("Can't reach the server.")


func _back_to_title(msg: String) -> void:
	## This function closes the connection and sends the player back to the title screen
	# msg: what to tell the player on the title screen

	# Guard case for when we already went back
	if peer == null:
		return

	# closing the connection
	var old_peer = peer
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	old_peer.close()

	# going back with the message
	last_error = msg
	room_code = "" # we are not in a lobby anymore
	room_port = 0 # the next lobby gets its own port from the front desk
	host_id = 0
	player_count = 0
	is_started = false
	my_slot = 0
	get_tree().change_scene_to_file(TITLE_SCENE)
