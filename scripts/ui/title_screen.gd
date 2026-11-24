class_name TitleScreen
extends Control
## First screen of the game: the player types a username, then creates a lobby or joins one with a code.

# Declaring Default/Const variables
const LOBBY_SCENE := "res://scenes/levels/lobby.tscn" # scene we go to once we have a lobby
const DESK_SCENE := "res://scenes/network/front_desk.tscn" # scene the --server build runs
const SAVE_PATH := "user://player.cfg" # file that remembers the username for next time
const MAX_NAME_LEN := 16 # longest username allowed
const ERROR_COLOR := Color(1, 0.45, 0.4) # red text for problems
const STATUS_COLOR := Color(0.62, 0.68, 0.8) # dim text for "Creating lobby..."

# Getting References for everyone in the scene
@onready var _name_input: LineEdit = %NameInput # box where the username is typed
@onready var _code_input: LineEdit = %CodeInput # box where a friend's lobby code is typed
@onready var _message: Label = %Message # text for problems and progress
@onready var _create_button: Button = %CreateButton # makes a new lobby
@onready var _join_button: Button = %JoinButton # joins the lobby in the code box
@onready var _quit_button: Button = %QuitButton # closes the game


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# servers have no screen: the front desk hands out codes, a room runs one lobby
	if HighLevelNetworkHandler.has_flag("--server"):
		get_tree().change_scene_to_file.call_deferred(DESK_SCENE)
		return
	if HighLevelNetworkHandler.has_flag("--room"):
		get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # the lobby locks the mouse, so freeing it here

	# connecting the buttons
	_create_button.pressed.connect(_on_create)
	_join_button.pressed.connect(_on_join)
	_quit_button.pressed.connect(get_tree().quit)

	# connecting the text boxes
	_name_input.text_submitted.connect(func(_text): _code_input.grab_focus()) # enter moves on to the code box
	_name_input.text_changed.connect(func(_text): _show_message("")) # clearing old errors while typing
	_code_input.text_submitted.connect(func(_text): _on_join()) # enter in the code box joins
	_code_input.text_changed.connect(_on_code_changed)

	# connecting the front desk answers
	LobbyDirectory.lobby_found.connect(_on_lobby_found)
	LobbyDirectory.lobby_failed.connect(_on_lobby_failed)

	# filling in the name from last time
	_name_input.text = _load_name()
	_name_input.caret_column = _name_input.text.length()
	_name_input.grab_focus()

	# showing why we came back here, if the network sent us back
	_show_message(HighLevelNetworkHandler.last_error)
	HighLevelNetworkHandler.last_error = ""


func _on_create() -> void:
	## This function asks the front desk for a brand new lobby
	# Guard case for a bad username
	if not _check_and_save_name():
		return

	_set_busy(true)
	_show_message("Creating lobby...", false)
	LobbyDirectory.create_lobby()


func _on_join() -> void:
	## This function asks the front desk for the lobby in the code box
	# Guard case for a bad username
	if not _check_and_save_name():
		return

	# Guard case for an empty code box
	var code = _code_input.text.strip_edges()
	if code.is_empty():
		_show_message("Type the lobby code your friend shared.")
		_code_input.grab_focus()
		return

	_set_busy(true)
	_show_message("Joining %s..." % code, false)
	LobbyDirectory.join_lobby(code)


func _on_code_changed(new_text: String) -> void:
	## This function keeps the code box in capitals while typing
	# new_text: what is in the box now
	var caret = _code_input.caret_column
	_code_input.text = new_text.to_upper()
	_code_input.caret_column = caret # keeping the cursor where it was
	_show_message("")


func _on_lobby_found(code: String, port: int) -> void:
	## This function moves the player to the lobby the front desk gave
	# code: the lobby code
	# port: the room's port
	print("[client] front desk sent us to lobby %s on port %d" % [code, port])
	HighLevelNetworkHandler.room_port = port
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_lobby_failed(reason: String) -> void:
	## This function shows why the front desk couldn't help, so the player can try again
	# reason: message from the front desk
	_set_busy(false)
	_show_message(reason)


func _check_and_save_name() -> bool:
	## This function checks the username, saves it, and says if it was fine
	var name_err = check_name(_name_input.text)

	# Guard case for a bad username
	if name_err != "":
		_show_message(name_err)
		_name_input.grab_focus()
		return false

	# remembering the name for the lobby and for next time
	var clean_name = _name_input.text.strip_edges()
	HighLevelNetworkHandler.username = clean_name
	_save_name(clean_name)
	return true


func _set_busy(busy: bool) -> void:
	## This function locks the buttons while we wait for the front desk
	# busy: true while waiting
	_create_button.disabled = busy
	_join_button.disabled = busy
	_name_input.editable = not busy
	_code_input.editable = not busy


func _show_message(text: String, is_error: bool = true) -> void:
	## This function shows a message under the buttons
	# text: what to show ("" hides it)
	# is_error: red for problems, dim for progress
	_message.text = text
	_message.add_theme_color_override("font_color", ERROR_COLOR if is_error else STATUS_COLOR)


static func check_name(raw_name:String) -> String:
	## This function says what is wrong with a username, or gives "" if it is fine
	# raw_name: the username as the player typed it
	var clean_name = raw_name.strip_edges()

	# checking the length
	if clean_name.is_empty():
		return "Please enter a username."
	if clean_name.length() > MAX_NAME_LEN:
		return "Usernames can be at most %d characters." % MAX_NAME_LEN

	# checking every character is allowed
	var allowed = RegEx.create_from_string("^[A-Za-z0-9 _-]+$")
	if allowed.search(clean_name) == null:
		return "Use only letters, numbers, spaces, _ and -."

	return ""


func _load_name() -> String:
	## This function reads the username saved last time
	var cfg = ConfigFile.new()

	# if nothing is saved yet (first time playing)
	if cfg.load(SAVE_PATH) != OK:
		return ""

	return cfg.get_value("player", "username", "")


func _save_name(user_name:String) -> void:
	## This function saves the username for next time
	# user_name: the username that already passed check_name
	var cfg = ConfigFile.new()
	cfg.set_value("player", "username", user_name)
	cfg.save(SAVE_PATH)
