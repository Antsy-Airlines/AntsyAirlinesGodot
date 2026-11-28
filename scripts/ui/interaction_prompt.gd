extends CanvasLayer
## The "Press E to ..." hint at the bottom of the screen, for everything players can use (crates, doors).
## Sits under our own player's Interactor and listens to it.

# Getting References for everyone in the scene
@onready var _prompt_panel: PanelContainer = %PromptPanel # box around the E hint
@onready var _prompt: Label = %Prompt # "Press E to pick up"


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# the server has no screen, and other players' hints aren't ours to show
	if HighLevelNetworkHandler.is_server_launch() or not is_multiplayer_authority():
		queue_free()
		return

	# hiding the hint until there is something to do
	_prompt_panel.visible = false
	get_parent().prompt_changed.connect(_show_prompt)


func _show_prompt(text: String) -> void:
	## This function shows or hides the E hint
	# text: what to show ("" hides it)
	_prompt.text = text
	_prompt_panel.visible = text != ""
