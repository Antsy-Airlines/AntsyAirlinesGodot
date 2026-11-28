class_name Seat
extends Interactable
## A seat a player sits in with E and leaves with Jump. This node is the marker: it sits on the floor at the base
## of the seat, facing the way a seated player faces (+Z, like the player rig).
## The server decides who sits where; every computer poses the player itself, so only one peer id goes over
## the network. The seated player's own computer keeps them on the seat, so they follow the plane when it moves.

# Declaring Default/Const variables
@export var sit_prompt: String = "Press E to sit" # E hint while the seat is free
@export var sit_offset: Vector3 = Vector3(0, -0.35, 0.1) # metres, seat space: where the player's origin goes so the sit pose lands on the cushion
@export var exit_point: Vector3 = Vector3(0, 0.05, 1.2) # metres, seat space: where the player stands after getting up

# Declaring tracking variables
var occupant: int = 0 # peer id of whoever sits here (0 = free)
var _pending_occupant: int = 0 # a late joiner's occupant whose player hadn't spawned yet


# Called when the seat is made, before the scene's values are applied.
func _init() -> void:
	interact_range = 1.5 # metres; seats sit close together, so less than the usual reach


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_process(false)

	# the server frees the seat of anyone who leaves the game
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	else:
		# a computer that joins late asks who is sitting here
		_request_state.rpc_id(1)


# Called every frame while a late joiner waits for the seated player to spawn.
func _process(_delta: float) -> void:
	var player = _find_player(_pending_occupant)
	# Guard case for the player still not being here
	if player == null:
		return
	player.take_seat(self)
	_pending_occupant = 0
	set_process(false)


func get_prompt(player: Node3D) -> String:
	## This function says what pressing E would do: sit, if the seat is free and the player is standing (see Interactable)
	# player: the player asking
	# Guard case for a taken seat, or a player who is already seated (they get up with Jump instead)
	if occupant != 0 or player == null or player.get("seat") != null:
		return ""
	return sit_prompt


func interact(id: int) -> void:
	## This function seats the player who pressed E (server only; get_prompt already checked the seat is free)
	# id: the player who pressed E
	_set_occupant.rpc(id)


func sit_transform() -> Transform3D:
	## This function gives where the seated player's origin goes, in world space
	return global_transform.translated_local(sit_offset)


func exit_transform() -> Transform3D:
	## This function gives where the player stands after getting up (facing the same way as the seat), in world space
	return global_transform.translated_local(exit_point)


func request_stand() -> void:
	## This function asks the server to let our player get up (called by the seated player's own computer)
	_request_stand.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _request_stand() -> void:
	## This function runs on the server when a seated player presses Jump
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	# Guard case for someone who isn't sitting here
	if sender != occupant:
		return
	_set_occupant.rpc(0)


@rpc("authority", "call_local", "reliable")
func _set_occupant(id: int) -> void:
	## This function runs on everyone when someone sits down or gets up, and poses the players
	# id: who sits here now (0 = nobody)
	var old = occupant
	occupant = id

	# the one getting up stands at the exit point
	var leaving = _find_player(old)
	if leaving != null:
		leaving.leave_seat(self)

	var sitting = _find_player(id)
	if sitting != null:
		sitting.take_seat(self)


func _on_peer_disconnected(id: int) -> void:
	## This function frees the seat when the player in it leaves the game (server only)
	# id: who left
	# Guard case for someone sitting elsewhere
	if id != occupant:
		return
	_set_occupant.rpc(0)


func _find_player(id: int) -> Node3D:
	## This function finds a player by peer id (null if there is none)
	# id: peer id (0 = nobody)
	# Guard case for nobody
	if id == 0:
		return null
	return get_tree().current_scene.get_node_or_null(str(id)) as Node3D


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	## This function runs on the server when a computer loads the plane and asks who sits here
	_apply_state.rpc_id(multiplayer.get_remote_sender_id(), occupant)


@rpc("authority", "call_remote", "reliable")
func _apply_state(id: int) -> void:
	## This function runs on a client with the server's view of the seat, and poses the seated player
	## (waiting for them to spawn if they haven't yet)
	# id: who sits here (0 = nobody)
	occupant = id
	var player = _find_player(id)
	if player != null:
		player.take_seat(self)
	elif id != 0:
		_pending_occupant = id
		set_process(true)
