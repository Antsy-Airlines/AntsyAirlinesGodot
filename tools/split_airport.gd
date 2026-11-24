extends SceneTree
## One-time tool: cuts the Sketchfab airport pack into separate piece scenes we can place freely.
## Each piece gets its mesh, the pack's own collider as its collision, and the shared airport material.
## Run from the project folder:
##   godot --headless --path . --script res://tools/split_airport.gd
## The raw download stays in assets/airport/source/ (Godot ignores that folder, so it never re-imports).

# Declaring Default/Const variables
const SOURCE := "res://assets/airport/source/airport_pack.gltf" # the raw Sketchfab download
const OUT_DIR := "res://assets/airport/pieces" # where the piece scenes go
const PALETTE := "res://assets/airport/airport_palette.png" # the pack's only colour texture
const MATERIAL_PATH := "res://assets/airport/airport_material.tres" # shared by every piece
const VISIBLE_MAT := "AIRPORT" # material the pack uses on meshes you see
const COLLIDER_MAT := "COLLIDERS" # material the pack uses on its collision meshes
const SAME_SPOT := 0.05 # metres; a collider sits exactly on its piece's origin

# pack node name -> our piece name (pieces not listed here are skipped, like the 4 copies of the container)
const NAMES := {
	"LandingTrack1Straight": "runway_straight",
	"LandingTrack2Curve": "runway_curve_long",
	"LandingTrack3Curve2": "runway_curve_round",
	"LandingTrack4Curve3": "runway_curve_small",
	"LandingTrack5StraightAngled": "runway_angled",
	"02_ControlTower": "control_tower",
	"03_AirplaneStairs": "airplane_stairs",
	"04_Hangar": "hangar",
	"05_Container": "baggage_container",
	"06_Tunnel": "jet_bridge",
	"07_Modulo1": "terminal_1",
	"07_Modulo2": "terminal_2",
	"08_CheckInDesk": "check_in_desk",
	"09_SecurityCheck": "security_check",
	"10_Chairs": "chairs",
	"11_BoardingAreaDesk": "boarding_desk",
	"12_1_BaggageClaimBand": "baggage_belt_1",
	"12_2_BaggageClaimBand": "baggage_belt_2",
	"12_3_BaggageClaimBand": "baggage_belt_3",
	"12_4_BaggageClaimBand": "baggage_belt_4",
	"12_5_BaggageClaimBand": "baggage_belt_5",
	"13_Cafe": "cafe",
	"14_Trashcan": "trash_can",
	"15_Advertising": "ad_stand",
	"16_DepartureSign": "departure_sign",
	"17_1_Model": "prop_1",
	"17_2_Model": "security_camera",
	"17_3_Model": "luggage_trolley",
	"17_4_Model": "check_in_kiosk",
	"17_5_Model": "ticket_machine",
	"17_6_Model": "prop_6",
	"17_7_Model": "suitcase",
	"17_8_Model": "backpack",
	"17_9_1_Model": "queue_post_belt",
	"17_9_2_Model": "queue_post",
	"17_10_Model": "plant",
	"18_1_Airplane": "airplane_1",
	"18_2_Airplane": "airplane_2",
	"18_3_Airplane": "airplane_3",
	"18_4_Airplane": "airplane_4",
	"19_Firetruck": "fire_truck",
	"20_PassengerBus": "passenger_bus",
	"21_1_BaggageTruck": "baggage_truck_1",
	"21_2_BaggageTruck": "baggage_truck_2",
	"21_3_BaggageTruck": "baggage_truck_3",
}
const NO_COLLISION := ["runway_straight", "runway_curve_long", "runway_curve_round", "runway_curve_small", "runway_angled"] # flat, the ground handles them

# piece name -> boxes (piece-local, metres) whose triangles are cut out of the mesh and the collision
const CUTS := {
	"terminal_1": [AABB(Vector3(19.0, 0.45, -3.8), Vector3(0.2, 4.2, 7.6))], # airside entrance glass, a sliding door goes here
}

# Declaring tracking variables
var _pack: Node3D # the loaded pack, kept until the first frame
var _done: bool = false # true once the pieces are saved


func _initialize() -> void:
	# loading the raw glTF without Godot's importer
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	var err = doc.append_from_file(SOURCE, state)
	if err != OK:
		push_error("Couldn't read %s: %s" % [SOURCE, error_string(err)])
		quit(1)
		return
	_pack = doc.generate_scene(state)
	root.add_child(_pack) # in the tree so global transforms work (ready from the first frame)


func _process(_delta: float) -> bool:
	# Guard case for frames after the work is done
	if _done:
		return true
	_done = true

	var pack = _pack
	var mat = _make_material()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# sorting the pack's meshes into the ones you see and the colliders
	var seen = []
	var colliders = []
	for mesh_node in pack.find_children("*", "MeshInstance3D", true, false):
		if _has_material(mesh_node, COLLIDER_MAT):
			colliders.append(mesh_node)
		elif _has_material(mesh_node, VISIBLE_MAT):
			seen.append(mesh_node)

	# saving one scene per piece
	var count = 0
	for mesh_node in seen:
		var pack_name = String(mesh_node.get_parent().name)
		if not NAMES.has(pack_name):
			continue
		_save_piece(NAMES[pack_name], mesh_node, colliders, mat)
		count += 1

	print("[split] saved %d pieces to %s" % [count, OUT_DIR])
	pack.free() # letting go of the pack before closing
	return true # ends the tool


