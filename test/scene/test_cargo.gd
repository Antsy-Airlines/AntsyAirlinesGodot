extends GdUnitTestSuite
## Cargo in the real airport without a network: picking up, dropping, loading, heavy crates and their edge cases.
## cargo.interact(id) is what the server runs when player <id> presses E (through their Interactor).

# Getting References for the helpers
const TestWorld := preload("res://test/helpers/test_world.gd") # current scene with the airport
const ManagerScript := preload("res://scripts/gameplay/cargo_manager.gd") # the cargo constants

# Declaring Default/Const variables
const FACE_OUT := 90.0 # yaw that faces +x
const PAD := Vector3(-37, 0.05, -35) # middle of the hold pad
const PAD_LEFT := Vector3(-38.5, 0.05, -35) # standing just left of the middle, facing +x so drops land on the pad

# Declaring tracking variables
var _world # fresh airport for each test
var _cargo # its cargo manager
var _counts: Array # every "loaded/total" the manager announced


func before_test() -> void:
	_world = TestWorld.new()
	_cargo = _world.cargo()
	_counts = []
	_cargo.cargo_changed.connect(func(l, t): _counts.append("%d/%d" % [l, t]))
	await await_millis(50)


func after_test() -> void:
	_world.close()
	await await_idle_frame()


func _next_to(crate_name: String, side: float = -1.0) -> Vector3:
	## This function gives a spot to stand beside a crate, on its -x side (or +x with side = 1)
	# crate_name: which crate
	# side: -1 for the -x side, 1 for the +x side
	var crate = _world.crate(crate_name)
	var gap = 1.5 if crate.heavy else 1.0
	return crate.global_position + Vector3(gap * side, 0.03, 0)


func _prompt() -> String:
	## This function gives the E hint our own player (1) sees right now
	return _world.root.get_node("1/Interactor").prompt


func _floor_under(spot: Vector3) -> float:
	## This function gives the floor height under a spot
	# spot: point to look under
	var query = PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 2, spot + Vector3.DOWN * 4)
	# skipping players, so the ray only finds the floor
	for node in _world.root.get_children():
		if node is CharacterBody3D:
			query.exclude.append(node.get_rid())
	var hit = _world.airport.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if hit else -100.0


# ---------------- light crates ----------------

func test_no_hint_with_nothing_in_reach() -> void:
	_world.add_player(1, _world.airport.get_spawn(0).origin)
	await await_millis(50)
	assert_str(_prompt()).is_empty()


func test_pick_up_and_drop_a_crate() -> void:
	var me = _world.add_player(1, _next_to("Crate1"), FACE_OUT)
	await await_millis(50)
	assert_str(_prompt()).is_equal("Press E to pick up")

	# picking up: we hold it, it is not solid, and it floats with us
	_cargo.interact(1)
	var crate = _world.crate("Crate1")
	assert_int(crate.holder_id).is_equal(1)
	assert_int(crate.collision_layer).is_equal(0)
	await await_millis(50)
	assert_str(_prompt()).is_equal("Press E to drop the crate")

	# dropping inside the terminal: on the floor, in front of us, solid again
	_world.place(me, Vector3(-90, 0.45, -20), FACE_OUT)
	await await_millis(50)
	_cargo.interact(1)
	await await_millis(50)
	assert_int(crate.holder_id).is_equal(0)
	assert_bool(crate.loaded).is_false()
	assert_float(crate.global_position.y).is_equal_approx(0.42, 0.05)
	assert_float(crate.global_position.x).is_greater(-90.0)
	assert_int(crate.collision_layer).is_equal(1)


func test_load_a_crate_on_the_pad() -> void:
	var me = _world.add_player(1, _next_to("Crate1"), FACE_OUT)
	_cargo.interact(1)

	_world.place(me, PAD_LEFT, FACE_OUT)
	await await_millis(50)
	assert_str(_prompt()).is_equal("Press E to load the crate")
	_cargo.interact(1)

	var crate = _world.crate("Crate1")
	assert_bool(crate.loaded).is_true()
	assert_int(crate.holder_id).is_equal(0)
	assert_bool(_cargo._in_hold(crate.global_position)).is_true()
	assert_array(_counts).contains(["1/8"])


