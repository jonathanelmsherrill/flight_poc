class_name Ai3ptWingAnimation1
extends WingAnimation

## Three-panel experimental wing animation. Player supplies the exact physical
## power and recovery windows so the visible stroke follows the applied force.
const JOINT_COUNT := 3
const WING_ROOT_OFFSET := 0.24
const SEGMENT_LENGTHS := [0.76, 0.74, 0.66]
const SEGMENT_CHORDS := [1.05, 0.82, 0.58]
const JOINT_NAMES := [&"ShoulderJoint", &"ElbowJoint", &"WristJoint"]

@export_group("Airspeed Response")
@export_range(0.01, 100.0, 0.1) var airspeed_for_fast_beat := 22.0
@export_range(1.0, 90.0) var slow_beat_angle_degrees := 72.0
@export_range(1.0, 90.0) var fast_beat_angle_degrees := 28.0

@export_group("Wingbeat Shape")
@export_range(0.1, 1.0) var chord_stroke_amplitude_multiplier := 0.65
@export_range(0.0, 0.5) var forward_downstroke_ratio := 0.15
@export_range(0.1, 0.5) var recovery_fold_fraction := 0.28
@export_range(0.05, 0.35) var recovery_settle_fraction := 0.15

var _left_joints: Array[Node3D] = []
var _right_joints: Array[Node3D] = []
var _flap_tween: Tween


func configure(_body_visual: Node3D, fast_power_stroke_airspeed: float) -> void:
	airspeed_for_fast_beat = fast_power_stroke_airspeed
	_left_joints = _make_wing("LeftWing", -1.0)
	_right_joints = _make_wing("RightWing", 1.0)
	_set_pose(_zero_pose(), _zero_pose())


func play_beat(request: WingBeatAnimationRequest) -> void:
	if _left_joints.size() != JOINT_COUNT or _right_joints.size() != JOINT_COUNT:
		push_warning("Ai3ptWingAnimation1 needs three joints on each wing before it can flap.")
		return

	var airspeed_ratio := clampf(
			request.airflow_speed / maxf(airspeed_for_fast_beat, 0.01),
			0.0,
			1.0
	)
	airspeed_ratio = smoothstep(0.0, 1.0, airspeed_ratio)
	var amplitude := deg_to_rad(lerpf(
			slow_beat_angle_degrees,
			fast_beat_angle_degrees,
			airspeed_ratio
	))

	# Resolve the requested thrust in the wing rig's frame. The visible power
	# stroke moves opposite that thrust: down for upward thrust, rearward for
	# forward thrust, and a blend for diagonal requests.
	var local_thrust := _local_thrust_direction(request.thrust_direction)
	var power_motion := -local_thrust
	var vertical_motion := power_motion.y
	var chord_motion := power_motion.z * chord_stroke_amplitude_multiplier
	if power_motion.z > 0.0:
		vertical_motion -= power_motion.z * forward_downstroke_ratio

	var ready_vertical := _ready_vertical_pose(amplitude, vertical_motion)
	var ready_sweep := _ready_sweep_pose(amplitude, chord_motion)
	var power_vertical := _power_vertical_pose(amplitude, vertical_motion)
	var power_sweep := _power_sweep_pose(amplitude, chord_motion)
	var low_airflow_emphasis := 1.0 - airspeed_ratio
	var shoulder_fold_progress := lerpf(0.45, 0.20, low_airflow_emphasis)
	var shoulder_lift_multiplier := lerpf(1.0, 1.18, low_airflow_emphasis)
	var elbow_fold_multiplier := lerpf(1.15, 1.60, low_airflow_emphasis)
	var hand_fold_multiplier := lerpf(1.25, 1.80, low_airflow_emphasis)
	var fold_vertical := PackedFloat32Array([
		lerpf(power_vertical[0], ready_vertical[0], shoulder_fold_progress),
		ready_vertical[1] * elbow_fold_multiplier,
		ready_vertical[2] * hand_fold_multiplier,
	])
	var fold_sweep := PackedFloat32Array([
		lerpf(power_sweep[0], ready_sweep[0], shoulder_fold_progress),
		ready_sweep[1] * elbow_fold_multiplier,
		ready_sweep[2] * hand_fold_multiplier,
	])
	var lift_vertical := PackedFloat32Array([
		ready_vertical[0] * shoulder_lift_multiplier,
		fold_vertical[1],
		fold_vertical[2],
	])
	var lift_sweep := PackedFloat32Array([
		ready_sweep[0] * shoulder_lift_multiplier,
		fold_sweep[1],
		fold_sweep[2],
	])

	if _flap_tween:
		_flap_tween.kill()
	_flap_tween = create_tween()

	# Force is active for exactly this first phase.
	_queue_pose(
			power_vertical,
			power_sweep,
			request.power_stroke_duration,
			Tween.TRANS_QUAD,
			Tween.EASE_IN
	)

	# Recovery is force-free. First collapse the elbow and wrist while the
	# shoulder has barely started upward, then lift that narrow folded wing and
	# open only enough to reach the next power-stroke-ready pose.
	var fold_duration := request.recovery_duration * recovery_fold_fraction
	var settle_duration := request.recovery_duration * recovery_settle_fraction
	var lift_duration := request.recovery_duration - fold_duration - settle_duration
	_queue_pose(
			fold_vertical,
			fold_sweep,
			fold_duration,
			Tween.TRANS_QUAD,
			Tween.EASE_OUT
	)
	_queue_pose(
			lift_vertical,
			lift_sweep,
			lift_duration,
			Tween.TRANS_SINE,
			Tween.EASE_IN_OUT
	)
	_queue_pose(
			ready_vertical,
			ready_sweep,
			settle_duration,
			Tween.TRANS_SINE,
			Tween.EASE_OUT
	)

	# Stay cocked through the remaining cadence window. A new beat kills this
	# tween from the prepared pose; if none arrives, ease back into the flat
	# aerodynamic pose used while gliding.
	if request.prepared_hold_duration > 0.0:
		_flap_tween.tween_interval(request.prepared_hold_duration)
	_queue_pose(
			_zero_pose(),
			_zero_pose(),
			request.recovery_duration,
			Tween.TRANS_SINE,
			Tween.EASE_IN_OUT
	)


