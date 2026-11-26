extends CharacterBody3D


const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MIN_STEP_HEIGHT = 0.01 # rises smaller than this are left to move_and_slide
const STEP_PROBE_DISTANCE = 0.05 # how far past a ledge's edge the surface check looks

## Tallest ledge the player walks up (or down) without jumping or falling. Keep floor_snap_length similar.
@export var max_step_height: float = 0.35

# State variables
@export var on_floor: bool
@export var on_floor_previous: bool
@export var just_landed: bool
@export var velocity_proxy: Vector3 = Vector3.ZERO
var username: String = "" # name from the title screen, set by the spawner before the player is added
var speed_mul: float = 1.0 # walk speed scale, lowered by the cargo manager while carrying something heavy


@onready var char_mesh = $CharacterMesh
@onready var animation_player = $AnimationPlayer
@onready var footstep_sound = $FootstepPlayer3D
@onready var jump_sound = $JumpPlayer3D
@onready var land_sound = $LandPlayer3D
@onready var name_tag: Label3D = $NameTag # floating name above the player

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	name_tag.text = username
	name_tag.visible = !is_multiplayer_authority() # hiding our own tag, others still see it

func _update_animation() -> void:
	if not on_floor:
		animation_player.speed_scale = 1
		animation_player.play("fall")
	elif velocity_proxy.length() > 0.1:
		# compare against facing (rig faces local +Z) so it holds after mouse-look turns the body
		if velocity_proxy.dot(transform.basis.z) > 0:
			animation_player.speed_scale = 1
			animation_player.play("Walk")
		else:
			animation_player.speed_scale = -1
			animation_player.play("Walk")
	else:
		animation_player.play("Idle")

func _on_footstep() -> void:
	if multiplayer.is_server():
		return
	# play footstep sound here
	footstep_sound.play()
	pass

func _physics_process(delta: float) -> void:
	# test playing animation
	_update_animation()

	if !is_multiplayer_authority():
		return

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump (on_floor also covers rolling down a step edge).
	if Input.is_action_just_pressed("jump") and on_floor:
		velocity.y = JUMP_VELOCITY
		jump_sound.play()

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	direction = -1 * direction # multiply by negative 1 because rig is flipped backwards
	if direction:
		velocity.x = direction.x * SPEED * speed_mul
		velocity.z = direction.z * SPEED * speed_mul
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	_try_step_up(delta)
	move_and_slide()
	on_floor = _is_grounded()
	just_landed = on_floor and not on_floor_previous
	if just_landed:
		land_sound.play()
	on_floor_previous = on_floor
	velocity_proxy = velocity


func _is_grounded() -> bool:
	## On the floor, or still walking down off a step: the rounded capsule rolls over ledge edges
	## for a few frames, which shouldn't count as falling (no fall animation or land sound on stairs).
	if is_on_floor():
		return true
	return on_floor_previous and velocity.dot(up_direction) <= 0.0 \
			and test_move(global_transform, -up_direction * max_step_height)


func _try_step_up(delta: float) -> void:
	## Lifts the player onto a low ledge that blocks this frame's horizontal move.
	## Sweeps the real collision shape (up, forward, down) so off-centre hits and ceilings are respected.
	if not is_on_floor():
		return
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.is_zero_approx():
		return

	# only step when a wall-like surface blocks the move (slopes are left to move_and_slide)
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, motion, hit) or _is_walkable(hit.get_normal()):
		return

	# rise as far as the ceiling allows
	var rise := up_direction * max_step_height
	if test_move(global_transform, rise, hit):
		rise = hit.get_travel()
	if rise.dot(up_direction) < MIN_STEP_HEIGHT:
		return

	# the raised shape must be able to make the move
	var raised := global_transform.translated(rise)
	if test_move(raised, motion):
		return

	# and land on walkable ground no higher than we rose
	if not test_move(raised.translated(motion), -rise, hit):
		return
	var height := _ledge_height(hit, motion.normalized())
	if height < MIN_STEP_HEIGHT or height > rise.dot(up_direction):
		return

	# the rise sweep already proved this height is clear above us
	global_position += up_direction * height


func _ledge_height(hit: KinematicCollision3D, forward: Vector3) -> float:
	## Height of the walkable surface the step sweep landed on, above our feet (-1 if not walkable).
	## The rounded capsule usually lands on the ledge's corner, whose normal is slanted and whose
	## contact sits below the top, so a short ray just past the contact point reads the real surface.
	if _is_walkable(hit.get_normal()):
		return (hit.get_position() - global_position).dot(up_direction)
	var probe := hit.get_position() + forward * STEP_PROBE_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(
			probe + up_direction * STEP_PROBE_DISTANCE, probe - up_direction * STEP_PROBE_DISTANCE,
			collision_mask, [get_rid()])
	var ray := get_world_3d().direct_space_state.intersect_ray(query)
	if ray.is_empty() or not _is_walkable(ray.normal):
		return -1.0
	return (ray.position - global_position).dot(up_direction)


func _is_walkable(normal: Vector3) -> bool:
	return normal.angle_to(up_direction) <= floor_max_angle
