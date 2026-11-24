extends Node
## Scene the --server build runs: it only starts the front desk that hands out lobby codes.


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	LobbyDirectory.start_desk()
