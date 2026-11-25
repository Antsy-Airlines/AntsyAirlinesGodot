extends GdUnitTestSuite
## Crates on their own: who holds them, when they count as lifted, when they are solid, and where they float.

# Getting References for the scenes under test
const TestWorld := preload("res://test/helpers/test_world.gd") # current scene with players
const LightCrate := preload("res://scenes/props/cargo_crate.tscn") # normal crate
const HeavyCrate := preload("res://scenes/props/heavy_crate.tscn") # two-player crate
const CrateScript := preload("res://scripts/props/cargo_crate.gd") # CARRY_OFF, HEAVY_LIFT, SOLID_LAYER

# Declaring tracking variables
var _world # TestWorld without the airport, made fresh for each test


func before_test() -> void:
	_world = TestWorld.new(false)


func after_test() -> void:
	_world.close()
	await await_idle_frame()


func _add(scene: PackedScene) -> Node3D:
	## This function puts a crate into the test world
	# scene: light or heavy crate
	var crate = scene.instantiate()
	_world.root.add_child(crate)
	return crate


func test_new_crates_sit_on_the_ground() -> void:
	for scene in [LightCrate, HeavyCrate]:
		var crate = _add(scene)
		assert_int(crate.holder_id).is_equal(0)
		assert_int(crate.helper_id).is_equal(0)
		assert_bool(crate.is_lifted()).is_false()
		assert_bool(crate.loaded).is_false()
	assert_bool(_add(LightCrate).heavy).is_false()
	assert_bool(_add(HeavyCrate).heavy).is_true()


func test_light_crate_lifts_with_one_holder() -> void:
	var crate = _add(LightCrate)
	crate.set_holders(5)
	assert_bool(crate.is_lifted()).is_true()
	assert_int(crate.collision_layer).is_equal(0) # not solid while carried


func test_heavy_crate_needs_both_sides() -> void:
	var crate = _add(HeavyCrate)

	# one side held: still on the ground and solid
	crate.set_holders(5)
	assert_bool(crate.is_lifted()).is_false()
	assert_int(crate.collision_layer).is_equal(CrateScript.SOLID_LAYER)

	# both sides held: lifted and not solid
	crate.set_holders(5, 6)
	assert_bool(crate.is_lifted()).is_true()
	assert_int(crate.collision_layer).is_equal(0)


func test_place_lets_go_and_moves_the_crate() -> void:
	var crate = _add(HeavyCrate)
	crate.set_holders(5, 6)
	var spot = Transform3D(Basis(Vector3.UP, 0.5), Vector3(3, 1, -2))
	crate.place(spot)

	assert_int(crate.holder_id).is_equal(0)
	assert_int(crate.helper_id).is_equal(0)
	assert_vector(crate.global_position).is_equal_approx(spot.origin, Vector3.ONE * 0.001)

	# see-through for a moment, then solid once it knows nobody stands there
	assert_bool(crate.settling).is_true()
	assert_int(crate.collision_layer).is_equal(0)
	await await_millis(50)
	assert_bool(crate.settling).is_false()
	assert_int(crate.collision_layer).is_equal(CrateScript.SOLID_LAYER)


func test_crate_put_down_on_a_player_waits_for_them_to_step_off() -> void:
	# a floor, so the player stands still instead of falling out of the crate
	var floor_body = StaticBody3D.new()
	var floor_shape = CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(40, 1, 40)
	floor_body.add_child(floor_shape)
	_world.root.add_child(floor_body)
	floor_body.global_position = Vector3(10, -0.5, 10)

	var crate = _add(LightCrate)
	var player = _world.add_player(5, Vector3(10, 0, 10))
	await await_millis(50) # letting physics register the new player first
	crate.place(Transform3D(Basis(), Vector3(10, 0, 10)))
	await await_millis(75)
	assert_int(crate.collision_layer).is_equal(0)

	_world.place(player, Vector3(14, 0, 10))
	await await_millis(75)
	assert_int(crate.collision_layer).is_equal(CrateScript.SOLID_LAYER)


func test_picking_up_a_settling_crate_stops_it_settling() -> void:
	var crate = _add(LightCrate)
	crate.place(Transform3D())
	crate.set_holders(5)
	assert_bool(crate.settling).is_false()
	assert_int(crate.collision_layer).is_equal(0)


func test_light_crate_floats_in_front_of_its_holder() -> void:
	var holder = _world.add_marker(5, Vector3(10, 0, 4), 90.0)
	var crate = _add(LightCrate)
	crate.set_holders(5)
	await await_millis(50)

	var want = holder.global_transform * CrateScript.CARRY_OFF
	assert_vector(crate.global_position).is_equal_approx(want, Vector3.ONE * 0.01)


func test_heavy_crate_floats_between_its_carriers() -> void:
	_world.add_marker(5, Vector3(0, 0, 0))
	_world.add_marker(6, Vector3(2, 0, 0))
	var crate = _add(HeavyCrate)
	crate.set_holders(5, 6)
	await await_millis(50)

	var want = Vector3(1, CrateScript.HEAVY_LIFT, 0)
	assert_vector(crate.global_position).is_equal_approx(want, Vector3.ONE * 0.01)


func test_heavy_crate_with_one_side_held_does_not_move() -> void:
	_world.add_marker(5, Vector3(4, 0, 4))
	var crate = _add(HeavyCrate)
	var start = crate.global_position
	crate.set_holders(5)
	await await_millis(50)
	assert_vector(crate.global_position).is_equal(start)


func test_crate_waits_for_a_holder_that_is_not_here() -> void:
	# a holder who left (or has not loaded yet) leaves the crate where it was, no errors
	var crate = _add(LightCrate)
	var start = crate.global_position
	crate.set_holders(777)
	await await_millis(50)
	assert_vector(crate.global_position).is_equal(start)