func _local_thrust_direction(world_thrust_direction: Vector3) -> Vector3:
	if world_thrust_direction.length_squared() < 0.0001:
		return Vector3.UP
	var wing_root := get_parent() as Node3D
	if not wing_root:
		return world_thrust_direction.normalized()
	return (
			wing_root.global_basis.inverse() * world_thrust_direction
	).normalized()


func _ready_vertical_pose(amplitude: float, power_motion: float) -> PackedFloat32Array:
	# The elbow closes sharply and the wrist counter-rotates. Opposing those
	# hinges gives the recovery a visible tucked corner instead of a U-shaped
	# chain of three turns in the same direction.
	return PackedFloat32Array([
		-amplitude * power_motion * 0.58,
		-amplitude * power_motion * 0.95,
		amplitude * power_motion * 0.75,
	])


func _ready_sweep_pose(amplitude: float, power_motion: float) -> PackedFloat32Array:
	return PackedFloat32Array([
		-amplitude * power_motion * 0.42,
		-amplitude * power_motion * 1.05,
		amplitude * power_motion * 0.82,
	])


func _power_vertical_pose(amplitude: float, power_motion: float) -> PackedFloat32Array:
	return PackedFloat32Array([
		amplitude * power_motion * 0.62,
		-amplitude * power_motion * 0.04,
		-amplitude * power_motion * 0.02,
	])


func _power_sweep_pose(amplitude: float, power_motion: float) -> PackedFloat32Array:
	return PackedFloat32Array([
		amplitude * power_motion * 0.55,
		amplitude * power_motion * 0.30,
		amplitude * power_motion * 0.15,
	])


func _zero_pose() -> PackedFloat32Array:
	return PackedFloat32Array([0.0, 0.0, 0.0])


func _set_pose(
		vertical_angles: PackedFloat32Array,
		rear_sweep_angles: PackedFloat32Array
) -> void:
	for side_index in 2:
		var side := -1.0 if side_index == 0 else 1.0
		var joints := _left_joints if side_index == 0 else _right_joints
		for joint_index in JOINT_COUNT:
			joints[joint_index].rotation.z = side * vertical_angles[joint_index]
			joints[joint_index].rotation.y = -side * rear_sweep_angles[joint_index]


func _queue_pose(
		vertical_angles: PackedFloat32Array,
		rear_sweep_angles: PackedFloat32Array,
		duration: float,
		transition: Tween.TransitionType,
		ease: Tween.EaseType
) -> void:
	var is_first_property := true
	for side_index in 2:
		var side := -1.0 if side_index == 0 else 1.0
		var joints := _left_joints if side_index == 0 else _right_joints
		for joint_index in JOINT_COUNT:
			var targets := {
				"rotation:z": side * vertical_angles[joint_index],
				"rotation:y": -side * rear_sweep_angles[joint_index],
			}
			for property: String in targets:
				var tweener: PropertyTweener
				if is_first_property:
					tweener = _flap_tween.tween_property(
							joints[joint_index], property, targets[property], duration
					)
					is_first_property = false
				else:
					tweener = _flap_tween.parallel().tween_property(
							joints[joint_index], property, targets[property], duration
					)
				tweener.set_trans(transition).set_ease(ease)


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
