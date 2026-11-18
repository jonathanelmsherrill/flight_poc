class_name Wings
extends Node3D

const WING_SPAN := 2.4 # meters, actual wing span is actually twice this
const WING_ROOT_WIDTH := 0.25 #How far apart in the middle
const WING_CHORD := 1.1 # How wide should the base of the triangle, at the 'root' be

const FLAP_UP_ANGLE := deg_to_rad(40.0)
const FLAP_DOWN_ANGLE := deg_to_rad(-30.0)
const FLAP_DURATION := 0.4 # seconds for the whole up-down-level cycle

var left_wing: Node3D
var right_wing: Node3D
var flap_tween: Tween


## Hook the wings onto attach_point and build one triangle on either side.
func configure(attach_point: Node3D) -> void:
	attach_point.add_child(self)
	left_wing = make_wing("Left", -1.0)
	right_wing = make_wing("Right", 1.0)


## Pivots the wings so their surface faces wing_normal with the span toward
## body_right. Forward follows from those two, assuming the wings are never
## upside down.
func direct_wings(wing_normal: Vector3) -> void:
	var up := wing_normal.normalized()
	var body_right := get_parent_node_3d().global_basis.x
	var right := body_right - up * body_right.dot(up) # Keep the span in the wing plane; issue here if we ever point sideways. 
	if right.length_squared() < 0.0001:
		return # Right is along the normal; keep the last pose
	right = right.normalized()
	var back := right.cross(up)
	global_basis = Basis(right, up, back)


## One flap: up, down, then back to level, over FLAP_DURATION.
func flap() -> void:
	if flap_tween:
		flap_tween.kill()
	flap_tween = create_tween()
	flap_tween.tween_method(set_flap_angle, 0.0, FLAP_UP_ANGLE, FLAP_DURATION * 0.25)
	flap_tween.tween_method(set_flap_angle, FLAP_UP_ANGLE, FLAP_DOWN_ANGLE, FLAP_DURATION * 0.5)
	flap_tween.tween_method(set_flap_angle, FLAP_DOWN_ANGLE, 0.0, FLAP_DURATION * 0.25)


## Rotates each wing about the forward axis; positive raises both tips.
func set_flap_angle(angle: float) -> void:
	left_wing.rotation.z = -angle
	right_wing.rotation.z = angle


func make_wing(wing_name: String, side: float) -> Node3D:
	var wing := Node3D.new()
	wing.name = wing_name + "Wing"
	add_child(wing)
	var wing_mesh := MeshInstance3D.new()
	wing_mesh.name = wing_name
	wing_mesh.mesh = make_triangle_mesh(side)
	wing_mesh.material_override = make_material()
	wing.add_child(wing_mesh)
	return wing

## Actually make the triangle that is the wing. 
func make_triangle_mesh(side: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array([
		Vector3(side * WING_ROOT_WIDTH, 0.0, -0.1),
		Vector3(side * WING_SPAN, 0.0, WING_CHORD * 0.55),
		Vector3(side * WING_ROOT_WIDTH, 0.0, WING_CHORD),
		])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.75, 1.0, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
