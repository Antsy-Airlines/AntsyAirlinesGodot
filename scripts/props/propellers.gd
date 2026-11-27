class_name Propellers
extends Node3D
## The plane's propellers: they spin up to speed when started and wind down when stopped.
## Each blade turns about its own axis (local, so it keeps working while the plane moves).
## The server decides on or off; every computer plays the spin itself, so only one bool goes over the network
## (blade angles are not synced, nobody can tell).

# Declaring Default/Const variables
@export var blades: Array[Node3D] = [] # the propeller meshes, each with its origin on its hub
@export var spin_axis: Vector3 = Vector3.BACK # turning axis in each blade's own space
@export var max_speed: float = 6.0 # revolutions per second at full speed
@export var spin_up_time: float = 2.0 # seconds from stopped to full speed (and back)

# Declaring tracking variables
var is_spinning: bool = false # what the server last said
var speed: float = 0.0 # revolutions per second right now
var _angle: float = 0.0 # radians the blades have turned from rest
var _rest: Array[Quaternion] = [] # each blade's rotation at rest


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# remembering the rest pose; rotations go through quaternions so mesh scale is never touched
	for blade in blades:
		_rest.append(blade.quaternion)

	# a computer that joins late asks whether the propellers are running
	if not multiplayer.is_server():
		_request_state.rpc_id(1)


# Called every physics frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	# winding the speed towards full or stopped
	var goal = max_speed if is_spinning else 0.0
	speed = move_toward(speed, goal, max_speed / spin_up_time * delta)

	# Guard case for propellers standing still
	if speed == 0.0:
		return

	_angle = fmod(_angle + TAU * speed * delta, TAU)
	var turn = Quaternion(spin_axis.normalized(), _angle)
	for i in blades.size():
		blades[i].quaternion = _rest[i] * turn


func set_spinning(on: bool) -> void:
	## This function starts or stops the propellers for everyone (server only)
	# on: true to start, false to stop
	# Guard case for clients, who must ask the server instead
	if not multiplayer.is_server():
		return
	# Guard case for the propellers already doing that
	if on == is_spinning:
		return
	_set_spinning.rpc(on)


@rpc("authority", "call_local", "reliable")
func _set_spinning(on: bool) -> void:
	## This function runs on everyone when the propellers are started or stopped; _physics_process winds them
	# on: true to start, false to stop
	is_spinning = on


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	## This function runs on the server when a computer loads the plane and asks if the propellers run
	_apply_state.rpc_id(multiplayer.get_remote_sender_id(), is_spinning)


@rpc("authority", "call_remote", "reliable")
func _apply_state(on: bool) -> void:
	## This function runs on a client with the server's view of the propellers, and jumps to that speed (no wind-up)
	# on: whether the propellers are running
	is_spinning = on
	speed = max_speed if on else 0.0
