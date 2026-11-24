extends Node3D
## Cargo loading: players press E to pick up a crate, carry it out to the plane and drop it on the cargo hold pad.
## The server decides who holds what and what counts as loaded. Every computer just shows the result.

signal cargo_changed(loaded: int, total: int) # everyone: how many crates are in the hold
signal prompt_changed(text: String) # this computer: what the E hint should say ("" hides it)

# Declaring Default/Const variables
const PICK_RANGE := 2.5 # metres a player can reach a crate from
const DROP_AHEAD := 1.3 # metres in front of the player a crate is put down
const HOLD_COLS := 3 # crates per row in the hold
const HOLD_GAP := 1.1 # metres between crates in the hold

@export var hold_size: Vector2 = Vector2(6, 5) # width (x) and depth (z) of the hold pad, in metres

# Getting References for everyone in the scene
@onready var _crates: Node3D = $Crates # every crate in this level
@onready var _hold: Node3D = $HoldZone # middle of the cargo hold pad next to the plane

# Declaring tracking variables
var _prompt: String = "" # last hint we showed, so we only send changes


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# showing the counter from the start (deferred so the HUD is connected first)
	_emit_count.call_deferred()

	# the server drops crates for players who leave; everyone else asks where the crates are
	if multiplayer.is_server():
		HighLevelNetworkHandler.player_left.connect(_on_player_left)
	else:
		_request_state.rpc_id(1)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	# updating the E hint for our own player
	var text = _hint_for(_player(multiplayer.get_unique_id()))
	if text != _prompt:
		_prompt = text
		prompt_changed.emit(text)


func _unhandled_input(event: InputEvent) -> void:
	# only E matters here
	if not event.is_action_pressed("interact"):
		return

	# Guard case for a computer without a player (the server)
	if _player(multiplayer.get_unique_id()) == null:
		return

	_request_interact.rpc_id(1) # the server decides if this is a pick up or a drop


func _hint_for(me: Node3D) -> String:
	## This function says what pressing E would do for a player right now ("" if nothing)
	# me: our own player, or null
	# Guard case for no player
	if me == null:
		return ""

	# carrying: E drops it (or loads it if we are on the pad)
	var held = _held_by(me.name.to_int())
	if held != null:
		return "Press E to load the crate" if _in_hold(_drop_spot(me)) else "Press E to drop the crate"

	# a crate in reach: E picks it up
	if _nearest_free(me.global_position) != null:
		return "Press E to pick up"
	return ""


@rpc("any_peer", "call_local", "reliable")
func _request_interact() -> void:
	## This function runs on the server when a player presses E
	var id = _sender_id()
	var player = _player(id)

	# Guard case for a player the server doesn't know
	if player == null:
		return

	# holding a crate: putting it down
	var held = _held_by(id)
	if held != null:
		_drop(held, player)
		return

	# hands free: picking up the nearest crate in reach
	var crate = _nearest_free(player.global_position)
	if crate != null:
		_set_holder.rpc(crate.name, id)


func _drop(crate: Node3D, player: Node3D) -> void:
	## This function puts a carried crate down: in the hold if the player is at the pad, else on the ground
	# crate: the crate being carried
	# player: who carries it
	var spot = _drop_spot(player)

	# on the pad it counts as loaded and goes in the next free spot in the hold
	if _in_hold(spot):
		_set_loaded.rpc(crate.name, _loaded_count())
		return

	_set_placed.rpc(crate.name, Transform3D(Basis(Vector3.UP, player.rotation.y), _ground_at(spot)))


func _drop_spot(player: Node3D) -> Vector3:
	## This function finds where a crate would land in front of a player (stopping short of walls)
	# player: who is dropping
	var forward = player.global_basis.z # the player rig faces +z
	var from = player.global_position + Vector3.UP
	var to = from + forward * DROP_AHEAD

	# checking for a wall between the player and the drop spot
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		to = hit.position - forward * 0.5 # backing off so the crate isn't inside the wall
	return to


func _ground_at(spot: Vector3) -> Vector3:
	## This function finds the floor under a spot, so crates sit on it
	# spot: point above the floor
	var query = PhysicsRayQueryParameters3D.create(spot + Vector3.UP, spot + Vector3.DOWN * 5.0)

	# ignoring carried crates, they aren't solid
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		return hit.position
	return spot


