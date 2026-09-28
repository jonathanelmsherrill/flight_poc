class_name SimpleWingAnimation
extends WingAnimation

## Original programmer-art wings: one triangle per side and a short body pulse
## for every beat. As a child of Wings, the triangles inherit the current
## shoulder/back attachment point and aerodynamic orientation.
const WING_SPAN := 2.4
const WING_ROOT_WIDTH := 0.25
const WING_CHORD := 1.1
const PULSE_SCALE := Vector3(1.25, 0.85, 1.25)
const PULSE_IN_DURATION := 0.08
const PULSE_OUT_DURATION := 0.18

var _body_visual: Node3D
var _flap_tween: Tween


func configure(body_visual: Node3D, _fast_power_stroke_airspeed: float) -> void:
	_body_visual = body_visual
	add_child(_make_wing("LeftWing", -1.0))
	add_child(_make_wing("RightWing", 1.0))


func play_beat(_request: WingBeatAnimationRequest) -> void:
	if not is_instance_valid(_body_visual):
		push_warning("SimpleWingAnimation needs a body visual to pulse.")
		return
	if _flap_tween:
		_flap_tween.kill()
	_body_visual.scale = Vector3.ONE
	_flap_tween = create_tween()
	_flap_tween.tween_property(
			_body_visual,
			"scale",
			PULSE_SCALE,
			PULSE_IN_DURATION
	)
	_flap_tween.tween_property(
			_body_visual,
			"scale",
			Vector3.ONE,
			PULSE_OUT_DURATION
	)


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
		Vector3(side * WING_ROOT_WIDTH, 0.0, WING_CHORD),
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
