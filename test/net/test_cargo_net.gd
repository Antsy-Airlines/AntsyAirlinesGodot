extends "res://test/helpers/net_suite.gd"
## Cargo over the network: two (or three) bot players in a started game. The server decides,
## and every computer must end up showing the same crates in the same places.

# Declaring Default/Const variables
const INSIDE := "-90 0.45 -20 90" # open floor inside the terminal, facing +x
const SYNC_WAIT := 400 # ms for a teleport to reach the server before pressing E
const PRESS_TRIES := 6 # times to press E before giving up
const PRESS_WAIT := 1.5 # seconds to wait for a press to show up before pressing again

# Declaring tracking variables
var _a_id: int = 0 # peer id of bot a
var _b_id: int = 0 # peer id of bot b


func _start_game() -> void:
	## This function starts a room with bots a and b, and starts the game
	await _start_room()
	_a_id = int((await _joined("a")).id)
	_b_id = int((await _joined("b")).id)
	await _send("a", "start")
	for bot in ["a", "b"]:
		var s = await _wait_for(bot, func(st): return st.started and not st.crates.is_empty() and st.players.size() == 2)
		assert_bool(s.get("started", false)).override_failure_message("%s did not get into the airport" % bot).is_true()


func _do(bot: String, cmd: String) -> void:
	## This function moves a bot and gives the move time to reach the server
	# bot: which bot
	# cmd: a "tp ..." or "near ..." command
	await _send(bot, cmd)
	await await_millis(SYNC_WAIT)


func _press(bot: String, watcher: String, check: Callable) -> Dictionary:
	## This function presses E and waits for what it should do, pressing again if the server turned it down,
	## and returns the watcher's last state.
	## Just after spawning, the server can ignore a player's moves for a few seconds (other computers already
	## see them), so it checks the press against where the player spawned and quietly refuses it.
	# bot: which bot presses
	# watcher: which bot to watch for the result
	# check: func(state) -> bool, true once the press did its job
	var s = {}
	for attempt in PRESS_TRIES:
		await _wait_for(bot, func(st): return st.get("prompt", "") != "", 3.0)
		await _send(bot, "press")
		s = await _wait_for(watcher, check, PRESS_WAIT)
		if not s.is_empty() and check.call(s):
			return s
	return s


func _same_place(a: Array, b: Array, tolerance: float = 0.1) -> bool:
	## This function says if two positions from bot states are the same spot
	# a, b: [x, y, z]
	# tolerance: metres they may differ
	return Vector3(a[0], a[1], a[2]).distance_to(Vector3(b[0], b[1], b[2])) <= tolerance


func test_picking_up_and_dropping_shows_on_every_computer() -> void:
	await _start_game()
	await _do("a", "near Crate1 -1")

	# b sees a carrying it
	var b = await _press("a", "b", func(s): return _crate(s, "Crate1").holder == _a_id)
	assert_int(int(_crate(b, "Crate1").holder)).is_equal(_a_id)
	assert_bool(_crate(b, "Crate1").lifted).is_true()

	# dropping inside the terminal: both see it on the floor in the same spot
	await _do("a", "tp " + INSIDE)
	b = await _press("a", "b", func(s): return _crate(s, "Crate1").holder == 0)
	var a = await _send("a", "state")
	assert_int(int(_crate(b, "Crate1").holder)).is_equal(0)
	assert_float(_crate(b, "Crate1").pos[1]).is_equal_approx(0.42, 0.05)
	assert_bool(_same_place(_crate(a, "Crate1").pos, _crate(b, "Crate1").pos)).override_failure_message("a and b see the crate in different places").is_true()


func test_loading_counts_on_every_computer() -> void:
	await _start_game()
	await _do("a", "near Crate1 -1")
	await _press("a", "a", func(s): return _crate(s, "Crate1").holder == _a_id)
	await _do("a", "pad")

	var b = await _press("a", "b", func(s): return s.loaded == 1)
	assert_int(int(b.loaded)).is_equal(1)
	assert_bool(_crate(b, "Crate1").loaded).is_true()
	var a = await _wait_for("a", func(s): return s.loaded == 1)
	assert_bool(_same_place(_crate(a, "Crate1").pos, _crate(b, "Crate1").pos)).is_true()


func test_two_players_pressing_on_one_crate_at_once() -> void:
	await _start_game()
	await _do("a", "near Crate1 -1")
	var a = await _send("a", "state")
	var spot = a.players[str(_a_id)].pos
	await _do("b", "tp %f %f %f 90" % [spot[0], spot[1] + 0.05, spot[2] + 0.7])

	# both press right after each other (once both screens offer the pick up)
	await _wait_for("a", func(s): return s.get("prompt", "") != "", 3.0)
	await _wait_for("b", func(s): return s.get("prompt", "") != "", 3.0)
	await _send("a", "press")
	await _send("b", "press")
	await await_millis(1500)
	a = await _send("a", "state")
	var b = await _send("b", "state")

	# Crate1 went to one of them only, and both computers agree on every crate
	assert_int([_a_id, _b_id].count(int(_crate(a, "Crate1").holder))).is_equal(1)
	for crate_name in a.crates:
		assert_int(int(a.crates[crate_name].holder)).override_failure_message("a and b disagree on %s" % crate_name).is_equal(int(b.crates[crate_name].holder))
	var held_by_b = a.crates.values().filter(func(c): return c.holder == _b_id)
	assert_int(held_by_b.size()).is_less_equal(1)


