extends GdUnitTestSuite
## Plane seats without a network: the E hint, sitting down (posed, held in place, sit animation), getting up with
## Jump without jumping, where players stand after getting up (in front in the cabin, behind in the cockpit),
## the fading hint, the head following the look, and seats freeing up when their player leaves.

# Getting References for the helpers
const TestWorld := preload("res://test/helpers/test_world.gd") # current scene, no airport
const PLANE_SCENE := preload("res://scenes/Plane.tscn") # the plane with its seats

# Declaring tracking variables
var _world # fresh world for each test
var _plane: Airplane # the plane in it


func before_test() -> void:
	_world = TestWorld.new(false)
	_plane = PLANE_SCENE.instantiate()
	_world.root.add_child(_plane)
	await await_millis(50)


func after_test() -> void:
	Input.action_release("jump")
	Input.action_release("move_forward")
	_world.close()
	await await_idle_frame()


func _seat(seat_name: String) -> Seat:
	return _plane.get_node("Seats/" + seat_name)


func _sit(seat_name: String) -> Array:
	## This function adds our player in front of a seat and sits them in it, giving [player, seat]
	# seat_name: like "Row2L" or "PilotL"
	var seat = _seat(seat_name)
	var me = _world.add_player(1, seat.exit_transform().origin)
	await await_millis(50)
	seat.interact(1)
	await await_millis(50)
	return [me, seat]


func _press_jump() -> void:
	Input.action_press("jump")
	await await_millis(50)
	Input.action_release("jump")


func test_every_seat_faces_forward_at_the_same_height() -> void:
	var seats = _plane.get_node("Seats").get_children()
	assert_int(seats.size()).is_equal(14)
	var height = _plane.to_local(seats[0].global_position).y
	for seat in seats:
		assert_vector(_plane.global_basis.inverse() * seat.global_basis.z).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.001)
		assert_float(_plane.to_local(seat.global_position).y).override_failure_message("%s is out of line" % seat.name).is_equal_approx(height, 0.01)


func test_hint_only_in_reach() -> void:
	var seat = _seat("Row2L")
	var me = _world.add_player(1, seat.exit_transform().origin)
	await await_millis(50)
	assert_object(me.get_node("Interactor").target).is_same(seat)
	assert_str(me.get_node("Interactor").prompt).is_equal(seat.sit_prompt)

	_world.place(me, seat.to_global(Vector3(0, 0.05, 2.0)))
	await await_millis(50)
	assert_object(me.get_node("Interactor").target).is_not_same(seat)


func test_sitting_holds_the_player_and_plays_sit() -> void:
	var sat = await _sit("Row2L")
	var me = sat[0]
	var seat: Seat = sat[1]
	assert_int(seat.occupant).is_equal(1)
	assert_object(me.seat).is_same(seat)
	assert_vector(me.global_position).is_equal_approx(seat.sit_transform().origin, Vector3.ONE * 0.01)
	assert_str(me.animation_player.current_animation).is_equal("sit")

	# walking does nothing while seated
	Input.action_press("move_forward")
	await await_millis(300)
	Input.action_release("move_forward")
	assert_vector(me.global_position).is_equal_approx(seat.sit_transform().origin, Vector3.ONE * 0.01)


func test_jump_gets_up_without_jumping() -> void:
	var sat = await _sit("Row2L")
	var me = sat[0]
	var seat: Seat = sat[1]
	await _press_jump()
	assert_object(me.seat).is_null()
	assert_int(seat.occupant).is_equal(0)
	assert_float(me.velocity.y).is_less_equal(0.0)

	# standing in front of the seat, not flying up
	await await_millis(300)
	var spot = seat.to_local(me.global_position)
	assert_float(spot.z).is_greater(0.8)
	assert_float(spot.y).is_less(0.3)


func test_pilots_get_up_behind_their_seat() -> void:
	var sat = await _sit("PilotL")
	var me = sat[0]
	var seat: Seat = sat[1]
	await _press_jump()
	assert_float(seat.to_local(me.global_position).z).is_less(-0.8)


func test_a_taken_seat_cannot_be_used() -> void:
	var seat = _seat("Row3R")
	var other = _world.add_player(2, seat.exit_transform().origin + Vector3(0.5, 0, 0))
	seat.interact(2)
	assert_object(other.seat).is_same(seat)

	var me = _world.add_player(1, seat.exit_transform().origin)
	await await_millis(50)
	assert_str(seat.get_prompt(me)).is_empty()
	me.get_node("Interactor")._request_interact(seat.get_path())
	assert_int(seat.occupant).is_equal(2)


