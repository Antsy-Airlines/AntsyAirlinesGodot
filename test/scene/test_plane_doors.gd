extends GdUnitTestSuite
## Plane doors without a network: the E hint, opening outward about the hinge, the handle turning on its own axis
## (and keeping its scale), closing again, the cargo ramp lowering to the ground, and the Interactor picking the nearest thing.
## Also the open and close sounds: the right one for each part, played from the part, delayed by its offset, and silent on a late-join snap.

# Getting References for the helpers
const TestWorld := preload("res://test/helpers/test_world.gd") # current scene, no airport
const PLANE_SCENE := preload("res://scenes/Plane.tscn") # the plane with its doors

# Declaring Default/Const variables
const DOORS := ["FrontDoorL", "FrontDoorR", "WingDoorL", "WingDoorR"]
const DOOR_WIDTH := 2.0 # metres from the hinge to the far edge (along the door's -z)
const GROUND_Y := -3.4 # plane space: the bottom of the landing gear wheels
const RAMP_TIP := Vector3(0, -3.54, -2.96) # cargo ramp space: the end away from the hinge

# Declaring tracking variables
var _world # fresh world for each test
var _plane: Node3D # the plane in it


func before_test() -> void:
	_world = TestWorld.new(false)
	_plane = PLANE_SCENE.instantiate()
	_world.root.add_child(_plane)
	await await_millis(50)


func after_test() -> void:
	_world.close()
	await await_idle_frame()


func _door(door_name: String) -> PlaneDoor:
	return _plane.get_node("Doors/" + door_name)


func _beside(door: PlaneDoor, metres: float) -> Vector3:
	## This function gives a spot on the floor outside a door, some metres out from its handle
	# door: which door
	# metres: how far out from the handle
	var handle = door.handle.global_position
	var out = signf(door.door.global_position.x - _plane.global_position.x) # left doors are on +x
	return Vector3(handle.x + out * metres, handle.y - 1.0, handle.z)


func _far_edge_x(door: PlaneDoor) -> float:
	## This function says how far the door's free edge sits from the plane's middle, sideways
	# door: which door
	return absf(_plane.to_local(door.door.to_global(Vector3(0, 0, -DOOR_WIDTH))).x)


func test_hint_only_in_reach() -> void:
	var door = _door("FrontDoorL")
	var me = _world.add_player(1, _beside(door, 1.0))
	await await_millis(50)
	assert_str(me.get_node("Interactor").prompt).is_equal(door.open_prompt)

	_world.place(me, _beside(door, 6.0))
	await await_millis(50)
	assert_str(me.get_node("Interactor").prompt).is_empty()


func test_every_door_swings_outward_and_closes() -> void:
	for door_name in DOORS:
		var door = _door(door_name)
		var closed_edge = _far_edge_x(door)
		var closed_rot = door.door.quaternion

		door.interact(1)
		assert_bool(door.is_open).is_true()
		await await_millis(int(door.open_time * 1000) + 150)

		# a quarter turn about its hinge, with the free edge now further out from the fuselage
		assert_float(rad_to_deg(closed_rot.angle_to(door.door.quaternion))).is_equal_approx(90.0, 1.0)
		assert_float(_far_edge_x(door)).override_failure_message("%s swung inward" % door_name).is_greater(closed_edge + 1.0)

		door.interact(1)
		await await_millis(int(door.open_time * 1000) + 150)
		assert_bool(door.is_open).is_false()
		assert_float(rad_to_deg(closed_rot.angle_to(door.door.quaternion))).is_less(0.5)


func test_handle_turns_on_its_own_axis_and_keeps_its_scale() -> void:
	# the right doors' handles are scaled unevenly, so a wrong rotation would stretch them
	for door_name in ["FrontDoorL", "FrontDoorR"]:
		var door = _door(door_name)
		var scale_before = door.handle.scale
		var pos_before = door.handle.position
		var closed_rot = door.handle.quaternion

		# halfway through the swing the handle is turned the most, about its own x axis
		door._pose(0.5)
		var turn = closed_rot.inverse() * door.handle.quaternion
		assert_float(rad_to_deg(turn.get_angle())).is_equal_approx(door.handle_angle_deg, 0.5)
		assert_vector(turn.get_axis().abs()).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 0.01)
		assert_vector(door.handle.scale).is_equal_approx(scale_before, Vector3.ONE * 0.001)
		assert_vector(door.handle.position).is_equal_approx(pos_before, Vector3.ONE * 0.001)

		# fully open, it is back to how it sat
		door._pose(1.0)
		assert_float(rad_to_deg(closed_rot.angle_to(door.handle.quaternion))).is_less(0.5)


func test_pressing_e_goes_through_the_interactor() -> void:
	var door = _door("WingDoorR")
	var me = _world.add_player(1, _beside(door, 1.0))
	await await_millis(50)
	assert_object(me.get_node("Interactor").target).is_same(door)

	# the same call a client's E press makes, run locally since we are the server offline
	me.get_node("Interactor")._request_interact(door.get_path())
	assert_bool(door.is_open).is_true()


func test_server_refuses_a_door_out_of_reach() -> void:
	var door = _door("WingDoorL")
	var me = _world.add_player(1, _beside(door, 6.0))
	await await_millis(50)
	me.get_node("Interactor")._request_interact(door.get_path())
	assert_bool(door.is_open).is_false()


