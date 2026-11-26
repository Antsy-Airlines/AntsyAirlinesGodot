extends GdUnitTestSuite
## Walking a real player into low and tall ledges on a bare floor: low ones are stepped up and down, tall ones block.

# Getting References for the helpers
const TestWorld := preload("res://test/helpers/test_world.gd") # current scene, no airport

# Declaring Default/Const variables
const FACE_OUT := 90.0 # yaw that faces +x
const LEDGE_X := 1.5 # x where the ledge starts

# Declaring tracking variables
var _world # fresh world for each test
var _left_floor: bool # set if the player was ever off the floor while walking


func before_test() -> void:
	_world = TestWorld.new(false)
	_add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40)) # the floor, top at y = 0
	_left_floor = false
	await await_millis(50)


func after_test() -> void:
	Input.action_release("move_forward")
	_world.close()
	await await_idle_frame()


func _add_box(center: Vector3, size: Vector3) -> void:
	## This function adds a solid box to the world
	# center: middle of the box
	# size: full size of the box
	var body = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	_world.root.add_child(body)
	body.global_position = center


func _add_ledge(height: float) -> void:
	## This function adds a raised block starting at LEDGE_X, running far in +x
	# height: how high its top is above the floor
	_add_box(Vector3(LEDGE_X + 5, height / 2, 0), Vector3(10, height, 10))


func _walk(seconds: float, me: CharacterBody3D) -> void:
	## This function holds W for a while, noting if the player ever leaves the floor
	# seconds: how long to walk
	# me: the player to watch
	var watch = func(): _left_floor = _left_floor or not me.on_floor # the grounded state animations and sounds use
	get_tree().physics_frame.connect(watch)
	Input.action_press("move_forward")
	await await_millis(int(seconds * 1000))
	Input.action_release("move_forward")
	await await_millis(75)
	get_tree().physics_frame.disconnect(watch)


func test_steps_up_a_low_ledge() -> void:
	_add_ledge(0.25)
	var me = _world.add_player(1, Vector3(0, 0.05, 0), FACE_OUT)
	await await_millis(100)
	await _walk(1.0, me)
	assert_float(me.global_position.x).is_greater(LEDGE_X + 0.5)
	assert_float(me.global_position.y).is_equal_approx(0.25, 0.05)
	assert_bool(_left_floor).is_false() # no fall animation or land sound on the step


func test_tall_ledge_still_blocks() -> void:
	_add_ledge(0.6)
	var me = _world.add_player(1, Vector3(0, 0.05, 0), FACE_OUT)
	await await_millis(100)
	await _walk(1.0, me)
	assert_float(me.global_position.x).is_less(LEDGE_X)
	assert_float(me.global_position.y).is_less(0.1)


func test_steps_down_without_falling() -> void:
	_add_ledge(0.25)
	# standing on the ledge, walking off its far end (x = LEDGE_X + 10) onto the floor
	var me = _world.add_player(1, Vector3(LEDGE_X + 9, 0.3, 0), FACE_OUT)
	await await_millis(150)
	assert_bool(me.on_floor).is_true()
	await _walk(0.6, me)
	assert_float(me.global_position.x).is_greater(LEDGE_X + 10.5)
	assert_float(me.global_position.y).is_less(0.05)
	assert_bool(_left_floor).is_false()
