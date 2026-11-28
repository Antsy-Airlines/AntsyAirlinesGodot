class_name Airplane
extends Node3D
## The plane as a whole: one place to set its states (landing gear, propellers, doors) from gameplay code.
## The setters run on the server only; each part then syncs and animates itself on every computer.
## (Not named Plane: Godot already has a built-in Plane type.)

# Declaring Default/Const variables
@export var landing_gear: LandingGear # the wheels that retract into the fuselage
@export var propellers: Propellers # both propellers
@export var doors_root: Node3D # parent of every PlaneDoor (side doors and the cargo ramp)
@export var shift_handle: PlaneDoor # the cockpit lever (a hinged part, like a door)


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# the model's "-col" meshes import as one-sided trimeshes; players are inside the fuselage, so block both ways
	for s in find_children("*", "CollisionShape3D", true, false):
		if s.shape is ConcavePolygonShape3D:
			s.shape.backface_collision = true
	# TEMPORARY (testing): throwing the shift handle starts the propellers and retracts the gear
	shift_handle.toggled.connect(_on_shift_handle_toggled)


func set_gear_down(down: bool) -> void:
	## This function lowers or retracts the landing gear (server only)
	# down: true to lower, false to retract
	landing_gear.set_down(down)


func set_propellers_spinning(on: bool) -> void:
	## This function starts or stops the propellers (server only)
	# on: true to start, false to stop
	propellers.set_spinning(on)


func get_door(door_name: StringName) -> PlaneDoor:
	## This function gives one door by its node name under the doors root (null if there is none)
	# door_name: like "FrontDoorL" or "CargoDoor"
	return doors_root.get_node_or_null(NodePath(door_name)) as PlaneDoor


func set_door_open(door_name: StringName, open: bool) -> void:
	## This function opens or closes one door (server only)
	# door_name: like "FrontDoorL" or "CargoDoor"
	# open: true to open, false to close
	var door = get_door(door_name)
	# Guard case for a name that isn't a door
	if door == null:
		push_warning("Airplane has no door named %s" % door_name)
		return
	door.set_open(open)


func set_all_doors_open(open: bool) -> void:
	## This function opens or closes every door, the cargo ramp included (server only)
	# open: true to open, false to close
	for door in doors_root.get_children():
		if door is PlaneDoor:
			door.set_open(open)


func _on_shift_handle_toggled(on: bool) -> void:
	## This function reacts to the shift handle being thrown (TEMPORARY, for testing the plane's states)
	# on: true when the handle was pushed forward
	# Guard case for clients: the server sets the states and they sync to everyone
	if not multiplayer.is_server():
		return
	set_propellers_spinning(on)
	set_gear_down(not on)