func _make_material() -> StandardMaterial3D:
	## This function saves the one material every piece shares (flat colours from the palette)
	var mat = StandardMaterial3D.new()
	mat.resource_name = "Airport"
	mat.albedo_texture = load(PALETTE)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST # palette squares stay crisp
	mat.roughness = 0.9
	ResourceSaver.save(mat, MATERIAL_PATH)
	return load(MATERIAL_PATH)


func _has_material(mesh_node: MeshInstance3D, mat_name: String) -> bool:
	## This function says if a mesh uses the pack material with this name
	# mesh_node: a mesh from the pack
	# mat_name: "AIRPORT" or "COLLIDERS"
	for i in mesh_node.mesh.get_surface_count():
		var mat = mesh_node.mesh.surface_get_material(i)
		if mat != null and mat.resource_name == mat_name:
			return true
	return false


func _save_piece(piece_name: String, mesh_node: MeshInstance3D, colliders: Array, mat: Material) -> void:
	## This function builds and saves one piece: its mesh plus the collider sitting on the same spot
	# piece_name: our name for it, also the file name
	# mesh_node: the visible mesh from the pack
	# colliders: every collider mesh in the pack
	# mat: the shared airport material
	var origin = mesh_node.get_parent().global_position # the pack's pivot for this piece
	var collider = _find_collider(origin, colliders)
	var wants_body = collider != null and not piece_name in NO_COLLISION

	# root is a static body when the piece blocks players
	var piece = StaticBody3D.new() if wants_body else Node3D.new()
	piece.name = piece_name.to_pascal_case()

	var cuts = CUTS.get(piece_name, []) # openings to cut out of this piece

	# the visible mesh, moved so the piece's pivot is at 0,0,0
	var look_xf = Transform3D(mesh_node.global_basis, mesh_node.global_position - origin)
	var mesh = _cut_mesh(mesh_node.mesh, look_xf, cuts) if not cuts.is_empty() else mesh_node.mesh.duplicate()
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, mat)
	var look = MeshInstance3D.new()
	look.name = "Mesh"
	look.mesh = mesh
	look.transform = look_xf
	piece.add_child(look)
	look.owner = piece

	# the pack's collider as an exact shape (pieces never move, so this is fine)
	if wants_body:
		var shape = CollisionShape3D.new()
		shape.name = "Shape"
		shape.transform = Transform3D(collider.global_basis, collider.global_position - origin)
		var trimesh = collider.mesh.create_trimesh_shape()
		trimesh.set_faces(_cut_faces(trimesh.get_faces(), shape.transform, cuts))
		trimesh.backface_collision = true # the pack's walls are one-sided, so players walked out through them and got stuck
		shape.shape = trimesh
		piece.add_child(shape)
		shape.owner = piece

	print("[split] %s at %s" % [piece_name, origin]) # where the artist put it
	var scene = PackedScene.new()
	scene.pack(piece)
	ResourceSaver.save(scene, "%s/%s.scn" % [OUT_DIR, piece_name])
	piece.free() # the saved file has it now


func _cut_mesh(mesh: Mesh, xf: Transform3D, cuts: Array) -> ArrayMesh:
	## This function rebuilds a mesh without the triangles that sit inside the cut boxes
	# mesh: the pack's visible mesh
	# xf: where the mesh sits inside the piece
	# cuts: boxes to cut out, in piece space
	var cut_mesh = ArrayMesh.new()
	for i in mesh.get_surface_count():
		var arrays = mesh.surface_get_arrays(i)
		var verts = arrays[Mesh.ARRAY_VERTEX]
		var idx = arrays[Mesh.ARRAY_INDEX]

		# a mesh without an index list gets one, so its triangles can be dropped the same way
		if idx == null or idx.is_empty():
			idx = PackedInt32Array(range(verts.size()))

		# keeping every triangle whose middle is outside the cuts
		var kept = PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var mid = xf * ((verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0)
			if not _in_cuts(mid, cuts):
				kept.append_array([idx[t], idx[t + 1], idx[t + 2]])

		arrays[Mesh.ARRAY_INDEX] = kept
		cut_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return cut_mesh


func _cut_faces(faces: PackedVector3Array, xf: Transform3D, cuts: Array) -> PackedVector3Array:
	## This function drops the collision triangles that sit inside the cut boxes
	# faces: the collision triangles, three points each
	# xf: where the collision sits inside the piece
	# cuts: boxes to cut out, in piece space
	var kept = PackedVector3Array()
	for t in range(0, faces.size(), 3):
		var mid = xf * ((faces[t] + faces[t + 1] + faces[t + 2]) / 3.0)
		if not _in_cuts(mid, cuts):
			kept.append_array([faces[t], faces[t + 1], faces[t + 2]])
	return kept


func _in_cuts(point: Vector3, cuts: Array) -> bool:
	## This function says if a point is inside any of the cut boxes
	# point: a triangle's middle, in piece space
	# cuts: boxes to cut out
	for box in cuts:
		if box.has_point(point):
			return true
	return false


func _find_collider(origin: Vector3, colliders: Array) -> MeshInstance3D:
	## This function finds the collider whose pivot is on the same spot as a piece (or null)
	# origin: the piece's pivot
	# colliders: every collider mesh in the pack
	for collider in colliders:
		if collider.get_parent().global_position.distance_to(origin) < SAME_SPOT:
			return collider
	return null
