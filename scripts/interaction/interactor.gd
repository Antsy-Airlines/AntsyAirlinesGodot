class_name Interactor
extends Node
## Sits under a player. For our own player it finds the nearest Interactable we can use, shows its E prompt,
## and asks the server to use it when E is pressed. The server checks again before anything happens.

signal prompt_changed(text: String) # this computer: what the E hint should say ("" hides it)

# Declaring Default/Const variables
const SERVER_SLACK := 0.75 # extra metres the server allows, since it sees our position a little late

# Getting References for everyone in the scene
@onready var _player: Node3D = get_parent() # the player this belongs to

# Declaring tracking variables
var prompt: String = "" # what the E hint says right now
var target: Interactable = null # what pressing E would use right now (null if nothing)


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# only our own player looks for things to use; the others just take requests on the server
	var mine = is_multiplayer_authority()
	set_process(mine)
	set_process_unhandled_input(mine)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	target = _nearest_usable()
	var text = target.get_prompt(_player) if target != null else ""
	if text != prompt:
		prompt = text
		prompt_changed.emit(text)


func _unhandled_input(event: InputEvent) -> void:
	# only E matters here
	if not event.is_action_pressed("interact"):
		return

	# Guard case for nothing to use
	if target == null:
		return

	get_viewport().set_input_as_handled()
	_request_interact.rpc_id(1, target.get_path())


func _nearest_usable() -> Interactable:
	## This function finds the closest Interactable our player can use right now (or null)
	var best: Interactable = null
	var best_dist = INF
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var thing = node as Interactable
		# Guard case for things out of reach or with nothing to do
		if thing == null or not thing.can_interact(_player):
			continue

		var dist = thing.get_distance(_player)
		if dist < best_dist:
			best = thing
			best_dist = dist
	return best


@rpc("any_peer", "call_local", "reliable")
func _request_interact(target_path: NodePath) -> void:
	## This function runs on the server when this player presses E on something
	# target_path: what they pressed E on
	# Guard case for someone pressing E for a player that isn't theirs
	var sender = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return

	# Guard case for a path that isn't something usable
	var thing = get_node_or_null(target_path) as Interactable
	if thing == null:
		return

	# Guard case for being out of reach or nothing to do, as the server sees it
	if thing.get_distance(_player) > thing.interact_range + SERVER_SLACK or thing.get_prompt(_player) == "":
		return

	thing.interact(get_multiplayer_authority())