func test_a_loaded_crate_cannot_be_picked_up_again() -> void:
	var me = _world.add_player(1, _next_to("Crate1"), FACE_OUT)
	_cargo.interact(1)
	_world.place(me, PAD_LEFT, FACE_OUT)
	_cargo.interact(1)

	# standing right on top of it and pressing E again
	var crate = _world.crate("Crate1")
	_world.place(me, crate.global_position + Vector3(-1, 0.05, 0), FACE_OUT)
	await await_millis(50)
	assert_str(_prompt()).is_empty()
	_cargo.interact(1)
	assert_int(crate.holder_id).is_equal(0)
	assert_bool(crate.loaded).is_true()


func test_dropping_at_a_wall_keeps_the_crate_inside() -> void:
	# facing the glass from 0.8 m away: a normal drop spot would be past it
	var me = _world.add_player(1, _next_to("Crate1"), FACE_OUT)
	_cargo.interact(1)
	_world.place(me, Vector3(-79.3, 0.45, -14), FACE_OUT)
	await await_millis(50)
	_cargo.interact(1)

	var crate = _world.crate("Crate1")
	assert_float(crate.global_position.x + 0.4).is_less(-78.5) # its far side is still inside the glass
	assert_float(crate.global_position.y).is_equal_approx(0.42, 0.05)


func test_dropping_against_the_glass_does_not_shove_the_holder() -> void:
	# pressed up against the glass, the drop spot backs off onto us
	var me = _world.add_player(1, _next_to("Crate1"), FACE_OUT)
	_cargo.interact(1)
	_world.place(me, Vector3(-78.9, 0.45, -14), FACE_OUT)
	await await_millis(50)
	var before = me.global_position
	_cargo.interact(1)
	await await_millis(250)

	# we must not get shoved, and the crate waits for us to step off before it turns solid
	var crate = _world.crate("Crate1")
	assert_float(me.global_position.distance_to(before)).is_less(0.3)
	assert_int(crate.collision_layer).is_equal(0)

	_world.place(me, Vector3(-82, 0.45, -14), FACE_OUT)
	await await_millis(75)
	assert_int(crate.collision_layer).is_equal(1)


func test_pressing_e_near_another_crate_drops_ours_first() -> void:
	_world.add_player(1, _next_to("Crate1"), FACE_OUT)
	_cargo.interact(1)
	_cargo.interact(1) # Crate2 is right there too, but we only put Crate1 down
	assert_int(_world.crate("Crate1").holder_id).is_equal(0)
	assert_int(_world.crate("Crate2").holder_id).is_equal(0)


func test_two_players_cannot_take_the_same_crate() -> void:
	_world.add_player(1, _next_to("Crate1"), FACE_OUT)
	_world.add_player(2, _next_to("Crate1") + Vector3(0, 0, 0.6), FACE_OUT)
	_cargo.interact(1)
	_cargo.interact(2) # takes a different crate in reach, never Crate1
	assert_int(_world.crate("Crate1").holder_id).is_equal(1)
	var held_by_two = _world.airport.get_node("Cargo/Crates").get_children().filter(func(c): return c.holder_id == 2)
	assert_int(held_by_two.size()).is_less_equal(1)
	if held_by_two.size() == 1:
		assert_str(held_by_two[0].name).is_not_equal("Crate1")


func test_leaving_while_carrying_drops_the_crate() -> void:
	var me = _world.add_player(1, _next_to("Crate1"), FACE_OUT)
	_cargo.interact(1)
	_world.place(me, Vector3(-90, 0.45, -20), FACE_OUT)
	await await_millis(50)

	_cargo._on_player_left(1)
	var crate = _world.crate("Crate1")
	assert_int(crate.holder_id).is_equal(0)
	assert_float(crate.global_position.y).is_equal_approx(_floor_under(crate.global_position), 0.05)


# ---------------- heavy crates ----------------

