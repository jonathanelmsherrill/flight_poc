class_name Wings
extends Node3D

## Two articulated visual wings. Their resting plane is defined by the
## controller's surface normal. Flyer velocity resolves the rotation around
## that normal without allowing wind to alter the displayed command.
const WING_ROOT_OFFSET := 0.24
const SEGMENT_LENGTHS := [0.76, 0.74, 0.66]
const SEGMENT_CHORDS := [1.05, 0.82, 0.58]
const JOINT_NAMES := [&"ShoulderJoint", &"ElbowJoint", &"WristJoint"]
const MIN_DIRECTION_LENGTH_SQUARED := 0.0001

var span_direction := Vector3.RIGHT

@onready var wing_animation: WingAnimation = $WingAnimation


func _ready() -> void:
	var left_joints := _make_wing("LeftWing", -1.0)
	var right_joints := _make_wing("RightWing", 1.0)
	wing_animation.configure(left_joints, right_joints)


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


func _make_wing(wing_name: String, side: float) -> Array[Node3D]:
	var wing_root := Node3D.new()
	wing_root.name = wing_name
	add_child(wing_root)

	var joints: Array[Node3D] = []
	var parent := wing_root
	for segment_index in SEGMENT_LENGTHS.size():
		var joint := Node3D.new()
		joint.name = JOINT_NAMES[segment_index]
		joint.position = Vector3(
				side * (WING_ROOT_OFFSET if segment_index == 0 else SEGMENT_LENGTHS[segment_index - 1]),
				0.0,
				0.0 if segment_index == 0 else SEGMENT_CHORDS[segment_index - 1] * 0.08
		)
		parent.add_child(joint)

		var panel := MeshInstance3D.new()
		panel.name = "Panel"
		panel.mesh = _make_triangle_mesh(
				side,
				SEGMENT_LENGTHS[segment_index],
				SEGMENT_CHORDS[segment_index]
		)
		panel.material_override = _make_material(segment_index)
		joint.add_child(panel)

		joints.append(joint)
		parent = joint
	return joints


func _make_triangle_mesh(side: float, length: float, chord: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array([
		Vector3(0.0, 0.0, -chord * 0.12),
		Vector3(side * length, 0.0, chord * 0.08),
		Vector3(0.0, 0.0, chord * 0.88),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_material(segment_index: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(
			0.35 + segment_index * 0.04,
			0.75 - segment_index * 0.04,
			1.0,
			0.85
	)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
