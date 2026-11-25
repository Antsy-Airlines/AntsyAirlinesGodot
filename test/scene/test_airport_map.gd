extends GdUnitTestSuite
## The airport map: spawn points, crates and the hold pad are where players can use them, and walls are solid.

# Getting References for the helpers
const TestWorld := preload("res://test/helpers/test_world.gd") # current scene with the airport

# Declaring Default/Const variables
const FLOOR_Y := 0.42 # terminal 1 floor height

# Declaring tracking variables
var _world # one airport for the whole suite (loading it takes a moment)


func before() -> void:
	_world = TestWorld.new()
	await await_millis(50)


func after() -> void:
	_world.close()
	await await_idle_frame()


func _ray_down(from: Vector3) -> Dictionary:
	## This function finds what is under a point
	# from: point to look down from
	var query = PhysicsRayQueryParameters3D.create(from + Vector3.UP, from + Vector3.DOWN * 4.0)
	return _world.airport.get_world_3d().direct_space_state.intersect_ray(query)


func _overlaps(shape: Shape3D, spot: Transform3D, skip: Array = []) -> Array:
	## This function lists what a shape placed somewhere would be inside of
	# shape: the shape to test
	# spot: where it goes
	# skip: bodies to ignore
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = spot
	query.exclude = skip
	var hits = _world.airport.get_world_3d().direct_space_state.intersect_shape(query)
	return hits.map(func(h): return str(h.collider.name))


func test_eight_spawn_points_on_the_terminal_floor() -> void:
	var spawns = _world.airport.get_node("SpawnPoints").get_children()
	assert_int(spawns.size()).is_equal(8)

	# a player-sized capsule at each spawn: floor right under it and nothing in the way
	var body = CapsuleShape3D.new()
	body.radius = 0.35
	body.height = 1.7
	for i in spawns.size():
		var spot = _world.airport.get_spawn(i)
		var hit = _ray_down(spot.origin)
		assert_dict(hit).is_not_empty()
		assert_float(hit.position.y).is_equal_approx(FLOOR_Y, 0.05)
		var in_the_way = _overlaps(body, Transform3D(Basis(), Vector3(spot.origin.x, FLOOR_Y + 0.9, spot.origin.z)))
		assert_array(in_the_way).override_failure_message("spawn %d is inside %s" % [i, in_the_way]).is_empty()


func test_spawn_slots_wrap_around() -> void:
	# a slot past the last spawn point reuses the first ones instead of crashing
	assert_vector(_world.airport.get_spawn(8).origin).is_equal(_world.airport.get_spawn(0).origin)


func test_every_crate_sits_on_the_floor_with_room_around_it() -> void:
	for crate in _world.cargo().get_node("Crates").get_children():
		var hit = _ray_down(crate.global_position + Vector3.UP * 0.1)
		assert_float(crate.global_position.y).is_equal_approx(FLOOR_Y, 0.05)

		# the box of the crate, a bit smaller so touching the floor does not count
		var box = BoxShape3D.new()
		var size = 1.2 if crate.heavy else 0.8
		box.size = Vector3.ONE * (size - 0.04)
		var in_the_way = _overlaps(box, Transform3D(Basis(), crate.global_position + Vector3.UP * size / 2.0), [crate.get_rid()])
		assert_array(in_the_way).override_failure_message("%s is inside %s" % [crate.name, in_the_way]).is_empty()


func test_crates_start_on_the_ground_and_free() -> void:
	var crates = _world.cargo().get_node("Crates").get_children()
	assert_int(crates.size()).is_equal(8)
	assert_int(crates.filter(func(c): return c.heavy).size()).is_equal(2)
	for crate in crates:
		assert_bool(crate.is_lifted() or crate.loaded).is_false()


func test_hold_pad_is_outside_on_the_ground() -> void:
	var hold = _world.cargo().get_node("HoldZone")
	var hit = _ray_down(hold.global_position + Vector3.UP * 0.5)
	assert_dict(hit).is_not_empty()
	assert_float(hit.position.y).is_equal_approx(0.0, 0.05) # apron level, not inside the terminal


func test_terminal_walls_block_from_both_sides() -> void:
	# the walls from the pack were one-sided at first; every terminal collider must block both ways
	var shapes = _world.airport.find_children("*", "CollisionShape3D", true, false)
	var concave = shapes.filter(func(s): return s.shape is ConcavePolygonShape3D)
	assert_int(concave.size()).is_greater(0)
	for s in concave:
		assert_bool(s.shape.backface_collision).override_failure_message("%s is one-sided" % s.get_path()).is_true()
