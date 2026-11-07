extends Node

const PORT: int = 42069
## Fallback used when no --host arg and no ANTSY_HOST env var is present.
## Point this at your EC2 Elastic IP (or a domain pointing at it) before shipping builds.
const DEFAULT_HOST: String = "3.133.100.208" # change to "localhost for local testing w/ multiple run instances
# !EC2 instance changes public api when you stop/start it

var peer: ENetMultiplayerPeer


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
		return
	multiplayer.multiplayer_peer = peer
	print("Client connecting to %s:%d" % [host, PORT])


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


func _on_connected_to_server() -> void:
	print("[client] connected, my id is %d" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	print("[client] CONNECTION FAILED to %s:%d" % [get_host(), PORT])


func _on_server_disconnected() -> void:
	print("[client] server disconnected")
