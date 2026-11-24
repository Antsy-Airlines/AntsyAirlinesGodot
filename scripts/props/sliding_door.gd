extends Node3D
## Automatic glass door: the two middle panels slide apart when a player walks up, and close once nobody is near.
## Every computer runs it on its own. Player positions are synced, so the door opens the same way for everyone.

# Declaring Default/Const variables
@export var slide_distance: float = 1.9 # metres each panel slides to open (one panel width)
@export var slide_time: float = 0.4 # seconds to open or close

# Getting References for everyone in the scene
@onready var _left_panel: AnimatableBody3D = $LeftPanel # slides to the left (-x) to open
@onready var _right_panel: AnimatableBody3D = $RightPanel # slides to the right (+x) to open
@onready var _sensor: Area3D = $Sensor # players inside this box open the door

# Declaring tracking variables
var _near: int = 0 # players standing in the sensor
var _left_closed: Vector3 # left panel's spot when closed
var _right_closed: Vector3 # right panel's spot when closed
var _tween: Tween # the slide that is playing, if any


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# remembering where the panels sit when closed
	_left_closed = _left_panel.position
	_right_closed = _right_panel.position

	_sensor.body_entered.connect(_on_body_entered)
	_sensor.body_exited.connect(_on_body_exited) # also fires when a player leaves the game


func _on_body_entered(body: Node3D) -> void:
	## This function opens the door when the first player walks up
	# body: whatever walked into the sensor
	# Guard case for things that aren't players (walls, desks, the panels)
	if not body is CharacterBody3D:
		return

	_near += 1
	if _near == 1:
		_slide(true)


func _on_body_exited(body: Node3D) -> void:
	## This function closes the door when the last player walks away
	# body: whatever left the sensor
	# Guard case for things that aren't players
	if not body is CharacterBody3D:
		return

	_near = maxi(_near - 1, 0)
	if _near == 0:
		_slide(false)


func _slide(open: bool) -> void:
	## This function slides both panels open or closed
	# open: true to open, false to close
	var off_vec = Vector3(slide_distance, 0, 0) if open else Vector3.ZERO

	# stopping a slide that is halfway, so the door can turn around
	if _tween:
		_tween.kill()

	# moving both panels at the same time
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_left_panel, "position", _left_closed - off_vec, slide_time)
	_tween.tween_property(_right_panel, "position", _right_closed + off_vec, slide_time)
