extends GdUnitTestSuite
## Plane states without a network: the landing gear retracting and coming back, the propellers spinning up and
## stopping, opening doors through the setters, and the cockpit shift handle (which, for now, starts the
## propellers and retracts the gear).
## Also their sounds: the gear on both moves, the engines starting into a loop and stopping, and a late joiner hearing running engines.

# Getting References for the helpers
const TestWorld := preload("res://test/helpers/test_world.gd") # current scene, no airport
const PLANE_SCENE := preload("res://scenes/Plane.tscn") # the plane with its parts

# Declaring Default/Const variables
const COCKPIT_FLOOR := Vector3(-1.315, -0.55, 13.0) # plane space: standing between the pilot seats at the shift handle (closer than either seat)

# Declaring tracking variables
var _world # fresh world for each test
var _plane: Airplane # the plane in it


func before_test() -> void:
	_world = TestWorld.new(false)
	_plane = PLANE_SCENE.instantiate()
	_world.root.add_child(_plane)
	await await_millis(50)


func after_test() -> void:
	_world.close()
	await await_idle_frame()


func _wheels_bottom_y() -> float:
	## This function gives the lowest point of the wheels, in plane space
	var wheels: MeshInstance3D = _plane.landing_gear.wheels
	var box = _plane.global_transform.affine_inverse() * wheels.global_transform * wheels.mesh.get_aabb()
	return box.position.y


func _lever_tip() -> Vector3:
	## This function gives the top of the shift handle lever, in plane space
	var lever: MeshInstance3D = _plane.shift_handle.door
	var box = lever.mesh.get_aabb()
	return _plane.to_local(lever.to_global(Vector3(box.position.x, box.get_center().y, box.get_center().z)))


func test_gear_retracts_into_the_fuselage_and_back() -> void:
	var gear = _plane.landing_gear
	var wheels = gear.wheels
	var down_bottom = _wheels_bottom_y()
	var down_rot = wheels.quaternion
	var down_scale = wheels.scale

	_plane.set_gear_down(false)
	assert_bool(gear.is_down).is_false()
	await await_millis(int(gear.move_time * 1000) + 150)

	# straight up by the retract distance, without turning or stretching
	assert_float(_wheels_bottom_y()).is_equal_approx(down_bottom + gear.retract_distance, 0.01)
	assert_float(rad_to_deg(down_rot.angle_to(wheels.quaternion))).is_less(0.1)
	assert_vector(wheels.scale).is_equal_approx(down_scale, Vector3.ONE * 0.001)

	_plane.set_gear_down(true)
	await await_millis(int(gear.move_time * 1000) + 150)
	assert_bool(gear.is_down).is_true()
	assert_float(_wheels_bottom_y()).is_equal_approx(down_bottom, 0.01)


func test_propellers_spin_about_the_forward_axis_and_stop() -> void:
	var props = _plane.propellers
	var rest = []
	for blade in props.blades:
		rest.append(blade.quaternion)

	_plane.set_propellers_spinning(true)
	await await_millis(int(props.spin_up_time * 1000) + 150)
	assert_float(props.speed).is_equal_approx(props.max_speed, 0.001)

	for i in props.blades.size():
		var blade: Node3D = props.blades[i]
		# its hub's axis still points along the plane (it turns about it rather than wobbling)
		var axis = _plane.global_basis.inverse() * blade.global_basis.z
		assert_vector(axis.normalized().abs()).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.01)
		assert_float(rest[i].angle_to(blade.quaternion)).is_greater(0.0)

	_plane.set_propellers_spinning(false)
	await await_millis(int(props.spin_up_time * 1000) + 150)
	assert_float(props.speed).is_equal(0.0)

	# stopped means stopped: the blades no longer move
	var stopped = props.blades[0].quaternion
	await await_millis(100)
	assert_float(stopped.angle_to(props.blades[0].quaternion)).is_less(0.0001)


func test_door_setters_open_and_close_without_a_player() -> void:
	var door = _plane.get_door(&"FrontDoorL")
	_plane.set_door_open(&"FrontDoorL", true)
	assert_bool(door.is_open).is_true()

	# setting the same state again changes nothing
	_plane.set_door_open(&"FrontDoorL", true)
	assert_bool(door.is_open).is_true()

	_plane.set_all_doors_open(true)
	for child in _plane.doors_root.get_children():
		assert_bool(child.is_open).override_failure_message("%s stayed shut" % child.name).is_true()

	_plane.set_all_doors_open(false)
	for child in _plane.doors_root.get_children():
		assert_bool(child.is_open).override_failure_message("%s stayed open" % child.name).is_false()


