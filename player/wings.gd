class_name Wings
extends Node3D

## Two visual wing panels. Their plane is defined by the controller's surface
## normal. Flyer velocity resolves the rotation around that normal without
## allowing wind to alter the displayed command.
const WING_SPAN := 2.4
const WING_ROOT_WIDTH := 0.25
const WING_CHORD := 1.1
const MIN_DIRECTION_LENGTH_SQUARED := 0.0001

var span_direction := Vector3.RIGHT


func _ready() -> void:
	add_child(_make_wing("LeftWing", -1.0))
	add_child(_make_wing("RightWing", 1.0))


func update_aerodynamic_pose(
		flight_velocity: Vector3,
		wing_surface_normal: Vector3,
		shoulder_position: Vector3
) -> void:
	if wing_surface_normal.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		return

	var surface_normal := wing_surface_normal.normalized()
	if flight_velocity.length_squared() >= MIN_DIRECTION_LENGTH_SQUARED:
		var flight_direction := flight_velocity.normalized()
		var requested_span_direction := flight_direction.cross(surface_normal)
		if requested_span_direction.length_squared() >= MIN_DIRECTION_LENGTH_SQUARED:
			requested_span_direction = requested_span_direction.normalized()
			if requested_span_direction.dot(span_direction) < 0.0:
				requested_span_direction = -requested_span_direction
			span_direction = requested_span_direction

	# At a 90 degree AoA, airflow and surface normal align and cannot define a
	# span direction. Keep the previous span, projected back into the wing plane.
	span_direction = span_direction - surface_normal * span_direction.dot(surface_normal)
	if span_direction.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		span_direction = _fallback_span_direction(surface_normal)
	else:
		span_direction = span_direction.normalized()

	var chord_back := span_direction.cross(surface_normal).normalized()
	global_position = shoulder_position
	global_basis = Basis(span_direction, surface_normal, chord_back)


func _fallback_span_direction(surface_normal: Vector3) -> Vector3:
	var reference := Vector3.RIGHT
	if absf(reference.dot(surface_normal)) > 0.9:
		reference = Vector3.FORWARD
	return (reference - surface_normal * reference.dot(surface_normal)).normalized()


func _make_wing(wing_name: String, side: float) -> MeshInstance3D:
	var wing := MeshInstance3D.new()
	wing.name = wing_name
	wing.mesh = _make_triangle_mesh(side)
	wing.material_override = _make_material()
	return wing


func _make_triangle_mesh(side: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array([
		Vector3(side * WING_ROOT_WIDTH, 0.0, -0.1),
		Vector3(side * WING_SPAN, 0.0, WING_CHORD * 0.55),
		Vector3(side * WING_ROOT_WIDTH, 0.0, WING_CHORD)
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.75, 1.0, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
