extends CanvasLayer
## Lobby overlay for players: the lobby code to share in the corner, and an Esc menu to copy it or leave.
## Before the game starts it also shows who the host is, and gives the host a Start button.

# Declaring Default/Const variables
const COPIED_TIME := 1.5 # seconds the copy button says "Copied!"

# Getting References for everyone in the scene
@onready var _code_panel: PanelContainer = %CodePanel # corner box with the code
@onready var _code_label: Label = %CodeLabel # the code in the corner
@onready var _menu: Control = %Menu # Esc menu, hidden while playing
@onready var _menu_code: Label = %MenuCode # the code inside the menu
@onready var _copy_button: Button = %CopyButton # copies the code
@onready var _back_button: Button = %BackButton # closes the menu
@onready var _leave_button: Button = %LeaveButton # goes back to the title screen
@onready var _start_button: Button = %StartButton # host only: starts the game for everyone
@onready var _status_panel: PanelContainer = %StatusPanel # top box: host / waiting and player count
@onready var _status_label: Label = %StatusLabel # "You're the host" or "Waiting for the host"
@onready var _status_hint: Label = %StatusHint # player count and what to do next


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# the server has no screen, so it doesn't need the overlay
	if HighLevelNetworkHandler.is_server_launch():
		queue_free()
		return

	# hiding everything until the server lets us in
	_menu.visible = false
	_show_code(HighLevelNetworkHandler.room_code)

	# connecting the buttons and the join signal
	HighLevelNetworkHandler.lobby_joined.connect(_show_code)
	_copy_button.pressed.connect(_on_copy)
	_back_button.pressed.connect(_close_menu)
	_leave_button.pressed.connect(HighLevelNetworkHandler.leave_lobby)

	# showing who can start, and hiding it all once the game starts
	HighLevelNetworkHandler.room_state_changed.connect(_show_room)
	HighLevelNetworkHandler.game_started.connect(_on_game_started)
	_start_button.pressed.connect(_on_start)


func _unhandled_input(event: InputEvent) -> void:
	# if it isn't Esc, the player and camera handle it
	if not event.is_action_pressed("ui_cancel"):
		return

	# Esc opens the menu, or closes it if it is open
	if _menu.visible:
		_close_menu()
	else:
		_open_menu()
	get_viewport().set_input_as_handled() # the camera doesn't need to see this Esc


func _open_menu() -> void:
	## This function shows the menu and frees the mouse so the buttons can be clicked
	_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_menu() -> void:
	## This function hides the menu and locks the mouse again for looking around
	_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_code(code: String) -> void:
	## This function puts the lobby code on screen, or hides it if there is none
	# code: the lobby code from the server
	var has_code = code != ""

	_code_label.text = code
	_menu_code.text = "Code: %s" % code
	_code_panel.visible = has_code
	_menu_code.visible = has_code
	_copy_button.visible = has_code


func _show_room(host: int, count: int, started: bool) -> void:
	## This function updates the top box and the Start button when the lobby changes
	# host: peer id of the host
	# count: players in the lobby
	# started: true once the game started
	var is_host = host == multiplayer.get_unique_id()
	var enough = count >= HighLevelNetworkHandler.MIN_PLAYERS
	var players = "%d/%d players" % [count, HighLevelNetworkHandler.MAX_PLAYERS]

	# Guard case for a game that already started (nothing to wait for)
	if started:
		_on_game_started()
		return

	# host sees what they need, everyone else sees they are waiting
	_status_panel.visible = true
	if is_host:
		_status_label.text = "You're the host"
		_status_hint.text = players + (" · Esc to start" if enough else " · need %d to start" % HighLevelNetworkHandler.MIN_PLAYERS)
	else:
		_status_label.text = "Waiting for the host to start"
		_status_hint.text = players

	# Start button only for the host, locked until enough players are in
	_start_button.visible = is_host
	_start_button.disabled = not enough
	_start_button.text = "Start game" if enough else "Need %d players" % HighLevelNetworkHandler.MIN_PLAYERS


func _on_start() -> void:
	## This function asks the server to start, then goes back to playing
	_start_button.disabled = true # no double starts while we wait for the server
	HighLevelNetworkHandler.request_start()
	_close_menu()


func _on_game_started() -> void:
	## This function hides the lobby-only parts once everyone is in the airport
	_status_panel.visible = false
	_start_button.visible = false


func _on_copy() -> void:
	## This function copies the lobby code so it can be pasted to friends
	DisplayServer.clipboard_set(HighLevelNetworkHandler.room_code)

	# showing "Copied!" for a moment (the tween stops if the overlay is gone)
	_copy_button.text = "Copied!"
	var tween = create_tween()
	tween.tween_callback(func(): _copy_button.text = "Copy code").set_delay(COPIED_TIME)
