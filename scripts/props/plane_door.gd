class_name PlaneDoor
extends Interactable
## A hinged plane door players open and close with E: the side doors, and the cargo ramp at the back.
## The door swings about its hinge (its own origin); if it has a handle, the handle turns about its own axis
## while it swings, then settles back.
## The server decides open or closed; every computer plays the swing itself, so only one bool goes over the network.
## Rotations are local, so the door keeps working while the fuselage it hangs on moves.
## Also used for other hinged parts, like the cockpit shift handle (listen to `toggled` to react to it).

signal toggled(open: bool) # emitted on every computer when the server opens or closes it

# Declaring Default/Const variables
@export var door: Node3D # the door mesh, with its origin on the hinge
@export var handle: Node3D # the handle mesh under the door (optional: the cargo ramp has none)
@export var reach_points: Array[Node3D] = [] # spots players use it from (e.g. Marker3Ds); empty = the handle, else the door's middle
@export var open_prompt: String = "Press E to open the door" # E hint while closed
@export var close_prompt: String = "Press E to close the door" # E hint while open
@export var open_angle_deg: float = 90.0 # how far it swings, signed so it opens outward
@export var hinge_axis: Vector3 = Vector3.UP # hinge direction in the door's own space
@export var handle_axis: Vector3 = Vector3.RIGHT # turning axis in the handle's own space
@export var handle_angle_deg: float = 45.0 # how far the handle turns at the middle of the swing
@export var open_time: float = 1.0 # seconds for a full swing

# Declaring tracking variables
var is_open: bool = false # what the server last said
var _amount: float = 0.0 # 0 = closed, 1 = open (the swing plays this)
var _door_closed: Quaternion # door rotation when closed
var _handle_closed: Quaternion # handle rotation when closed
var _reach_point: Vector3 # where players reach for, in the door's space (the handle, or the door's middle)
var _tween: Tween # the swing that is playing, if any


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# remembering the closed pose; rotations go through quaternions so mesh scale is never touched
	_door_closed = door.quaternion
	if handle != null:
		_handle_closed = handle.quaternion
		_reach_point = door.to_local(handle.global_position)
	elif door is MeshInstance3D:
		_reach_point = door.mesh.get_aabb().get_center()

	# a computer that joins late asks whether the door is already open
	if not multiplayer.is_server():
		_request_state.rpc_id(1)


func get_prompt(_player: Node3D) -> String:
	## This function says what pressing E would do (see Interactable)
	# _player: the player asking
	return close_prompt if is_open else open_prompt


func get_distance(player: Node3D) -> float:
	## This function measures to the nearest reach point, or else the handle (or the door's middle) (see Interactable)
	# player: the player asking
	# Guard case for a door without reach points
	if reach_points.is_empty():
		return door.to_global(_reach_point).distance_to(player.global_position)

	var best = INF
	for point in reach_points:
		best = minf(best, point.global_position.distance_to(player.global_position))
	return best


func interact(_id: int) -> void:
	## This function opens a closed door or closes an open one (server only)
	# _id: the player who pressed E
	set_open(not is_open)


func set_open(open: bool) -> void:
	## This function opens or closes the door for everyone (server only)
	# open: true to open, false to close
	# Guard case for clients, who must ask the server instead
	if not multiplayer.is_server():
		return
	# Guard case for the door already being that way
	if open == is_open:
		return
	_set_open.rpc(open)


@rpc("authority", "call_local", "reliable")
func _set_open(open: bool) -> void:
	## This function runs on everyone when the door is opened or closed, and plays the swing
	# open: true to open, false to close
	is_open = open
	toggled.emit(open)
	var goal = 1.0 if open else 0.0

	# stopping a swing that is halfway, so the door can turn around
	if _tween != null:
		_tween.kill()

	# physics time, so the door's collision moves in step with the players
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_pose, _amount, goal, open_time * absf(goal - _amount))


func _pose(amount: float) -> void:
	## This function puts the door and handle where they are at one point of the swing
	# amount: 0 = closed, 1 = open
	_amount = amount
	door.quaternion = _door_closed * Quaternion(hinge_axis.normalized(), deg_to_rad(open_angle_deg) * amount)

	# Guard case for a door without a handle
	if handle == null:
		return

	# the handle turns as the door unlatches and settles back as it finishes
	var turn = deg_to_rad(handle_angle_deg) * sin(PI * amount)
	handle.quaternion = _handle_closed * Quaternion(handle_axis.normalized(), turn)


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	## This function runs on the server when a computer loads the plane and asks if the door is open
	_apply_state.rpc_id(multiplayer.get_remote_sender_id(), is_open)


@rpc("authority", "call_remote", "reliable")
func _apply_state(open: bool) -> void:
	## This function runs on a client with the server's view of the door, and snaps it there (no swing)
	# open: whether the door is open
	is_open = open
	_pose(1.0 if open else 0.0)