func test_seated_pilot_can_reach_the_shift_handle() -> void:
	var sat = await _sit("PilotL")
	var me = sat[0]
	await await_millis(50)
	# the seat offers nothing to the one sitting in it, so E goes to the controls
	assert_object(me.get_node("Interactor").target).is_same(_plane.shift_handle)


func test_stand_up_hint_shows_then_fades() -> void:
	var sat = await _sit("Row2L")
	var me = sat[0]
	var hint = me.get_node("SeatHint")
	var panel = hint.get_node("%HintPanel")
	assert_bool(panel.visible).is_true()
	assert_str(panel.get_node("Hint").text).contains("Space")

	await await_millis(int((hint.hold_time + hint.fade_time) * 1000) + 200)
	assert_bool(panel.visible).is_false()


func test_head_follows_the_look_and_resets_on_standing() -> void:
	var sat = await _sit("Row2L")
	var me = sat[0]
	var camera = me.get_node("CameraPivot")
	var skeleton: Skeleton3D = me.get_node("CharacterMesh/Armature/Skeleton3D")
	var head_look: HeadLook = skeleton.get_node("HeadLook")
	var body_rot = me.quaternion

	# looking left turns the view, not the body, and the head is told the same look
	camera.look_seated(0.6)
	assert_float(me.head_look.x).is_equal_approx(0.6, 0.001)
	assert_float(me.quaternion.angle_to(body_rot)).is_less(0.001)

	# the head's forward (+Z) points where the camera looks (the camera looks down its -Z);
	# modifiers only hold their pose during the skeleton update, so it is read from there
	var head = skeleton.find_bone(head_look.head_bone)
	var seen = [Vector3.ZERO]
	var read_head = func(): seen[0] = (skeleton.global_basis * skeleton.get_bone_global_pose(head).basis.z).normalized()
	skeleton.skeleton_updated.connect(read_head)
	await await_millis(100)
	skeleton.skeleton_updated.disconnect(read_head)
	var view_forward = -camera.global_basis.z.normalized()
	# yaw matches the view; the sit animation nods the head a little, so only the sideways turn is compared
	var flat_head = Vector3(seen[0].x, 0, seen[0].z).normalized()
	var flat_view = Vector3(view_forward.x, 0, view_forward.z).normalized()
	assert_float(rad_to_deg(flat_head.angle_to(flat_view))).is_less(1.0)

	# the look stops at the limit
	camera.look_seated(10.0)
	assert_float(rad_to_deg(me.head_look.x)).is_equal_approx(camera.seated_max_yaw_degrees, 0.01)

	# getting up turns the body to where we looked and squares the head up
	await _press_jump()
	assert_vector(me.head_look).is_equal(Vector2.ZERO)
	assert_float(rad_to_deg(me.quaternion.angle_to(body_rot))).is_equal_approx(camera.seated_max_yaw_degrees, 0.5)


func test_seated_view_sits_above_the_torso_and_returns_on_standing() -> void:
	var sat = await _sit("Row2L")
	var me = sat[0]
	var camera = me.get_node("CameraPivot")
	var standing = camera._standing_position
	await await_millis(100)

	# the view hangs off the torso bone, so it follows the sit pose rather than the player's origin
	var skeleton: Skeleton3D = me.get_node("CharacterMesh/Armature/Skeleton3D")
	var torso = me.to_local(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(camera.TORSO_BONE)).origin))
	# (the sit loop moves a little between the camera's frame and ours)
	assert_vector(camera.position).is_equal_approx(camera.seated_eye_position(), Vector3.ONE * 0.05)
	assert_float(camera.position.y - torso.y).is_equal_approx(camera.SEATED_EYE_OFFSET.y, 0.05)

	await _press_jump()
	assert_vector(camera.position).is_equal_approx(standing, Vector3.ONE * 0.001)


func test_leaving_the_game_frees_the_seat() -> void:
	var sat = await _sit("Row4R")
	var me = sat[0]
	var seat: Seat = sat[1]
	seat._on_peer_disconnected(1)
	assert_int(seat.occupant).is_equal(0)
	assert_object(me.seat).is_null()


func test_seated_player_moves_with_the_plane() -> void:
	var sat = await _sit("Row5L")
	var me = sat[0]
	var seat: Seat = sat[1]
	_plane.global_position += Vector3(5, 1, 0)
	await await_millis(100)
	assert_vector(me.global_position).is_equal_approx(seat.sit_transform().origin, Vector3.ONE * 0.01)


func test_late_joiner_poses_a_player_who_spawns_after_the_seat_state() -> void:
	# the server's answer arrives before the seated player has spawned on this computer
	var seat = _seat("Row6L")
	seat._apply_state(2)
	await await_millis(50)
	var other = _world.add_player(2, seat.exit_transform().origin)
	await await_millis(50)
	assert_object(other.seat).is_same(seat)
