extends AnimatableBody3D
## One cargo crate. On the ground it is solid; while someone carries it, it floats in front of them.
## The cargo manager on the server decides who holds it. This script only shows that on every computer.

# Declaring Default/Const variables
const CARRY_OFF := Vector3(0, 0.7, 0.9) # where the crate's bottom sits from the holder's feet (up, in front)
const SOLID_LAYER := 1 # physics layer the crate is on while it sits on the ground

# Declaring tracking variables
var holder_id: int = 0 # peer carrying it (0 = nobody)
var loaded: bool = false # true once it is in the plane's hold


# Called every physics frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(_delta: float) -> void:
	# Guard case for a crate nobody is carrying
	if holder_id == 0:
		return

	# Guard case for a holder that isn't on this computer yet (or just left)
	var holder = get_tree().current_scene.get_node_or_null(str(holder_id))
	if holder == null:
		return

	# following the holder: in front of them, turned the same way
	global_transform = Transform3D(holder.global_basis, holder.global_transform * CARRY_OFF)


func set_holder(id: int) -> void:
	## This function marks who carries the crate (0 to let go)
	# id: peer carrying it
	holder_id = id

	# a carried crate stops being solid, so it doesn't push its holder around
	collision_layer = 0 if id != 0 else SOLID_LAYER


func place(spot: Transform3D) -> void:
	## This function puts the crate down somewhere
	# spot: where it goes (origin is the crate's bottom)
	set_holder(0)
	global_transform = spot