func test_nearest_door_wins() -> void:
	# standing between the two left doors, closer to the wing door
	var front = _door("FrontDoorL")
	var wing = _door("WingDoorL")
	var spot = _beside(wing, 1.0).lerp(_beside(front, 1.0), 0.1)
	var me = _world.add_player(1, spot)
	await await_millis(50)
	assert_object(me.get_node("Interactor").target).is_same(wing)


func test_cargo_ramp_lowers_to_the_ground_and_back() -> void:
	var ramp = _door("CargoDoor")
	assert_object(ramp.handle).is_null() # the ramp has no handle, the same script copes without one
	var tip_closed = _plane.to_local(ramp.door.to_global(RAMP_TIP))

	ramp.interact(1)
	await await_millis(int(ramp.open_time * 1000) + 150)
	var tip_open = _plane.to_local(ramp.door.to_global(RAMP_TIP))
	assert_float(tip_open.y).is_between(GROUND_Y - 0.05, GROUND_Y + 0.3) # resting just on the ground
	assert_float(tip_open.z).is_less(tip_closed.z) # still out behind the plane
	assert_str(ramp.get_prompt(null)).is_equal(ramp.close_prompt)

	ramp.interact(1)
	await await_millis(int(ramp.open_time * 1000) + 150)
	assert_vector(_plane.to_local(ramp.door.to_global(RAMP_TIP))).is_equal_approx(tip_closed, Vector3.ONE * 0.01)


func test_cargo_ramp_is_usable_from_the_ground_behind_the_tail() -> void:
	# standing on the ground under the tail, far below the ramp itself (no jumping needed)
	var ramp = _door("CargoDoor")
	var me = _world.add_player(1, _plane.to_global(Vector3(-1.315, GROUND_Y, -20.0)))
	await await_millis(50)
	assert_object(me.get_node("Interactor").target).is_same(ramp)
	assert_str(me.get_node("Interactor").prompt).is_equal(ramp.open_prompt)

	# walking well away from both reach points: no prompt
	_world.place(me, _plane.to_global(Vector3(-1.315, GROUND_Y, -26.0)))
	await await_millis(50)
	assert_str(me.get_node("Interactor").prompt).is_empty()


func _part(path: String) -> PlaneDoor:
	## This function finds a door or control on the plane by its path
	# path: e.g. "Doors/CargoDoor" or "Controls/ShiftHandle"
	return _plane.get_node(path)


func test_every_part_plays_its_open_and_close_sound() -> void:
	var fuselage_open = load("res://assets/plane/Sounds/fuselage_door_open.mp3")
	var fuselage_close = load("res://assets/plane/Sounds/fuselage_door_close.mp3")
	var lever = load("res://assets/plane/Sounds/mechanical_lever.mp3")
	var expected = {
		"Doors/FrontDoorL": [fuselage_open, fuselage_close],
		"Doors/FrontDoorR": [fuselage_open, fuselage_close],
		"Doors/WingDoorL": [fuselage_open, fuselage_close],
		"Doors/WingDoorR": [fuselage_open, fuselage_close],
		"Doors/CargoDoor": [load("res://assets/plane/Sounds/cargo_door_open.mp3"), load("res://assets/plane/Sounds/cargo_door_close.mp3")],
		"Controls/ShiftHandle": [lever, lever],
	}
	for path in expected:
		var part = _part(path)
		part.open_sound_offset = 0.0 # the tuned offsets would delay the sounds past these checks
		part.close_sound_offset = 0.0
		part.interact(1)
		assert_object(part.audio_player.stream).override_failure_message("%s open sound" % path).is_same(expected[path][0])
		assert_bool(part.audio_player.playing).override_failure_message("%s not playing" % path).is_true()
		await await_millis(int(part.open_time * 1000) + 100)

		part.interact(1)
		assert_object(part.audio_player.stream).override_failure_message("%s close sound" % path).is_same(expected[path][1])
		assert_bool(part.audio_player.playing).is_true()
		await await_millis(int(part.open_time * 1000) + 100)


func test_sound_comes_from_the_part() -> void:
	for path in ["Doors/FrontDoorL", "Doors/WingDoorR", "Doors/CargoDoor", "Controls/ShiftHandle"]:
		var part = _part(path)
		var distance = part.audio_player.global_position.distance_to(part.door.global_position)
		assert_float(distance).override_failure_message("%s sound is %.1f m away" % [path, distance]).is_less(3.0)


func test_positive_offset_waits_before_playing() -> void:
	var door = _door("FrontDoorL")
	door.open_sound_offset = 0.3
	door.interact(1)
	assert_bool(door.audio_player.playing).is_false()
	await await_millis(450)
	assert_bool(door.audio_player.playing).is_true()


func test_turning_around_cancels_a_waiting_sound() -> void:
	var door = _door("FrontDoorL")
	door.open_sound_offset = 0.5
	door.close_sound_offset = 0.0
	door.interact(1)
	door.interact(1) # closes again before the open sound started
	assert_object(door.audio_player.stream).is_same(door.close_sound)
	await await_millis(650)
	assert_object(door.audio_player.stream).is_same(door.close_sound)


func test_late_join_snap_is_silent() -> void:
	var door = _door("CargoDoor")
	door._apply_state(true)
	assert_bool(door.audio_player.playing).is_false()