func test_heavy_crate_cannot_be_lifted_alone() -> void:
	var me = _world.add_player(1, _next_to("HeavyCrate1"), FACE_OUT)
	await await_millis(50)
	assert_str(_prompt()).is_equal("Press E to grab (needs 2 players)")

	_cargo.interact(1)
	await await_millis(50)
	var crate = _world.crate("HeavyCrate1")
	assert_int(crate.holder_id).is_equal(1)
	assert_bool(crate.is_lifted()).is_false()
	assert_str(_prompt()).is_equal("Waiting for a second player (E to let go)")
	assert_float(me.speed_mul).is_equal(1.0)

	# pressing E again lets go
	_cargo.interact(1)
	assert_int(crate.holder_id).is_equal(0)


func test_two_players_lift_carry_and_load_a_heavy_crate() -> void:
	var me = _world.add_player(1, _next_to("HeavyCrate1"), FACE_OUT)
	var two = _world.add_player(2, _next_to("HeavyCrate1", 1.0), FACE_OUT)
	_cargo.interact(1)
	_cargo.interact(2)
	await await_millis(50)

	var crate = _world.crate("HeavyCrate1")
	assert_bool(crate.is_lifted()).is_true()
	assert_int(crate.helper_id).is_equal(2)
	assert_float(me.speed_mul).is_equal(ManagerScript.HEAVY_SPEED)

	# both walk to the pad, one on each side of its middle
	_world.place(me, PAD + Vector3(-1.2, 0, 0))
	_world.place(two, PAD + Vector3(1.2, 0, 0))
	await await_millis(50)
	assert_str(_prompt()).is_equal("Press E to load the crate")
	_cargo.interact(2)

	assert_bool(crate.loaded).is_true()
	assert_bool(_cargo._in_hold(crate.global_position)).is_true()
	await await_millis(50)
	assert_float(me.speed_mul).is_equal(1.0)


func test_heavy_crate_drops_when_carriers_walk_apart() -> void:
	_world.add_player(1, _next_to("HeavyCrate1"), FACE_OUT)
	var two = _world.add_player(2, _next_to("HeavyCrate1", 1.0), FACE_OUT)
	_cargo.interact(1)
	_cargo.interact(2)
	await await_millis(50)

	_world.place(two, two.global_position + Vector3(ManagerScript.HEAVY_BREAK + 1, 0, 0))
	await await_millis(75)
	var crate = _world.crate("HeavyCrate1")
	assert_bool(crate.is_lifted()).is_false()
	assert_int(crate.holder_id).is_equal(0)
	assert_float(crate.global_position.y).is_equal_approx(0.42, 0.05)


func test_heavy_crate_drops_when_a_carrier_leaves() -> void:
	_world.add_player(1, _next_to("HeavyCrate1"), FACE_OUT)
	_world.add_player(2, _next_to("HeavyCrate1", 1.0), FACE_OUT)
	_cargo.interact(1)
	_cargo.interact(2)
	_cargo._on_player_left(2)
	var crate = _world.crate("HeavyCrate1")
	assert_int(crate.holder_id).is_equal(0)
	assert_int(crate.helper_id).is_equal(0)


func test_a_player_carrying_a_light_crate_cannot_help_lift() -> void:
	_world.add_player(1, _next_to("HeavyCrate1"), FACE_OUT)
	_world.add_player(2, _next_to("Crate6", 1.0), FACE_OUT)
	_cargo.interact(2) # player 2 picks up a light crate
	assert_int(_world.crate("Crate6").holder_id).is_equal(2)
	_cargo.interact(1) # player 1 grabs the heavy one

	# player 2 walks over and presses E: that only puts their light crate down
	_world.place(_world.root.get_node("2"), _next_to("HeavyCrate1", 1.0), FACE_OUT)
	_cargo.interact(2)
	assert_int(_world.crate("HeavyCrate1").helper_id).is_equal(0)
	assert_int(_world.crate("Crate6").holder_id).is_equal(0)


