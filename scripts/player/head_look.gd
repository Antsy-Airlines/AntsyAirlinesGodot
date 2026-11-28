class_name HeadLook
extends SkeletonModifier3D
## Turns the player's head bone to where they are looking while seated, on top of the sit animation.
## The look comes from the player's head_look (yaw, pitch), which our camera sets and the synchronizer sends,
## so everyone sees the head turn. Runs after the AnimationPlayer has posed the skeleton each frame.

# Declaring Default/Const variables
@export var head_bone: StringName = &"Bone.002" # the bone that sits on top of the neck
@export var max_yaw_degrees: float = 80.0 # how far the head turns left/right (the camera can look a little further)
@export var max_pitch_degrees: float = 60.0 # how far the head tilts up/down

# Getting References for everyone in the scene
@onready var _player: Node3D = owner # the player this head belongs to

# Declaring tracking variables
var _bone: int = -1 # index of the head bone


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_bone = get_skeleton().find_bone(head_bone)


func _process_modification_with_delta(_delta: float) -> void:
	## This function turns the head bone by the player's look, while they are seated (see SkeletonModifier3D)
	# _delta: seconds since the last update
	# Guard case for a missing bone, or a player who is standing (they turn their whole body instead)
	if _bone < 0 or _player.get("seat") == null:
		return

	var turn = look_rotation(_player.head_look)
	var skeleton = get_skeleton()
	var pose = skeleton.get_bone_global_pose(_bone)
	pose.basis = Basis(turn) * pose.basis
	skeleton.set_bone_global_pose(_bone, pose)


func look_rotation(look: Vector2) -> Quaternion:
	## This function turns a look (yaw, pitch) into the head's rotation in the rig's space (the rig faces +Z)
	# look: radians; yaw positive = left, pitch positive = up
	var yaw = clampf(look.x, -deg_to_rad(max_yaw_degrees), deg_to_rad(max_yaw_degrees))
	var pitch = clampf(look.y, -deg_to_rad(max_pitch_degrees), deg_to_rad(max_pitch_degrees))
	# tilting up turns +Z towards +Y, which is a turn about -X
	return Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.LEFT, pitch)
