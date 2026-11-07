extends Node

const PORT: int = 42069
## Fallback used when no --host arg and no ANTSY_HOST env var is present.
## Point this at your EC2 Elastic IP (or a domain pointing at it) before shipping builds.
const DEFAULT_HOST: String = "3.133.100.208" # change to "localhost for local testing w/ multiple run instances
# !EC2 instance changes public api when you stop/start it

var peer: ENetMultiplayerPeer


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
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("--host="):
			return arg.trim_prefix("--host=")

	var env_host: String = OS.get_environment("ANTSY_HOST")
	if not env_host.is_empty():
		return env_host

	return DEFAULT_HOST
