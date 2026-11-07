extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if "--server" in OS.get_cmdline_args(): # checks if --server flag was an argument when the program launched
		HighLevelNetworkHandler.start_server()
	else:
		print("Client mode")
		HighLevelNetworkHandler.start_client()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