func test_heavy_crate_lifts_slows_and_drops_when_apart() -> void:
	await _start_game()
	await _do("a", "near HeavyCrate1 -1")
	await _do("b", "near HeavyCrate1 1")

	# a grabs one side: nothing lifts yet
	var b = await _press("a", "b", func(s): return _crate(s, "HeavyCrate1").holder == _a_id)
	assert_bool(_crate(b, "HeavyCrate1").lifted).is_false()
	assert_str(b.prompt).is_equal("Press E to help lift")

	# b takes the other side: lifted on both computers, and both walk slower
	b = await _press("b", "b", func(s): return _crate(s, "HeavyCrate1").lifted and s.speed < 1.0)
	var a = await _wait_for("a", func(s): return _crate(s, "HeavyCrate1").lifted and s.speed < 1.0)
	assert_int(int(_crate(a, "HeavyCrate1").helper)).is_equal(_b_id)
	assert_float(a.speed).is_equal_approx(0.6, 0.01)
	assert_float(b.speed).is_equal_approx(0.6, 0.01)

	# b walks off: the crate drops for both, and both walk normally again
	await _do("b", "tp -84 0.45 -13.6 -90")
	a = await _wait_for("a", func(s): return not _crate(s, "HeavyCrate1").lifted and s.speed == 1.0)
	b = await _wait_for("b", func(s): return not _crate(s, "HeavyCrate1").lifted and s.speed == 1.0)
	assert_int(int(_crate(a, "HeavyCrate1").holder)).is_equal(0)
	assert_float(_crate(b, "HeavyCrate1").pos[1]).is_equal_approx(0.42, 0.05)
	assert_float(b.speed).is_equal(1.0)


func test_leaving_while_carrying_drops_the_crate_for_the_others() -> void:
	await _start_game()
	await _do("a", "near Crate1 -1")
	await _press("a", "b", func(s): return _crate(s, "Crate1").holder == _a_id)
	await _do("a", "tp " + INSIDE)

	await _send("a", "leave")
	var b = await _wait_for("b", func(s): return _crate(s, "Crate1").holder == 0 and s.players.size() == 1)
	assert_int(int(_crate(b, "Crate1").holder)).is_equal(0)
	assert_float(_crate(b, "Crate1").pos[1]).is_equal_approx(0.42, 0.05)


func test_a_heavy_carrier_leaving_drops_it() -> void:
	await _start_game()
	await _do("a", "near HeavyCrate1 -1")
	await _do("b", "near HeavyCrate1 1")
	await _press("a", "b", func(s): return _crate(s, "HeavyCrate1").holder == _a_id)
	await _press("b", "a", func(s): return _crate(s, "HeavyCrate1").lifted)

	await _send("b", "leave")
	var a = await _wait_for("a", func(s): return _crate(s, "HeavyCrate1").holder == 0 and s.speed == 1.0)
	assert_int(int(_crate(a, "HeavyCrate1").holder)).is_equal(0)
	assert_int(int(_crate(a, "HeavyCrate1").helper)).is_equal(0)
	assert_float(a.speed).is_equal(1.0)


func test_a_late_joiner_sees_every_crate_as_it_is() -> void:
	await _start_game()

	# a loads Crate1
	await _do("a", "near Crate1 -1")
	await _press("a", "a", func(s): return _crate(s, "Crate1").holder == _a_id)
	await _do("a", "pad")
	await _press("a", "a", func(s): return s.loaded == 1)

	# then a and b hold HeavyCrate1 up in the air
	await _do("a", "near HeavyCrate1 -1")
	await _do("b", "near HeavyCrate1 1")
	await _press("a", "b", func(s): return _crate(s, "HeavyCrate1").holder == _a_id)
	var a = await _press("b", "a", func(s): return _crate(s, "HeavyCrate1").lifted)

	# c joins now and must see the same
	var c = await _joined("c")
	c = await _wait_for("c", func(s): return s.loaded == 1 and _crate(s, "HeavyCrate1").lifted and _crate(s, "HeavyCrate1").pos[1] > 0.6)
	assert_int(int(c.loaded)).is_equal(1)
	assert_bool(_crate(c, "Crate1").loaded).is_true()
	assert_bool(_same_place(_crate(a, "Crate1").pos, _crate(c, "Crate1").pos)).override_failure_message("c sees the loaded crate somewhere else").is_true()
	assert_int(int(_crate(c, "HeavyCrate1").holder)).is_equal(_a_id)
	assert_int(int(_crate(c, "HeavyCrate1").helper)).is_equal(_b_id)
	assert_float(_crate(c, "HeavyCrate1").pos[1]).is_greater(0.6) # up in the air between a and b

	# c sees a and b standing where they really are, so the crate floats in the same place too
	# (positions of players who stand still can take a moment to reach a new computer)
	# a's view is read again now: the snapshot from the moment of lifting can catch the crate still rising
	a = await _send("a", "state")
	var check = func(s):
		for id in [_a_id, _b_id]:
			if not _same_place(s.players[str(id)].pos, a.players[str(id)].pos):
				return false
		return _same_place(_crate(s, "HeavyCrate1").pos, _crate(a, "HeavyCrate1").pos)
	c = await _wait_for("c", check, 5.0)
	for id in [_a_id, _b_id]:
		assert_bool(_same_place(c.players[str(id)].pos, a.players[str(id)].pos)).override_failure_message("c sees player %d at %s, a sees %s" % [id, c.players[str(id)].pos, a.players[str(id)].pos]).is_true()
	assert_bool(_same_place(_crate(a, "HeavyCrate1").pos, _crate(c, "HeavyCrate1").pos)).override_failure_message("c sees the heavy crate at %s, a at %s" % [_crate(c, "HeavyCrate1").pos, _crate(a, "HeavyCrate1").pos]).is_true()
