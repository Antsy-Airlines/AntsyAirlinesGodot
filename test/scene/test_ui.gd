extends GdUnitTestSuite
## The title screen and the lobby overlay, without a network: messages, the code box,
## the saved username, the host box and the Esc menu.
## The saved username file is backed up first and put back after, so a local run never changes it.

# Getting References for the scenes under test
const TitleScene := preload("res://scenes/ui/title_screen.tscn") # first screen
const HudScene := preload("res://scenes/ui/lobby_hud.tscn") # lobby overlay

# Declaring tracking variables
var _saved_cfg: String = "" # player.cfg as it was before the tests ("" if there was none)
var _had_cfg: bool = false # if player.cfg existed before the tests
var _saved_user: String = "" # the username in the autoload before each test
var _node: Node # the screen made for the current test


func before() -> void:
	_had_cfg = FileAccess.file_exists(TitleScreen.SAVE_PATH)
	if _had_cfg:
		_saved_cfg = FileAccess.get_file_as_string(TitleScreen.SAVE_PATH)


func after() -> void:
	# putting the saved username file back the way it was
	if _had_cfg:
		var file = FileAccess.open(TitleScreen.SAVE_PATH, FileAccess.WRITE)
		file.store_string(_saved_cfg)
		file.close()
	elif FileAccess.file_exists(TitleScreen.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TitleScreen.SAVE_PATH))


func before_test() -> void:
	_saved_user = HighLevelNetworkHandler.username
	_node = null


func after_test() -> void:
	HighLevelNetworkHandler.username = _saved_user
	HighLevelNetworkHandler.last_error = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _node != null:
		_node.queue_free()
	await await_idle_frame()


func _title() -> Control:
	## This function puts a fresh title screen in the tree
	_node = TitleScene.instantiate()
	get_tree().root.add_child(_node)
	return _node


func _hud() -> CanvasLayer:
	## This function puts a fresh lobby overlay in the tree
	_node = HudScene.instantiate()
	get_tree().root.add_child(_node)
	return _node


func _save_name(user_name: String) -> void:
	## This function writes a username into player.cfg like the title screen does
	# user_name: the name to remember
	var cfg = ConfigFile.new()
	cfg.set_value("player", "username", user_name)
	cfg.save(TitleScreen.SAVE_PATH)


# ---------------- title screen ----------------

func test_the_code_box_types_in_capitals() -> void:
	var title = _title()
	title._on_code_changed("ab3x")
	assert_str(title.get_node("%CodeInput").text).is_equal("AB3X")


func test_create_with_no_name_shows_why() -> void:
	var title = _title()
	title.get_node("%NameInput").text = "   "
	title._on_create()
	assert_str(title.get_node("%Message").text).is_equal("Please enter a username.")
	assert_bool(title.get_node("%CreateButton").disabled).is_false() # still free to try again
	assert_bool(LobbyDirectory._asking).is_false() # the front desk was never asked


func test_join_with_no_code_shows_why_and_remembers_the_name() -> void:
	var title = _title()
	title.get_node("%NameInput").text = "  Kim  "
	title.get_node("%CodeInput").text = ""
	title._on_join()
	assert_str(title.get_node("%Message").text).is_equal("Type the lobby code your friend shared.")
	assert_bool(LobbyDirectory._asking).is_false()

	# the good name was trimmed, kept for the lobby and saved for next time
	assert_str(HighLevelNetworkHandler.username).is_equal("Kim")
	assert_str(title._load_name()).is_equal("Kim")


func test_the_name_from_last_time_is_filled_in() -> void:
	_save_name("Remembered")
	var title = _title()
	assert_str(title.get_node("%NameInput").text).is_equal("Remembered")


func test_the_reason_we_were_sent_back_is_shown_once() -> void:
	HighLevelNetworkHandler.last_error = "Lost connection to the server."
	var title = _title()
	assert_str(title.get_node("%Message").text).is_equal("Lost connection to the server.")
	assert_str(HighLevelNetworkHandler.last_error).is_empty() # not shown again next time


func test_a_front_desk_problem_unlocks_the_buttons() -> void:
	var title = _title()
	title._set_busy(true)
	assert_bool(title.get_node("%JoinButton").disabled).is_true()

	title._on_lobby_failed("No lobby with code ZZZZZ.")
	assert_str(title.get_node("%Message").text).is_equal("No lobby with code ZZZZZ.")
	assert_bool(title.get_node("%JoinButton").disabled).is_false()
	assert_bool(title.get_node("%NameInput").editable).is_true()


# ---------------- lobby overlay ----------------

func test_the_code_shows_only_once_we_have_one() -> void:
	var hud = _hud()
	hud._show_code("")
	assert_bool(hud.get_node("%CodePanel").visible).is_false()
	assert_bool(hud.get_node("%CopyButton").visible).is_false()

	hud._show_code("K7QXM")
	assert_bool(hud.get_node("%CodePanel").visible).is_true()
	assert_str(hud.get_node("%CodeLabel").text).is_equal("K7QXM")
	assert_str(hud.get_node("%MenuCode").text).is_equal("Code: K7QXM")


func test_the_host_sees_the_start_button() -> void:
	# offline we are peer 1, so host 1 is us
	var hud = _hud()
	hud._show_room(1, 1, false)
	assert_str(hud.get_node("%StatusLabel").text).starts_with("You")
	assert_str(hud.get_node("%StatusHint").text).is_equal("1/4 players · Esc to start")
	assert_bool(hud.get_node("%StartButton").visible).is_true()
	assert_bool(hud.get_node("%StartButton").disabled).is_false()
	assert_str(hud.get_node("%StartButton").text).is_equal("Start game")


func test_everyone_else_waits_for_the_host() -> void:
	var hud = _hud()
	hud._show_room(999, 3, false)
	assert_str(hud.get_node("%StatusLabel").text).is_equal("Waiting for the host to start")
	assert_str(hud.get_node("%StatusHint").text).is_equal("3/4 players")
	assert_bool(hud.get_node("%StartButton").visible).is_false()


func test_start_is_locked_with_too_few_players() -> void:
	var hud = _hud()
	hud._show_room(1, 0, false)
	assert_bool(hud.get_node("%StartButton").disabled).is_true()
	assert_str(hud.get_node("%StatusHint").text).ends_with("need 1 to start")


func test_the_lobby_boxes_hide_once_the_game_starts() -> void:
	var hud = _hud()
	hud._show_room(1, 2, false)
	hud._show_room(1, 2, true)
	assert_bool(hud.get_node("%StatusPanel").visible).is_false()
	assert_bool(hud.get_node("%StartButton").visible).is_false()


func test_esc_opens_and_closes_the_menu() -> void:
	var hud = _hud()
	var esc = InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true

	hud._unhandled_input(esc)
	assert_bool(hud.get_node("%Menu").visible).is_true()
	hud._unhandled_input(esc)
	assert_bool(hud.get_node("%Menu").visible).is_false()
