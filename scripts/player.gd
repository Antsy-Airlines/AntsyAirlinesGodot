extends CharacterBody3D


const SPEED = 5.0
const JUMP_VELOCITY = 4.5
@export var on_floor: bool
@export var velocity_proxy: Vector3 = Vector3.ZERO
@onready var char_mesh = $CharacterMesh
@onready var animation_player = $AnimationPlayer

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

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

func _physics_process(delta: float) -> void:
	# test playing animation
	_update_animation()

	if !is_multiplayer_authority():
		return

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	direction = -1 * direction # multiply by negative 1 because rig is flipped backwards
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	on_floor = is_on_floor()
	velocity_proxy = velocity	
