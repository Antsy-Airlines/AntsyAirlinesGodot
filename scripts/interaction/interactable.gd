class_name Interactable
extends Node3D
## Something a player can use with E (a door, the cargo). Each player's Interactor picks the nearest
## available one, shows its prompt, and asks the server to run interact() on it.
## Extend this and override get_prompt() and interact(); override get_distance() if "where it is" isn't this node.

# Declaring Default/Const variables
const GROUP := &"interactable" # every Interactable joins this group so Interactors can find it

@export var interact_range: float = 2.5 # metres a player can use it from


# Called when the node enters the scene tree.
func _enter_tree() -> void:
	add_to_group(GROUP)


func get_prompt(_player: Node3D) -> String:
	## This function says what pressing E would do for a player right now ("" if they can't use it)
	# _player: the player asking
	return ""


func get_distance(player: Node3D) -> float:
	## This function says how far a player is from it, to pick the nearest one and check the range
	# player: the player asking
	return global_position.distance_to(player.global_position)


func can_interact(player: Node3D) -> bool:
	## This function says if a player is in range and has something to do here
	# player: the player asking
	return get_distance(player) <= interact_range and get_prompt(player) != ""


func interact(_id: int) -> void:
	## This function does what pressing E means (runs on the server only)
	# _id: the player who pressed E
	pass
