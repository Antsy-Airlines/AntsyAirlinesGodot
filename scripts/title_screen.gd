class_name TitleScreen
extends Control
## First screen of the game: the player types a username and presses Play to join the lobby.

# Declaring Default/Const variables
const LOBBY_SCENE := "res://scenes/lobby.tscn" # scene we go to after pressing Play
const SAVE_PATH := "user://player.cfg" # file that remembers the username for next time
const MAX_NAME_LEN := 16 # longest username allowed

# Getting References for everyone in the scene
@onready var _name_input: LineEdit = %NameInput # box where the username is typed
@onready var _message: Label = %Message # red text for problems
@onready var _play_button: Button = %PlayButton # joins the lobby
@onready var _quit_button: Button = %QuitButton # closes the game


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# the server has no screen, so it goes straight to the lobby
	if HighLevelNetworkHandler.is_server_launch():
		get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # the lobby locks the mouse, so freeing it here

	# connecting the buttons
	_play_button.pressed.connect(_on_play)
	_quit_button.pressed.connect(get_tree().quit)
	_name_input.text_submitted.connect(func(_text): _on_play()) # pressing enter also plays
	_name_input.text_changed.connect(func(_text): _message.text = "") # clearing old errors while typing

	# filling in the name from last time
	_name_input.text = _load_name()
	_name_input.caret_column = _name_input.text.length()
	_name_input.grab_focus()

	# showing why we came back here, if the network sent us back
	_message.text = HighLevelNetworkHandler.last_error
	HighLevelNetworkHandler.last_error = ""


func _on_play() -> void:
	## This function checks the username and moves the player to the lobby
	var name_err = check_name(_name_input.text)

	# Guard case for a bad username
	if name_err != "":
		_message.text = name_err
		return

	# remembering the name for the lobby and for next time
	var clean_name = _name_input.text.strip_edges()
	HighLevelNetworkHandler.username = clean_name
	_save_name(clean_name)

	get_tree().change_scene_to_file(LOBBY_SCENE)


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
