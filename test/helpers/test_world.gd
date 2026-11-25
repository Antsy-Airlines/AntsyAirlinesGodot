extends RefCounted
## Test world: puts a root node into the tree as the current scene (like the lobby is in the game),
## optionally with the airport inside it, and adds players named by their peer id.
## Offline we are peer 1, so player "1" is the one our input moves; other players only move when placed.

# Declaring Default/Const variables
const AIRPORT_PATH := "res://scenes/levels/airport.tscn" # the map
const PLAYER_SCENE := preload("res://scenes/player/player.tscn") # the real player

# Declaring tracking variables
var root: Node3D # stands in for the lobby: players and the airport go under it
var airport: Node3D # the loaded airport (null if not asked for)
var _tree: SceneTree # the running tree
var _old_scene: Node # the current scene before the test, put back in close()


func _init(with_airport: bool = true) -> void:
	_tree = Engine.get_main_loop()

	# making our root the current scene, since players are looked up there
	root = Node3D.new()
	root.name = "TestWorld"
	_tree.root.add_child(root)
	_old_scene = _tree.current_scene
	_tree.current_scene = root

	if with_airport:
		airport = load(AIRPORT_PATH).instantiate()
		root.add_child(airport)


func add_player(id: int, pos: Vector3, yaw_deg: float = 0.0) -> CharacterBody3D:
	## This function adds a real player named by peer id and puts it somewhere
	# id: peer id (1 is us)
	# pos: where its feet go
	# yaw_deg: which way it faces (90 = facing +x)
	var player = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.username = "P%d" % id
	root.add_child(player)
	place(player, pos, yaw_deg)
	return player


func add_marker(id: int, pos: Vector3, yaw_deg: float = 0.0) -> Node3D:
	## This function adds a plain node named by peer id, as a light stand-in for a player
	# id: peer id
	# pos: where it goes
	# yaw_deg: which way it faces
	var marker = Node3D.new()
	marker.name = str(id)
	root.add_child(marker)
	marker.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)
	return marker


func place(node: Node3D, pos: Vector3, yaw_deg: float = 0.0) -> void:
	## This function teleports a player or marker, facing a direction
	# node: what to move
	# pos: where it goes
	# yaw_deg: which way it faces (90 = facing +x)
	node.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)
	if node is CharacterBody3D:
		node.velocity = Vector3.ZERO


func cargo() -> Node3D:
	## This function gives the cargo manager of the airport
	return airport.get_node("Cargo")


func crate(crate_name: String) -> Node3D:
	## This function gives one crate by name
	# crate_name: like "Crate1" or "HeavyCrate1"
	return airport.get_node("Cargo/Crates/" + crate_name)


func close() -> void:
	## This function removes the test world and puts the old current scene back
	## (tests wait with gdUnit's own await_millis / await_idle_frame, since awaiting inside this helper confuses gdUnit)
	_tree.current_scene = _old_scene
	root.queue_free()
