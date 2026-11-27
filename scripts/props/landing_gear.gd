class_name LandingGear
extends Node3D
## The plane's landing gear: the wheels slide straight up into the fuselage and back down.
## "Up" is this node's up (keep it unrotated under the plane), turned into the wheels' parent space,
## so the slide stays local and keeps working while the plane moves.
## The server decides up or down; every computer plays the slide itself, so only one bool goes over the network.
## Each computer also plays the lower or raise sound when the slide starts (not when snapping for late joiners).

# Declaring Default/Const variables
@export var wheels: Node3D # the wheels mesh (its collider is a child, so it moves along)
@export var retract_distance: float = 1.25 # metres the wheels rise when retracted
@export var move_time: float = 3.0 # seconds for a full retract or extend
@export var audio_player: SoundCuePlayer # where the sounds come from (optional: no player = silent)
@export var lower_sound: AudioStream # played when it starts lowering
@export var raise_sound: AudioStream # played when it starts retracting
@export var lower_sound_offset: float = 0.0 # seconds; > 0 waits before playing, < 0 skips that far into the sound
@export var raise_sound_offset: float = 0.0 # seconds; > 0 waits before playing, < 0 skips that far into the sound

# Declaring tracking variables
var is_down: bool = true # what the server last said
var _amount: float = 0.0 # 0 = down, 1 = retracted (the slide plays this)
var _down_position: Vector3 # wheels' local position when down
var _retract_offset: Vector3 # how far the wheels move when retracted, in their parent's space
var _tween: Tween # the slide that is playing, if any


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# remembering the down pose and turning "up by retract_distance" into the parent's space
	_down_position = wheels.position
	var parent_basis = (wheels.get_parent() as Node3D).global_basis
	_retract_offset = parent_basis.inverse() * (global_basis.y.normalized() * retract_distance)

	# a computer that joins late asks where the gear is
	if not multiplayer.is_server():
		_request_state.rpc_id(1)


func set_down(down: bool) -> void:
	## This function lowers or retracts the gear for everyone (server only)
	# down: true to lower, false to retract
	# Guard case for clients, who must ask the server instead
	if not multiplayer.is_server():
		return
	# Guard case for the gear already being there
	if down == is_down:
		return
	_set_down.rpc(down)


@rpc("authority", "call_local", "reliable")
func _set_down(down: bool) -> void:
	## This function runs on everyone when the gear is lowered or retracted, and plays the slide
	# down: true to lower, false to retract
	is_down = down
	var goal = 0.0 if down else 1.0

	# stopping a slide that is halfway, so the gear can turn around
	if _tween != null:
		_tween.kill()

	# physics time, so the wheels' collision moves in step with the players
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_pose, _amount, goal, move_time * absf(goal - _amount))

	# the sound starts with the slide; a new cue drops a stale one from gear turned around mid-slide
	if audio_player != null:
		audio_player.play_cue(lower_sound if down else raise_sound, lower_sound_offset if down else raise_sound_offset)


func _pose(amount: float) -> void:
	## This function puts the wheels where they are at one point of the slide
	# amount: 0 = down, 1 = retracted
	_amount = amount
	wheels.position = _down_position + _retract_offset * amount


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	## This function runs on the server when a computer loads the plane and asks where the gear is
	_apply_state.rpc_id(multiplayer.get_remote_sender_id(), is_down)


@rpc("authority", "call_remote", "reliable")
func _apply_state(down: bool) -> void:
	## This function runs on a client with the server's view of the gear, and snaps it there (no slide)
	# down: whether the gear is down
	is_down = down
	_pose(0.0 if down else 1.0)
