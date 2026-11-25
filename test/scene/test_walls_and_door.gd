extends GdUnitTestSuite
## Walking around terminal 1 with a real player: the glass blocks both ways, and the sliding door and ramp let you out and back in.

# Getting References for the helpers
const TestWorld := preload("res://test/helpers/test_world.gd") # current scene with the airport

# Declaring Default/Const variables
const GLASS_X := -78.5 # x of the airside glass of terminal 1
const DOOR_Z := -28.86 # z of the middle of the sliding door
const FACE_OUT := 90.0 # yaw that faces +x (out towards the planes)
const FACE_IN := -90.0 # yaw that faces -x (back into the terminal)

# Declaring tracking variables
var _world # fresh airport for each test, so players do not carry over


func before_test() -> void:
	_world = TestWorld.new()
	await await_millis(50)


func after_test() -> void:
	Input.action_release("move_forward")
	_world.close()
	await await_idle_frame()


func _walk(seconds: float) -> void:
	## This function holds W for a while (only player "1", ours, listens)
	# seconds: how long to walk
	Input.action_press("move_forward")
	await await_millis(int(seconds * 1000))
	Input.action_release("move_forward")
	await await_millis(75)


func _door() -> Node3D:
	return _world.airport.get_node("Terminal1Entrance/SlidingDoor")


func _is_open() -> bool:
	## This function says if the left panel of the door has slid away from where it sits closed
	var door = _door()
	return door.get_node("LeftPanel").position.distance_to(door._left_closed) > door.slide_distance * 0.9


func _is_closed() -> bool:
	var door = _door()
	return door.get_node("LeftPanel").position.distance_to(door._left_closed) < 0.01


func test_glass_blocks_walking_out() -> void:
	var me = _world.add_player(1, Vector3(-81, 0.45, -14), FACE_OUT)
	await _walk(1.5)
	assert_float(me.global_position.x).is_less(GLASS_X)


func test_glass_blocks_walking_in() -> void:
	# standing on the platform outside the glass, walking at it
	var me = _world.add_player(1, Vector3(-76.5, 0.45, -14), FACE_IN)
	await _walk(1.5)
	assert_float(me.global_position.x).is_greater(GLASS_X)


func test_walk_out_through_the_door_and_back_in() -> void:
	var me = _world.add_player(1, Vector3(-83, 0.45, DOOR_Z), FACE_OUT)

	# out through the door and down the ramp to the apron
	await _walk(3.0)
	assert_float(me.global_position.x).is_greater(-70.0)
	assert_float(me.global_position.y).is_less(0.3)

	# turning around: up the ramp and back inside
	_world.place(me, me.global_position, FACE_IN)
	await _walk(3.0)
	assert_float(me.global_position.x).is_less(GLASS_X - 1.0)
	assert_float(me.global_position.y).is_equal_approx(0.42, 0.1)


func test_door_opens_for_a_player_and_closes_after() -> void:
	assert_bool(_is_closed()).is_true()

	var me = _world.add_player(1, Vector3(-77, 0.45, DOOR_Z), FACE_OUT)
	await await_millis(700)
	assert_bool(_is_open()).is_true()

	_world.place(me, Vector3(-88, 0.45, DOOR_Z))
	await await_millis(700)
	assert_bool(_is_closed()).is_true()


func test_door_stays_open_until_the_last_player_leaves() -> void:
	var one = _world.add_player(1, Vector3(-77, 0.45, DOOR_Z - 1), FACE_OUT)
	var two = _world.add_player(2, Vector3(-77, 0.45, DOOR_Z + 1), FACE_OUT)
	await await_millis(700)
	assert_bool(_is_open()).is_true()

	# one walks off: still open for the other
	_world.place(one, Vector3(-88, 0.45, DOOR_Z))
	await await_millis(700)
	assert_bool(_is_open()).is_true()

	_world.place(two, Vector3(-88, 0.45, DOOR_Z + 2))
	await await_millis(700)
	assert_bool(_is_closed()).is_true()


func test_door_closes_when_a_player_leaves_the_game_in_it() -> void:
	var me = _world.add_player(1, Vector3(-77, 0.45, DOOR_Z), FACE_OUT)
	await await_millis(700)
	assert_bool(_is_open()).is_true()

	me.queue_free() # like the spawner removing a player who left
	await await_millis(700)
	assert_bool(_is_closed()).is_true()


func test_door_ignores_crates() -> void:
	var crate = _world.crate("Crate1")
	crate.place(Transform3D(Basis(), Vector3(-77, 0.42, DOOR_Z)))
	await await_millis(700)
	assert_bool(_is_closed()).is_true()
