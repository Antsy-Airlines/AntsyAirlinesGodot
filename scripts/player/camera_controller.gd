extends Node3D
## Camera rig for the local player: first person + third-person back/front views (cycled with
## "switch_camera") and mouse look. Removed entirely on remote player instances.
## While seated the body is held by the seat, so looking left/right turns this pivot instead, and the look is
## handed to the player's head (head_look) so the head turns to match.
## While seated this pivot also follows the torso bone, so the view stays at the head however the sit pose sits.

const LOCAL_BODY_LAYER := 2 # render layer the local player's mesh is moved to (hidden in first person)
const TORSO_BONE := &"Bone.001" # the bone under the head; the seated view hangs off it
const SEATED_EYE_OFFSET := Vector3(0, 0.26, 0) # metres, torso bone space: from the torso to the eyes (base character standing: camera 1.75 - torso 1.49)

@export var mouse_sensitivity := 0.003
@export var max_pitch_degrees := 89.0
@export var seated_max_yaw_degrees := 100.0 # how far left/right we can look while seated

@onready var player: CharacterBody3D = get_parent()
@onready var first_person_camera: Camera3D = $FirstPersonCamera
@onready var cameras: Array[Camera3D] = [first_person_camera, $BackArm/BackCamera, $FrontArm/FrontCamera]
@onready var _skeleton: Skeleton3D = player.get_node("CharacterMesh/Armature/Skeleton3D") # the rig the seated view follows

var camera_index := 0
var _standing_position: Vector3 # this pivot's place while standing (in the player's space)
var _torso: int = -1 # index of the torso bone


func _ready() -> void:
	# Authority is set on the Player in _enter_tree (recursive), so it's valid here.
	if not is_multiplayer_authority():
		queue_free() # remote players don't need cameras or spring arm raycasts
		return

	for arm: SpringArm3D in [$BackArm, $FrontArm]:
		arm.add_excluded_object(player.get_rid())

	# Hide our own body from the first-person camera only.
	for mesh: MeshInstance3D in player.find_children("*", "MeshInstance3D"):
		mesh.layers = 1 << (LOCAL_BODY_LAYER - 1)
	first_person_camera.set_cull_mask_value(LOCAL_BODY_LAYER, false)

	cameras[camera_index].make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.seat_changed.connect(_on_seat_changed)
	_standing_position = position
	_torso = _skeleton.find_bone(TORSO_BONE)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	# Guard case for standing (the pivot keeps its fixed place) or a rig without the bone
	if player.seat == null or _torso < 0:
		return
	position = seated_eye_position()


func seated_eye_position() -> Vector3:
	## This function gives where the eyes are in the sit pose, from the torso bone (in the player's space)
	var torso = _skeleton.global_transform * _skeleton.get_bone_global_pose(_torso)
	var eyes = torso.origin + torso.basis.orthonormalized() * SEATED_EYE_OFFSET
	return player.to_local(eyes)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_camera"):
		camera_index = (camera_index + 1) % cameras.size()
		cameras[camera_index].make_current()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var max_pitch := deg_to_rad(max_pitch_degrees)
		rotation.x = clampf(rotation.x - event.relative.y * mouse_sensitivity, -max_pitch, max_pitch)
		if player.seat == null:
			player.rotate_y(-event.relative.x * mouse_sensitivity) # yaw turns the body (synced via rotation)
		else:
			look_seated(-event.relative.x * mouse_sensitivity)


func look_seated(yaw_change: float) -> void:
	## This function turns the view left/right while seated, and hands the look to the head
	# yaw_change: radians to turn (positive = left)
	var max_yaw := deg_to_rad(seated_max_yaw_degrees)
	var yaw := clampf(player.head_look.x + yaw_change, -max_yaw, max_yaw)
	rotation.y = PI + yaw # the pivot sits turned around, facing the rig's +Z
	player.head_look = Vector2(yaw, rotation.x)


func _on_seat_changed(seated: bool) -> void:
	## This function squares the view up when sitting down or getting up
	# seated: true when we just sat down
	# getting up: the body turns to where we were looking, so the view doesn't jump
	if not seated:
		player.rotate_y(player.head_look.x)
		position = _standing_position
	rotation.y = PI
	player.head_look = Vector2(0.0, rotation.x) if seated else Vector2.ZERO
