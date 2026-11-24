extends Node3D
## The lobby players wait in. When the host starts the game, the waiting room is swapped
## for the airport and every player moves to their own spawn point inside terminal 1.

# Declaring Default/Const variables
const AIRPORT_PATH := "res://scenes/levels/airport.tscn" # the map the game starts in

# Getting References for everyone in the scene
@onready var _lobby_room: Node3D = $LobbyRoom # floor and light of the waiting room

# Declaring tracking variables
var _airport: Node3D # the loaded airport, null until the game starts


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# loading the airport when the host starts (or right away for a late joiner)
	HighLevelNetworkHandler.game_started.connect(_load_airport)

	# our player can show up after the airport, so placing it when it arrives
	child_entered_tree.connect(_on_child_entered)

	if HighLevelNetworkHandler.is_server_launch(): # checks if --server or --room was an argument when the program launched
		HighLevelNetworkHandler.start_server()
	else:
		print("Client mode")
		HighLevelNetworkHandler.start_client()


func _load_airport() -> void:
	## This function removes the waiting room and puts the airport in its place
	# Guard case for a second start message
	if _airport != null:
		return

	# swapping the waiting room for the airport (the server loads it too, for later cargo physics)
	_lobby_room.queue_free()
	_airport = load(AIRPORT_PATH).instantiate()
	add_child(_airport)
	print("[lobby] airport loaded")

	_place_my_player()


func _on_child_entered(node: Node) -> void:
	## This function places our player if it just spawned and the airport is already here
	# node: the child that was added (players are named by their peer id)
	if node.name == str(multiplayer.get_unique_id()):
		_place_my_player.call_deferred() # waiting a frame so the player is fully ready


func _place_my_player() -> void:
	## This function moves our own player to our spawn point in the airport
	# Guard case for when the game hasn't started yet
	if _airport == null:
		return

	# Guard case for our player not being spawned yet (the server has no player at all)
	var me = get_node_or_null(str(multiplayer.get_unique_id()))
	if me == null:
		return

	# only we move our player, the synchronizer shows it to everyone else
	me.global_transform = _airport.get_spawn(HighLevelNetworkHandler.my_slot)
	me.velocity = Vector3.ZERO
	print("[lobby] placed at spawn %d" % HighLevelNetworkHandler.my_slot)
