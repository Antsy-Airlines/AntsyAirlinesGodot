extends CanvasLayer
## The "Press Space to stand up" hint shown when our player sits down. It stays for a moment, then fades away.
## Sits under our own player and listens to it.

# Declaring Default/Const variables
@export var hold_time: float = 3.0 # seconds the hint stays fully visible
@export var fade_time: float = 1.0 # seconds it takes to fade out

# Getting References for everyone in the scene
@onready var _panel: PanelContainer = %HintPanel # box around the hint

# Declaring tracking variables
var _tween: Tween # the fade that is playing, if any


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# the server has no screen, and other players' hints aren't ours to show
	if HighLevelNetworkHandler.is_server_launch() or not is_multiplayer_authority():
		queue_free()
		return

	_panel.visible = false
	get_parent().seat_changed.connect(_on_seat_changed)


func _on_seat_changed(seated: bool) -> void:
	## This function shows the hint when we sit down, and hides it when we get up
	# seated: true when we just sat down
	if _tween != null:
		_tween.kill()
	_panel.visible = seated

	# Guard case for getting up: nothing to fade
	if not seated:
		return

	_panel.modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(hold_time)
	_tween.tween_property(_panel, "modulate:a", 0.0, fade_time)
	_tween.tween_callback(_panel.hide)
