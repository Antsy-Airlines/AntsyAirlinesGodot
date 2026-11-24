extends MultiplayerSpawner

@export var network_player: PackedScene

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# every peer builds players the same way, so the name arrives with the spawn
	spawn_function = _make_player

	# spawning once the server accepts a name, not on connect
	HighLevelNetworkHandler.player_joined.connect(spawn_player)
	HighLevelNetworkHandler.player_left.connect(remove_player)

func spawn_player(id: int, user_name: String) -> void:
	if !multiplayer.is_server(): return

	spawn.call_deferred({"id": id, "name": user_name}) # sent to everyone, including people who join later

func _make_player(data: Dictionary) -> Node:
	## This function builds a player from the spawn data on every peer
	# data: the id and username the server sent
	var player: CharacterBody3D = network_player.instantiate()
	player.name = str(data["id"])
	player.username = data["name"]
	return player

func remove_player(id: int) -> void:
	## This function removes a player who left (the spawner removes it for everyone)
	# id: the peer that left
	if !multiplayer.is_server(): return

	var player = get_node(spawn_path).get_node_or_null(str(id))
	if player: # if they had a player
		player.queue_free()
