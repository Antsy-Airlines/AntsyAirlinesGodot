extends CanvasLayer
## Cargo overlay: how many crates are in the plane. Sits under the cargo manager and listens to it.
## (The "Press E" hint is the shared InteractionPrompt on our own player.)

# Getting References for everyone in the scene
@onready var _counter: Label = %Counter # "Cargo 2/6 loaded"


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# the server has no screen, so it doesn't need the overlay
	if HighLevelNetworkHandler.is_server_launch():
		queue_free()
		return

	get_parent().cargo_changed.connect(_show_count) # the cargo manager


func _show_count(loaded: int, total: int) -> void:
	## This function updates the loaded counter
	# loaded: crates in the hold
	# total: crates in the level
	_counter.text = "Cargo %d/%d loaded" % [loaded, total]
