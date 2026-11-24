extends Node3D
## The airport map: terminals, planes, runways and the furniture inside terminal 1.
## Players start inside terminal 1 at the spawn points.

# Declaring Default/Const variables
const PLAYER_SCENE := preload("res://scenes/player.tscn") # only used for the test player

# Getting References for everyone in the scene
@onready var _spawn_points: Node3D = $SpawnPoints # one Marker3D per player slot, inside terminal 1


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# running this scene by itself (F6) drops in a test player, so the map can be walked around
	if get_tree().current_scene == self:
		_add_test_player()


func get_spawn(index: int) -> Transform3D:
	## This function gives the spawn point for a player slot (wraps around if there are more players than points)
	# index: the player's slot, 0 for the first player
	var points = _spawn_points.get_children()
	return points[index % points.size()].global_transform


func _add_test_player() -> void:
	## This function adds one player we control, for walking the map without a server
	var player = PLAYER_SCENE.instantiate()
	player.name = "1" # offline we are peer 1, so this player is ours
	player.username = "Test"
	add_child(player)
	player.global_transform = get_spawn(0)
