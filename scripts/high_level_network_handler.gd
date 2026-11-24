extends Node

signal player_joined(id: int, user_name: String) # server: a player passed the name check
signal player_left(id: int) # server: a player with a name left

const PORT: int = 42069
## Fallback used when no --host arg and no ANTSY_HOST env var is present.
## Point this at your EC2 Elastic IP (or a domain pointing at it) before shipping builds.
const DEFAULT_HOST: String = "localhost" # change to "localhost for local testing w/ multiple run instances
# !EC2 instance changes public api when you stop/start it

# Declaring title screen variables
const TITLE_SCENE: String = "res://scenes/title_screen.tscn" # where players go back to when the connection breaks
const CONNECT_TIMEOUT: float = 5.0 # seconds to wait for the server before giving up
const KICK_DELAY: float = 2.0 # seconds before kicking a refused player, so the reason reaches them first

var peer: ENetMultiplayerPeer
var username: String = "" # name typed on the title screen
var last_error: String = "" # message the title screen shows after we get sent back
var _names: Dictionary = {} # server only: peer id -> username


func _ready() -> void:
	# Server-side signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Client-side signals
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func start_server() -> void:
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(PORT)
	if err != OK:
		push_error("Failed to create server on port %d: %s" % [PORT, error_string(err)])
		return
	multiplayer.multiplayer_peer = peer
	print("Server listening on UDP port %d" % PORT)


func start_client() -> void:
	var host: String = get_host()
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(host, PORT)
	if err != OK:
		push_error("Failed to create client for %s:%d: %s" % [host, PORT, error_string(err)])
		_back_to_title.call_deferred("Can't reach the server.")
		return
	multiplayer.multiplayer_peer = peer
	print("Client connecting to %s:%d" % [host, PORT])

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


func _on_peer_connected(id: int) -> void:
	print("[server] peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	print("[server] peer %d disconnected" % id)

	# if they never got a name, there is no player to remove
	if not _names.has(id):
		return
	_names.erase(id)
	player_left.emit(id)


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

	# checking the name with the same rules as the title screen
	var name_err = TitleScreen.check_name(user_name)
	if name_err != "":
		_refuse(id, name_err)
		return

	# giving the player a name nobody else has
	var final_name = unique_name(user_name.strip_edges(), _names.values())
	_names[id] = final_name
	print("[server] peer %d joined as %s" % [id, final_name])
	player_joined.emit(id, final_name)


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
	print("[client] CONNECTION FAILED to %s:%d" % [get_host(), PORT])
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
	get_tree().change_scene_to_file(TITLE_SCENE)
