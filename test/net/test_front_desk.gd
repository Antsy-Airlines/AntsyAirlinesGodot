extends "res://test/helpers/net_suite.gd"
## The front desk with real bot players: making a lobby, joining it by code, and every way asking can fail.

# Declaring Default/Const variables
const DESK_WAIT := 25.0 # seconds to wait for the desk to start a room and send us there


func _create(bot: String) -> Dictionary:
	## This function starts a bot that makes a new lobby, and waits until it is inside
	# bot: its name
	await _start_bot(bot)
	await _send(bot, "create")
	var s = await _wait_for(bot, func(st): return st.found != "" and st.host != 0, DESK_WAIT)
	assert_str(s.get("found", "")).override_failure_message("%s got no lobby from the front desk" % bot).is_not_empty()
	return s


func test_create_a_lobby_and_join_it_by_code() -> void:
	await _start_desk()
	var a = await _create("a")
	assert_int(a.found.length()).is_equal(5)
	assert_str(a.code).is_equal(a.found)
	assert_int(int(a.host)).is_equal(int(a.id))

	# a friend types the code in lowercase, and still lands in the same lobby
	await _start_bot("b")
	await _send("b", "join " + a.found.to_lower())
	var b = await _wait_for("b", func(s): return s.count == 2, DESK_WAIT)
	assert_str(b.code).is_equal(a.found)
	assert_int(int(b.count)).is_equal(2)
	assert_int(int(b.host)).is_equal(int(a.id))


func test_two_lobbies_get_different_codes() -> void:
	await _start_desk()
	var a = await _create("a")
	var b = await _create("b")
	assert_str(b.found).is_not_equal(a.found)
	assert_int(int(b.host)).is_equal(int(b.id)) # b is alone in its own lobby
	assert_int(int(b.count)).is_equal(1)


func test_wrong_codes_are_refused() -> void:
	await _start_desk()
	await _start_bot("a")

	# a code nobody made
	await _send("a", "join ZZZZZ")
	var a = await _wait_for("a", func(s): return s.failed != "")
	assert_str(a.failed).is_equal("No lobby with code ZZZZZ.")

	# a code with the wrong length
	await _send("a", "join abc")
	a = await _wait_for("a", func(s): return s.failed != "")
	assert_str(a.failed).is_equal("Please enter a 5-character code.")

	# an empty code
	await _send("a", "join")
	a = await _wait_for("a", func(s): return s.failed != "")
	assert_str(a.failed).is_equal("Please enter a 5-character code.")
	assert_str(a.scene).is_empty() # never left for a lobby


func test_an_old_game_version_is_refused() -> void:
	await _start_desk()
	var a = await _create("a")
	await _start_bot("b")
	await _send("b", "oldjoin " + a.found)
	var b = await _wait_for("b", func(s): return s.failed != "")
	assert_str(b.failed).is_equal("Your game is out of date. Please update.")


func test_a_full_lobby_is_refused_at_the_front_desk() -> void:
	await _start_desk()
	var a = await _create("a")
	for bot in ["b", "c", "d"]:
		await _start_bot(bot)
		await _send(bot, "join " + a.found)
	await _wait_for("a", func(s): return s.count == 4, DESK_WAIT)

	# waiting for the room to report 4 players to the desk, then a fifth asks
	await await_millis(int(HighLevelNetworkHandler.STATUS_TIME * 1000) + 1000)
	await _start_bot("e")
	await _send("e", "join " + a.found)
	var e = await _wait_for("e", func(s): return s.failed != "")
	assert_str(e.failed).is_equal("This lobby is full.")


func test_no_front_desk_running() -> void:
	# nobody listens on the desk port, so asking gives up after a few seconds
	await _start_bot("a")
	await _send("a", "create")
	var a = await _wait_for("a", func(s): return s.failed != "", LobbyDirectory.ASK_TIMEOUT + 5.0)
	assert_str(a.failed).ends_with("reach the server.") # the full text has an apostrophe, which gdUnit cannot read here
