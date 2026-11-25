extends "res://test/helpers/net_suite.gd"
## One lobby room with real bot players over the network: joining, the host, names, a full room,
## starting the game, leaving, late joiners and the room closing by itself.


func test_players_join_and_the_first_is_host() -> void:
	await _start_room()
	var a = await _joined("a")
	var b = await _joined("b")

	# both see two players, and the first one in is the host
	a = await _wait_for("a", func(s): return s.count == 2 and s.players.size() == 2)
	b = await _wait_for("b", func(s): return s.count == 2 and s.players.size() == 2)
	assert_int(int(a.count)).is_equal(2)
	assert_int(int(b.count)).is_equal(2)
	assert_int(int(a.host)).is_equal(int(a.id))
	assert_int(int(b.host)).is_equal(int(a.id))
	assert_str(a.code).is_equal("TESTS")

	# each gets its own spawn slot
	assert_int(int(a.slot)).is_equal(0)
	assert_int(int(b.slot)).is_equal(1)


func test_the_same_name_gets_a_number() -> void:
	await _start_room()
	await _start_bot("a")
	await _start_bot("b")
	await _send("a", "user Sam")
	await _send("b", "user sam")
	await _send("a", "connect %d" % ROOM_PORT)
	await _wait_for("a", func(s): return s.players.size() == 1)
	await _send("b", "connect %d" % ROOM_PORT)

	# the second Sam is shown as "sam 2" on every computer
	var a = await _wait_for("a", func(s): return s.players.size() == 2)
	var names = a.players.values().map(func(p): return p.name)
	assert_array(names).contains_exactly_in_any_order(["Sam", "sam 2"])


func test_a_bad_name_is_refused_by_the_server() -> void:
	# the title screen normally stops this, but the server checks again
	await _start_room()
	await _start_bot("a")
	await _send("a", "user <b>hi</b>")
	await _send("a", "connect %d" % ROOM_PORT)
	var a = await _wait_for("a", func(s): return s.scene == "TitleScreen" and s.refused != "")
	assert_str(a.refused).contains("Use only")


func test_a_fifth_player_is_refused() -> void:
	await _start_room()
	for bot in ["a", "b", "c", "d"]:
		await _joined(bot)

	await _start_bot("e")
	await _send("e", "connect %d" % ROOM_PORT)
	var e = await _wait_for("e", func(s): return s.refused != "")
	assert_str(e.refused).is_equal("This lobby is full (4 players).")
	assert_str(e.scene).is_equal("TitleScreen")

	# the four inside are not bothered
	var a = await _wait_for("a", func(s): return s.count == 4)
	assert_int(int(a.count)).is_equal(4)


func test_only_the_host_can_start() -> void:
	await _start_room()
	await _joined("a")
	await _joined("b")

	# a non-host asking does nothing
	await _send("b", "start")
	await await_millis(1000)
	var b = await _send("b", "state")
	assert_bool(b.started).is_false()

	# the host asking starts it for everyone, and the airport loads
	await _send("a", "start")
	b = await _wait_for("b", func(s): return s.started and not s.crates.is_empty())
	var a = await _wait_for("a", func(s): return s.started and not s.crates.is_empty())
	assert_bool(b.started).is_true()
	assert_int(int(a.loaded)).is_equal(0)
	assert_int(b.crates.size()).is_equal(8)


func test_the_host_can_start_alone() -> void:
	await _start_room()
	await _joined("a")
	await _send("a", "start")
	var a = await _wait_for("a", func(s): return s.started)
	assert_bool(a.started).is_true()


func test_host_leaving_hands_the_room_over() -> void:
	await _start_room()
	await _joined("a")
	var b = await _joined("b")

	await _send("a", "leave")
	b = await _wait_for("b", func(s): return s.host == s.id and s.count == 1)
	assert_int(int(b.host)).is_equal(int(b.id))
	assert_int(int(b.count)).is_equal(1)
	assert_int(b.players.size()).is_equal(1)

	# the new host can start
	await _send("b", "start")
	b = await _wait_for("b", func(s): return s.started)
	assert_bool(b.started).is_true()


func test_a_late_joiner_goes_straight_to_the_airport_in_a_free_slot() -> void:
	await _start_room()
	await _joined("a")
	await _joined("b")
	await _joined("c")
	await _send("a", "start")
	await _wait_for("a", func(s): return s.started)

	# b leaves, so slot 1 is free for the next player
	await _send("b", "leave")
	await _wait_for("a", func(s): return s.count == 2)

	var d = await _joined("d")
	d = await _wait_for("d", func(s): return s.started and not s.crates.is_empty())
	assert_bool(d.started).is_true()
	assert_int(int(d.slot)).is_equal(1)


func test_an_empty_room_closes_itself() -> void:
	var room = await _start_room(ROOM_PORT, ["--empty-timeout=2"])
	await _joined("a")

	# still open while someone is inside
	await await_millis(3000)
	assert_bool(OS.is_process_running(room)).is_true()

	await _send("a", "leave")
	assert_bool(await _wait_exit(room, 10.0)).override_failure_message("the empty room stayed open").is_true()


func test_a_room_on_a_busy_port_closes_cleanly() -> void:
	await _start_room()
	var log_name = "busy_room"
	var pid = _launch(["--room", "--port=%d" % ROOM_PORT, "--code=BUSYY", "--status-port=%d" % STATUS_PORT], log_name)
	assert_bool(await _wait_exit(pid, 15.0)).override_failure_message("a room on a busy port kept running").is_true()

	var log_text = _read_log(log_name)
	assert_str(log_text).contains("Failed to create server")
	assert_str(log_text).not_contains("SCRIPT ERROR")
