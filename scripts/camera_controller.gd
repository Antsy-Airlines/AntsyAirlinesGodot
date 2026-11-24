extends Node3D
## Camera rig for the local player: first person + third-person back/front views (cycled with
## "switch_camera") and mouse look. Removed entirely on remote player instances.

const LOCAL_BODY_LAYER := 2 # render layer the local player's mesh is moved to (hidden in first person)

@export var mouse_sensitivity := 0.003
@export var max_pitch_degrees := 89.0

@onready var player: CharacterBody3D = get_parent()
@onready var first_person_camera: Camera3D = $FirstPersonCamera
@onready var cameras: Array[Camera3D] = [first_person_camera, $BackArm/BackCamera, $FrontArm/FrontCamera]

var camera_index := 0


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_camera"):
		camera_index = (camera_index + 1) % cameras.size()
		cameras[camera_index].make_current()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.rotate_y(-event.relative.x * mouse_sensitivity) # yaw turns the body (synced via rotation)
		var max_pitch := deg_to_rad(max_pitch_degrees)
		rotation.x = clampf(rotation.x - event.relative.y * mouse_sensitivity, -max_pitch, max_pitch)