func test_shift_handle_shows_its_prompt_in_the_cockpit() -> void:
	var handle = _plane.shift_handle
	var me = _world.add_player(1, _plane.to_global(COCKPIT_FLOOR))
	await await_millis(50)
	assert_object(me.get_node("Interactor").target).is_same(handle)
	assert_str(me.get_node("Interactor").prompt).is_equal(handle.open_prompt)


func test_shift_handle_tilts_forward_and_keeps_its_scale() -> void:
	var handle = _plane.shift_handle
	var lever = handle.door
	var tip_back = _lever_tip()
	var scale_before = lever.scale
	var pos_before = lever.position

	handle.interact(1)
	await await_millis(int(handle.open_time * 1000) + 150)

	# pushed forward (the cockpit is +z) about the axis across the plane, so it doesn't drift sideways
	var tip_forward = _lever_tip()
	assert_float(tip_forward.z).is_greater(tip_back.z + 0.05)
	assert_float(tip_forward.x).is_equal_approx(tip_back.x, 0.01)
	assert_vector(lever.scale).is_equal_approx(scale_before, Vector3.ONE * 0.001)
	assert_vector(lever.position).is_equal_approx(pos_before, Vector3.ONE * 0.001)

	handle.interact(1)
	await await_millis(int(handle.open_time * 1000) + 150)
	assert_vector(_lever_tip()).is_equal_approx(tip_back, Vector3.ONE * 0.001)


func test_shift_handle_starts_propellers_and_retracts_gear() -> void:
	# TEMPORARY hook: the handle drives the plane's states while there is no flight code yet
	var handle = _plane.shift_handle
	handle.interact(1)
	assert_bool(_plane.propellers.is_spinning).is_true()
	assert_bool(_plane.landing_gear.is_down).is_false()

	handle.interact(1)
	assert_bool(_plane.propellers.is_spinning).is_false()
	assert_bool(_plane.landing_gear.is_down).is_true()


func test_gear_plays_its_sound_both_ways() -> void:
	var gear = _plane.landing_gear
	_plane.set_gear_down(false)
	assert_object(gear.audio_player.stream).is_same(gear.raise_sound)
	assert_bool(gear.audio_player.playing).is_true()

	_plane.set_gear_down(true)
	assert_object(gear.audio_player.stream).is_same(gear.lower_sound)
	assert_bool(gear.audio_player.playing).is_true()


func test_engines_start_into_the_loop_and_stop() -> void:
	var props = _plane.propellers
	assert_int(props.audio_players.size()).is_equal(2)
	assert_bool(props.loop_sound.loop).override_failure_message("engine_loop.mp3 must be imported with loop on").is_true()

	_plane.set_propellers_spinning(true)
	for player in props.audio_players:
		assert_object(player.stream).is_same(props.start_sound)
		assert_bool(player.playing).is_true()
		player.stop()
		player.finished.emit() # as if the start sound had played out
		assert_object(player.stream).is_same(props.loop_sound)
		assert_bool(player.playing).is_true()

	_plane.set_propellers_spinning(false)
	for player in props.audio_players:
		assert_object(player.stream).is_same(props.stop_sound)
		player.stop()
		player.finished.emit() # the stop sound ending must not bring the loop back
		assert_bool(player.playing).is_false()


func test_engines_stopped_during_start_play_the_stop_sound() -> void:
	var props = _plane.propellers
	_plane.set_propellers_spinning(true)
	_plane.set_propellers_spinning(false)
	for player in props.audio_players:
		assert_object(player.stream).is_same(props.stop_sound)


func test_late_joiner_hears_running_engines_and_not_the_gear() -> void:
	var props = _plane.propellers
	props._apply_state(true)
	for player in props.audio_players:
		assert_object(player.stream).is_same(props.loop_sound)
		assert_bool(player.playing).is_true()

	_plane.landing_gear._apply_state(false)
	assert_bool(_plane.landing_gear.audio_player.playing).is_false()

	props._apply_state(false)
	for player in props.audio_players:
		assert_bool(player.playing).is_false()


func test_engine_sounds_come_from_the_propellers() -> void:
	var props = _plane.propellers
	for i in props.blades.size():
		var distance = props.audio_players[i].global_position.distance_to(props.blades[i].global_position)
		assert_float(distance).is_less(1.0)
