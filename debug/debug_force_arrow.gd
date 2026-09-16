class_name DebugForceArrow
extends Node3D

## Visual-only world-space arrow for inspecting a simulated force vector.
const WORLD_UNITS_PER_NEWTON := 0.003
const MIN_VISIBLE_FORCE := 1.0

var shaft: MeshInstance3D
var arrow_head: MeshInstance3D


func _ready() -> void:
	shaft = MeshInstance3D.new()
	shaft.mesh = _make_shaft_mesh()
	shaft.material_override = _make_material()
	add_child(shaft)

	arrow_head = MeshInstance3D.new()
	arrow_head.mesh = _make_arrow_head_mesh()
	arrow_head.material_override = _make_material()
	add_child(arrow_head)
	visible = false


func show_force(force: Vector3, origin: Vector3) -> void:
	global_position = origin
	if force.length_squared() < MIN_VISIBLE_FORCE * MIN_VISIBLE_FORCE:
		visible = false
		return

	visible = true
	global_basis = _basis_with_local_up(force.normalized())
	var arrow_length := force.length() * WORLD_UNITS_PER_NEWTON
	var head_length := minf(0.45, arrow_length * 0.28)
	var shaft_length := maxf(0.02, arrow_length - head_length)
	shaft.position.y = shaft_length * 0.5
	shaft.scale.y = shaft_length
	arrow_head.position.y = shaft_length + head_length * 0.5
	arrow_head.scale.y = head_length


func _basis_with_local_up(up_direction: Vector3) -> Basis:
	var reference_forward := Vector3.FORWARD
	if absf(reference_forward.dot(up_direction)) > 0.95:
		reference_forward = Vector3.RIGHT
	var right := reference_forward.cross(up_direction).normalized()
	var back := right.cross(up_direction).normalized()
	return Basis(right, up_direction, back)


func _make_shaft_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.035
	mesh.height = 1.0
	return mesh


func _make_arrow_head_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.12
	mesh.height = 1.0
	return mesh


func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.35, 0.1)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