func test_heavy_crate_put_down_does_not_trap_its_carriers() -> void:
	# carriers standing close together: the crate lands between them
	var me = _world.add_player(1, _next_to("HeavyCrate2"), FACE_OUT)
	var two = _world.add_player(2, _next_to("HeavyCrate2", 1.0), FACE_OUT)
	_cargo.interact(1)
	_cargo.interact(2)
	_world.place(me, Vector3(-88, 0.45, -20))
	_world.place(two, Vector3(-87, 0.45, -20))
	await await_millis(75)
	var before = me.global_position
	_cargo.interact(1)
	await await_millis(250)

	# nobody may end up inside the solid crate or get shoved far away
	var crate = _world.crate("HeavyCrate2")
	for p in [me, two]:
		var dif = crate.global_position - p.global_position
		var inside = absf(dif.x) < 0.6 and absf(dif.z) < 0.6
		assert_bool(inside and crate.collision_layer != 0).override_failure_message("%s is trapped inside the crate" % p.name).is_false()
	assert_float(me.global_position.distance_to(before)).is_less(0.5)

	# once both step away it is solid again
	_world.place(me, Vector3(-88, 0.45, -24))
	_world.place(two, Vector3(-85, 0.45, -24))
	await await_millis(75)
	assert_int(crate.collision_layer).is_equal(1)


# ---------------- the hold ----------------

func test_every_crate_fits_on_the_pad() -> void:
	# loading all 8, one after another
	var me = _world.add_player(1, PAD_LEFT, FACE_OUT)
	var two = _world.add_player(2, PAD_LEFT, FACE_OUT)
	for crate in _world.airport.get_node("Cargo/Crates").get_children():
		if crate.heavy:
			crate.set_holders(1, 2)
			_world.place(me, PAD + Vector3(-1.2, 0, 0))
			_world.place(two, PAD + Vector3(1.2, 0, 0))
			await await_millis(50)
		else:
			crate.set_holders(1)
			_world.place(me, PAD_LEFT, FACE_OUT)
		_cargo.interact(1)
		assert_bool(crate.loaded).override_failure_message("%s did not load" % crate.name).is_true()
	assert_str(_counts.back()).is_equal("8/8")

	# every crate on the pad, and no two crates overlapping
	var crates = _world.airport.get_node("Cargo/Crates").get_children()
	var half_pad = _cargo.hold_size / 2.0
	for a in crates:
		var local = _cargo.get_node("HoldZone").to_local(a.global_position)
		var half = 0.6 if a.heavy else 0.4
		assert_float(absf(local.x) + half).is_less_equal(half_pad.x)
		assert_float(absf(local.z) + half).is_less_equal(half_pad.y)
		for b in crates:
			if a == b:
				continue
			var dif = a.global_position - b.global_position
			var need = (0.6 if a.heavy else 0.4) + (0.6 if b.heavy else 0.4)
			assert_bool(absf(dif.x) < need and absf(dif.z) < need).override_failure_message("%s overlaps %s" % [a.name, b.name]).is_false()


func test_hold_edges() -> void:
	var hold = _cargo.get_node("HoldZone")
	var half = _cargo.hold_size / 2.0
	assert_bool(_cargo._in_hold(hold.global_position)).is_true()
	assert_bool(_cargo._in_hold(hold.to_global(Vector3(half.x - 0.05, 0, half.y - 0.05)))).is_true()
	assert_bool(_cargo._in_hold(hold.to_global(Vector3(half.x + 0.05, 0, 0)))).is_false()
	assert_bool(_cargo._in_hold(hold.to_global(Vector3(0, 0, -half.y - 0.05)))).is_false()


func test_hud_shows_the_count_and_the_hint() -> void:
	var hud = _cargo.get_node("CargoHud")
	await await_millis(50)
	assert_str(hud.get_node("%Counter").text).is_equal("Cargo 0/8 loaded")

	# the hint is the shared prompt on our own player, hidden until something is in reach
	var me = _world.add_player(1, _world.airport.get_spawn(0).origin)
	var prompt = me.get_node("Interactor/InteractionPrompt")
	await await_millis(50)
	assert_bool(prompt.get_node("%PromptPanel").visible).is_false()

	_world.place(me, _next_to("Crate1"), FACE_OUT)
	await await_millis(50)
	assert_bool(prompt.get_node("%PromptPanel").visible).is_true()
	assert_str(prompt.get_node("%Prompt").text).is_equal("Press E to pick up")
