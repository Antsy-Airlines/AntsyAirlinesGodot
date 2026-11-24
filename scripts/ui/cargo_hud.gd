extends CanvasLayer
## Cargo overlay: how many crates are in the plane, and what pressing E will do right now.
## Sits under the cargo manager and listens to its signals.

# Getting References for everyone in the scene
@onready var _counter: Label = %Counter # "Cargo 2/6 loaded"
@onready var _prompt_panel: PanelContainer = %PromptPanel # box around the E hint
@onready var _prompt: Label = %Prompt # "Press E to pick up"


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# the server has no screen, so it doesn't need the overlay
	if HighLevelNetworkHandler.is_server_launch():
		queue_free()
		return

	# hiding the hint until there is something to do
	_prompt_panel.visible = false

	var cargo = get_parent() # the cargo manager
	cargo.cargo_changed.connect(_show_count)
	cargo.prompt_changed.connect(_show_prompt)


func _show_count(loaded: int, total: int) -> void:
	## This function updates the loaded counter
	# loaded: crates in the hold
	# total: crates in the level
	_counter.text = "Cargo %d/%d loaded" % [loaded, total]


func _show_prompt(text: String) -> void:
	## This function shows or hides the E hint
	# text: what to show ("" hides it)
	_prompt.text = text
	_prompt_panel.visible = text != ""
