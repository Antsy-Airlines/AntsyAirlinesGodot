extends AnimatableBody3D
## One cargo crate. On the ground it is solid; while someone carries it, it floats in front of them.
## Heavy crates need two players: one grabs a side, and it only lifts once a second player grabs the other.
## The cargo manager on the server decides who holds it. This script only shows that on every computer.

# Declaring Default/Const variables
const CARRY_OFF := Vector3(0, 0.7, 0.9) # where the crate's bottom sits from the holder's feet (up, in front)
const HEAVY_LIFT := 0.4 # metres a heavy crate is lifted off the floor between its two carriers
const SOLID_LAYER := 1 # physics layer the crate is on while it sits on the ground

@export var heavy: bool = false # true for crates that need two players to lift

# Declaring tracking variables
var holder_id: int = 0 # peer carrying it, or the first to grab a heavy crate (0 = nobody)
var helper_id: int = 0 # heavy crates: the second player carrying it (0 = nobody)
var loaded: bool = false # true once it is in the plane's hold


# Called every physics frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(_delta: float) -> void:
	# Guard case for a crate still on the ground
	if not is_lifted():
		return

	# Guard case for a holder that isn't on this computer yet (or just left)
	var holder = _find(holder_id)
	if holder == null:
		return

	# light crate: following the holder, in front of them and turned the same way
	if not heavy:
		global_transform = Transform3D(holder.global_basis, holder.global_transform * CARRY_OFF)
		return

	# Guard case for a helper that isn't on this computer yet (or just left)
	var helper = _find(helper_id)
	if helper == null:
		return

	# heavy crate: halfway between the two carriers, turned along the line between them
	var mid = (holder.global_position + helper.global_position) / 2.0
	var dif = helper.global_position - holder.global_position
	global_transform = Transform3D(Basis(Vector3.UP, atan2(dif.x, dif.z)), mid + Vector3.UP * HEAVY_LIFT)


func is_lifted() -> bool:
	## This function says if the crate is off the ground (heavy crates need both sides held)
	if heavy:
		return holder_id != 0 and helper_id != 0
	return holder_id != 0


func set_holders(id: int, help_id: int = 0) -> void:
	## This function marks who carries the crate (0, 0 to let go)
	# id: peer carrying it, or the first to grab a heavy crate
	# help_id: second player on a heavy crate
	holder_id = id
	helper_id = help_id

	# a lifted crate stops being solid, so it doesn't push its carriers around
	collision_layer = 0 if is_lifted() else SOLID_LAYER


func place(spot: Transform3D) -> void:
	## This function puts the crate down somewhere
	# spot: where it goes (origin is the crate's bottom)
	set_holders(0, 0)
	global_transform = spot


func _find(id: int) -> Node3D:
	## This function finds a player by peer id (players are named by their id)
	# id: the peer
	return get_tree().current_scene.get_node_or_null(str(id))