@rpc("authority", "call_local", "reliable")
func _set_holder(crate_name: String, id: int) -> void:
	## This function runs on everyone when a player picks up a crate
	# crate_name: which crate
	# id: who picked it up
	_crates.get_node(crate_name).set_holder(id)


@rpc("authority", "call_local", "reliable")
func _set_placed(crate_name: String, spot: Transform3D) -> void:
	## This function runs on everyone when a crate is put down on the ground
	# crate_name: which crate
	# spot: where it now sits
	_crates.get_node(crate_name).place(spot)


@rpc("authority", "call_local", "reliable")
func _set_loaded(crate_name: String, slot: int) -> void:
	## This function runs on everyone when a crate is put in the hold
	# crate_name: which crate
	# slot: its place in the hold (0 for the first crate loaded)
	var crate = _crates.get_node(crate_name)
	crate.loaded = true
	crate.place(_hold_slot(slot))
	_emit_count()


func _hold_slot(slot: int) -> Transform3D:
	## This function gives the spot for the nth crate in the hold, in neat rows
	# slot: 0 for the first crate loaded
	var col = slot % HOLD_COLS
	var row = slot / HOLD_COLS
	var off_vec = Vector3((col - (HOLD_COLS - 1) / 2.0) * HOLD_GAP, 0, (row - 0.5) * HOLD_GAP)
	return _hold.global_transform * Transform3D(Basis(), off_vec)


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	## This function runs on the server when a computer loads the airport and asks where every crate is
	var states = []
	for crate in _crates.get_children():
		states.append([crate.name, crate.holder_id, crate.loaded, crate.global_transform])
	_apply_state.rpc_id(_sender_id(), states)


@rpc("authority", "call_remote", "reliable")
func _apply_state(states: Array) -> void:
	## This function runs on a client with the server's view of every crate
	# states: [name, holder, loaded, transform] for each crate
	for state in states:
		var crate = _crates.get_node(String(state[0]))
		crate.loaded = state[2]
		crate.place(state[3])
		crate.set_holder(state[1])
	_emit_count()


func _on_player_left(id: int) -> void:
	## This function drops the crate of a player who left, right where they were
	# id: the player who left
	var held = _held_by(id)
	if held != null:
		_set_placed.rpc(held.name, Transform3D(Basis(Vector3.UP, held.rotation.y), _ground_at(held.global_position)))


func _nearest_free(pos: Vector3) -> Node3D:
	## This function finds the closest crate in reach that nobody holds and isn't loaded (or null)
	# pos: where the player stands
	var best = null
	var best_dist = PICK_RANGE
	for crate in _crates.get_children():
		# skipping crates that are taken or already in the plane
		if crate.holder_id != 0 or crate.loaded:
			continue

		# measuring on the floor only, so height doesn't matter
		var dif = crate.global_position - pos
		var dist = Vector2(dif.x, dif.z).length()
		if dist < best_dist:
			best = crate
			best_dist = dist
	return best


func _held_by(id: int) -> Node3D:
	## This function finds the crate a player carries (or null)
	# id: the player
	for crate in _crates.get_children():
		if crate.holder_id == id:
			return crate
	return null


func _in_hold(spot: Vector3) -> bool:
	## This function says if a spot is on the cargo hold pad
	# spot: where a crate would land
	var local = _hold.to_local(spot)
	return absf(local.x) <= hold_size.x / 2.0 and absf(local.z) <= hold_size.y / 2.0


func _loaded_count() -> int:
	## This function counts the crates already in the hold
	var count = 0
	for crate in _crates.get_children():
		if crate.loaded:
			count += 1
	return count


func _emit_count() -> void:
	## This function tells the HUD how many crates are loaded
	cargo_changed.emit(_loaded_count(), _crates.get_child_count())


func _player(id: int) -> Node3D:
	## This function finds a player by peer id (players are named by their id)
	# id: the peer
	return get_tree().current_scene.get_node_or_null(str(id))


func _sender_id() -> int:
	## This function gives the peer that sent the current message (ourselves when it was a local call)
	var id = multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()
