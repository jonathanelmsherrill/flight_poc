class_name AiOpus3ptWingAnimation1
extends WingAnimation

## Three-joint wing (shoulder, elbow, wrist) proportioned like a bird's: a short
## upper arm under the tertials, a longer forearm carrying the broad
## secondaries, and a hand whose primaries make up nearly half the span.
##
## Beats play keyframed poses along a cubic spline, timed so the downstroke
## spans exactly the physical power stroke. The stroke runs in a frame turned
## about the span toward the requested thrust, so the wings always sweep away
## from it: overhead-to-low for takeoff, down-and-back when pushing forward,
## down-and-forward when braking. Between beats the wings ease back into the
## aerodynamic frame Wings supplies, so the glide keeps showing the real AoA.
const JOINT_COUNT := 3
const JOINT_NAMES := [&"ShoulderJoint", &"ElbowJoint", &"WristJoint"]
const ROOT_OFFSET := 0.2
## Upper arm, forearm, and hand bone. The hand bone is short; its primaries
## carry the outer panel well past it.
const BONE_LENGTHS := [0.58, 0.82, 0.34]
const BONE_THICKNESS := 0.04
## Convex panel outlines in each joint's frame for a right wing: x runs out
## along the span, y runs back along the chord. Bones lie on y = 0, just behind
## the leading edge. Neighbouring panels overlap a little so bends stay closed.
const PANEL_OUTLINES := [
	# Upper arm: short and deep, with the tertials filling in against the back.
	[Vector2(0.0, -0.09), Vector2(0.58, -0.11), Vector2(0.61, 1.0), Vector2(0.0, 1.1)],
	# Forearm: the secondaries make a long, nearly straight trailing edge.
	[Vector2(-0.03, -0.11), Vector2(0.82, -0.18), Vector2(0.85, 0.86), Vector2(-0.03, 1.0)],
	# Hand: the long primaries taper to a swept-back tip.
	[Vector2(-0.03, -0.18), Vector2(1.36, 0.3), Vector2(0.78, 0.82), Vector2(-0.03, 0.86)],
]
const PANEL_COLORS := [
	Color(0.55, 0.85, 1.0, 0.85),
	Color(0.38, 0.72, 1.0, 0.85),
	Color(0.22, 0.55, 0.95, 0.85),
]
const BONE_COLOR := Color(0.1, 0.2, 0.4)

## Key poses in degrees per joint (shoulder, elbow, wrist): x = elevation (tip
## up), y = rear sweep (tip back), z = twist (leading edge up). Elbow and wrist
## are relative to the bone before them. _SLOW is the deep takeoff stroke,
## _FAST the shallow cruise stroke; each beat blends them by airspeed.
## Ready: extended high over the back, hand flicked open.
const TOP_SLOW := [Vector3(76, 12, 0), Vector3(4, -4, 0), Vector3(-8, 8, 6)]
const TOP_FAST := [Vector3(38, 6, 0), Vector3(2, -4, 0), Vector3(-4, 8, 4)]
## Mid-downstroke: fully spread; air load bends the tip up and pronates the hand.
const MID_DOWN_SLOW := [Vector3(8, 0, 0), Vector3(6, -4, 0), Vector3(16, 2, -8)]
const MID_DOWN_FAST := [Vector3(2, 0, 0), Vector3(4, -4, 0), Vector3(10, 4, -10)]
## Bottom: swept down and forward, the hand whipping past the arm.
const BOTTOM_SLOW := [Vector3(-52, -20, 0), Vector3(-6, -6, 0), Vector3(-12, -4, -4)]
const BOTTOM_FAST := [Vector3(-28, -8, 0), Vector3(-4, -4, 0), Vector3(-8, 2, -6)]
## Early recovery: elbow and wrist flex so the wrist leads upward while the hand
## trails low, swept back and feathered to slip through the air.
const FOLD_SLOW := [Vector3(-40, 8, 0), Vector3(26, -36, 0), Vector3(-55, 58, 20)]
const FOLD_FAST := [Vector3(-18, 12, 0), Vector3(16, -28, 0), Vector3(-32, 50, 14)]
## Late recovery: wrist high, hand still trailing before it flicks open.
const RISE_SLOW := [Vector3(44, 16, 0), Vector3(22, -26, 0), Vector3(-90, 44, 16)]
const RISE_FAST := [Vector3(22, 12, 0), Vector3(10, -20, 0), Vector3(-50, 36, 10)]
## Resting glide: slight dihedral with the hand swept a little behind the wrist.
const GLIDE := [Vector3(4, 2, 0), Vector3(1, -4, 0), Vector3(-2, 6, 0)]
## Diving: the elbow pulls in and the hand sweeps far back.
const HIGH_SPEED_TUCK := [Vector3(-3, 22, 0), Vector3(0, -32, 0), Vector3(-4, 52, 0)]
## Braking: wings reach forward and cup into the oncoming air.
const FLARE := [Vector3(-8, -12, 0), Vector3(-4, 0, 0), Vector3(-14, -6, 4)]
## Standing: a Z-fold flat along the back, in a frame where sweep points toward
## the feet. Upper arm down, forearm back up, hand down again, with the
## feathers tipped off the back.
const FOLDED := [Vector3(0, 80, -20), Vector3(0, -160, 0), Vector3(0, 165, 0)]
## How far the folded wings sit out from the shoulder mount, clear of the body.
const FOLD_BACK_OFFSET := 0.25
## Rigid panels can't swing their feathers in line with the bones, so folded
## panels narrow instead, reading as feathers stacked along the back.
const FOLDED_CHORD_SCALE := 0.25
const FOLD_RESPONSE := 5.0
const UNFOLD_RESPONSE := 14.0

const DOWNSTROKE_MID_FRACTION := 0.45
const RECOVERY_FOLD_FRACTION := 0.3
const RECOVERY_RISE_FRACTION := 0.72
## Smallest windup worth its own keyframe, as a fraction of the power stroke.
const MIN_WINDUP_FRACTION := 0.02
const THRUST_DIRECTION_RESPONSE := 12.0
const FLIGHT_READING_RESPONSE := 8.0
const MIN_DIRECTION_LENGTH_SQUARED := 0.0001

@export_group("Airspeed Response")
## Airspeed at which beats use the full cruise stroke instead of the takeoff
## stroke. Also where the glide begins tucking.
@export_range(0.01, 100.0, 0.1) var airspeed_for_fast_beat := 22.0
## Below this airspeed the aerodynamic wing frame says little, so the stroke is
## referenced to world up instead and a hover or takeoff beats level.
@export_range(0.1, 20.0, 0.1) var takeoff_airspeed := 6.0
@export_range(1.0, 100.0, 0.1) var full_tuck_airspeed := 40.0
@export_range(0.0, 90.0) var flare_start_aoa_degrees := 20.0
@export_range(0.0, 90.0) var full_flare_aoa_degrees := 60.0

@export_group("Stroke Shape")
## How far the stroke plane leans from wing-up toward the requested thrust.
## 0 always flaps straight down through the wing; 1 paddles directly away from
## the thrust.
@export_range(0.0, 1.0) var takeoff_thrust_tilt := 0.45
@export_range(0.0, 1.0) var cruise_thrust_tilt := 0.3
## Largest share of the power stroke spent raising wings that start low, such
## as the first beat out of a glide. Force is already applying meanwhile.
@export_range(0.0, 0.6) var max_windup_fraction := 0.35
## How far the raised wings sag toward the glide while held for the next
## regular beat.
@export_range(0.0, 1.0) var hold_sag := 0.3
@export_range(0.05, 2.0) var glide_relax_duration := 0.35

var _body_visual: Node3D
var _stroke_frame: Node3D
var _left_joints: Array[Node3D] = []
var _right_joints: Array[Node3D] = []
var _panels: Array[MeshInstance3D] = []
var _glide_pose := WingPose.from_degrees(0.0, GLIDE)
var _tuck_pose := WingPose.from_degrees(0.0, HIGH_SPEED_TUCK)
var _flare_pose := WingPose.from_degrees(0.0, FLARE)
var _folded_pose := WingPose.from_degrees(0.0, FOLDED)
var _current_pose := _glide_pose
var _flight_velocity := Vector3.ZERO
var _is_airborne := true
## Overlay on top of the beat/glide pose: 1 is folded flat against the back.
var _fold_weight := 0.0
var _smoothed_airspeed := 0.0
var _smoothed_aoa := 0.0
var _beat_thrust_direction := Vector3.UP
var _target_beat_thrust_direction := Vector3.UP
var _beat_airspeed_ratio := 0.0
## Keyframes of the beat in progress. A null pose stands for the live glide.
var _track_times := PackedFloat32Array()
var _track_poses: Array[WingPose] = []
var _track_time := 0.0


func _process(delta: float) -> void:
	if _left_joints.size() != JOINT_COUNT or _right_joints.size() != JOINT_COUNT:
		return
	_update_flight_readings(delta)
	_beat_thrust_direction = _beat_thrust_direction.slerp(
			_target_beat_thrust_direction,
			1.0 - exp(-THRUST_DIRECTION_RESPONSE * delta)
	).normalized()

	var glide := _live_glide_pose()
	if _track_times.is_empty():
		_current_pose = glide
	else:
		_track_time += delta
		_current_pose = _sample_track(_track_time, glide)
		if _track_time >= _track_times[_track_times.size() - 1]:
			_track_times.clear()
			_track_poses.clear()

	# Fold slowly after landing; snap open quickly for a takeoff.
	var fold_target := 0.0 if _is_airborne else 1.0
	var fold_response := FOLD_RESPONSE if fold_target > _fold_weight else UNFOLD_RESPONSE
	_fold_weight = lerpf(_fold_weight, fold_target, 1.0 - exp(-fold_response * delta))
	for panel in _panels:
		panel.scale.z = lerpf(1.0, FOLDED_CHORD_SCALE, _fold_weight)
	_update_stroke_frame(_current_pose.stroke_weight)
	_apply_pose(_current_pose.lerp_to(_folded_pose, _fold_weight))


func configure(body_visual: Node3D, fast_power_stroke_airspeed: float) -> void:
	_body_visual = body_visual
	airspeed_for_fast_beat = fast_power_stroke_airspeed
	_stroke_frame = Node3D.new()
	_stroke_frame.name = "StrokeFrame"
	add_child(_stroke_frame)
	_left_joints = _make_wing("LeftWing", -1.0)
	_right_joints = _make_wing("RightWing", 1.0)
	_apply_pose(_current_pose)


func update_flight_state(flight_velocity: Vector3, is_airborne: bool) -> void:
	_flight_velocity = flight_velocity
	_is_airborne = is_airborne


func play_beat(request: WingBeatAnimationRequest) -> void:
	if _left_joints.size() != JOINT_COUNT or _right_joints.size() != JOINT_COUNT:
		push_warning("AiOpus3ptWingAnimation1 needs three joints on each wing before it can flap.")
		return

	_beat_airspeed_ratio = smoothstep(0.0, 1.0, clampf(
			request.airflow_speed / maxf(airspeed_for_fast_beat, 0.01),
			0.0,
			1.0
	))
	# A beat out of the glide takes its direction outright. One that interrupts
	# a held stroke turns toward it so the stroke plane doesn't snap.
	_target_beat_thrust_direction = request.thrust_direction
	if (
			_current_pose.stroke_weight < 0.05
			or _beat_thrust_direction.dot(request.thrust_direction) < -0.9
	):
		_beat_thrust_direction = request.thrust_direction

	var top := _stroke_pose(TOP_SLOW, TOP_FAST)
	var bottom := _stroke_pose(BOTTOM_SLOW, BOTTOM_FAST)
	# Force starts immediately, so wings that begin low spend the first part of
	# the power stroke getting up before they sweep down.
	var shoulder_stroke_range := maxf(top.joints[0].x - bottom.joints[0].x, 0.01)
	var windup_fraction := max_windup_fraction * clampf(
			(top.joints[0].x - _current_pose.joints[0].x) / shoulder_stroke_range,
			0.0,
			1.0
	)
	if windup_fraction < MIN_WINDUP_FRACTION:
		windup_fraction = 0.0
	var windup_end := request.power_stroke_duration * windup_fraction
	var power_end := request.power_stroke_duration
	var recovery_end := power_end + request.recovery_duration
	var hold_end := recovery_end + request.prepared_hold_duration

	_track_times.clear()
	_track_poses.clear()
	_track_time = 0.0
	_add_key(0.0, _current_pose)
	if windup_end > 0.0:
		_add_key(windup_end, top)
	_add_key(
			lerpf(windup_end, power_end, DOWNSTROKE_MID_FRACTION),
			_stroke_pose(MID_DOWN_SLOW, MID_DOWN_FAST)
	)
	_add_key(power_end, bottom)

	# Recovery is force-free: fold, lift the folded wing, then open it at the top.
	_add_key(
			power_end + request.recovery_duration * RECOVERY_FOLD_FRACTION,
			_stroke_pose(FOLD_SLOW, FOLD_FAST)
	)
	_add_key(
			power_end + request.recovery_duration * RECOVERY_RISE_FRACTION,
			_stroke_pose(RISE_SLOW, RISE_FAST)
	)
	_add_key(recovery_end, top)

	# Stay cocked through the rest of the cadence window, sagging a little so a
	# long hold doesn't freeze. A new beat takes over from wherever this is; if
	# none comes, settle into the glide.
	if request.prepared_hold_duration > 0.0:
		var cocked := top.lerp_to(_glide_pose, hold_sag)
		cocked.stroke_weight = 1.0
		_add_key(hold_end, cocked)
	_add_key(hold_end + glide_relax_duration, null)


func _add_key(time: float, pose: WingPose) -> void:
	_track_times.append(time)
	_track_poses.append(pose)


func _stroke_pose(slow_degrees: Array, fast_degrees: Array) -> WingPose:
	return WingPose.from_degrees(1.0, slow_degrees).lerp_to(
			WingPose.from_degrees(1.0, fast_degrees),
			_beat_airspeed_ratio
	)


func _sample_track(time: float, glide: WingPose) -> WingPose:
	var last_index := _track_times.size() - 1
	if time >= _track_times[last_index]:
		return glide
	var index := 0
	while time >= _track_times[index + 1]:
		index += 1

	var duration := _track_times[index + 1] - _track_times[index]
	if duration <= 0.0:
		return _track_pose(index + 1, glide)
	return WingPose.hermite(
			_track_pose(index, glide),
			_track_pose(index + 1, glide),
			_track_velocity(index, glide),
			_track_velocity(index + 1, glide),
			(time - _track_times[index]) / duration,
			duration
	)


func _track_pose(index: int, glide: WingPose) -> WingPose:
	var pose := _track_poses[index]
	return pose if pose else glide


## Secant velocity across a key's neighbours. Unlike a Catmull-Rom tangent, it
## stays tame when a short segment meets a long one, such as the snap to the
## top followed by a long hold. The track starts and ends at rest.
func _track_velocity(index: int, glide: WingPose) -> WingPose:
	if index == 0 or index == _track_times.size() - 1:
		return WingPose.new()
	return WingPose.velocity(
			_track_pose(index - 1, glide),
			_track_pose(index + 1, glide),
			_track_times[index + 1] - _track_times[index - 1]
	)


func _update_flight_readings(delta: float) -> void:
	var response := 1.0 - exp(-FLIGHT_READING_RESPONSE * delta)
	_smoothed_airspeed = lerpf(_smoothed_airspeed, _flight_velocity.length(), response)
	var aoa := 0.0
	var wing_root := get_parent() as Node3D
	if wing_root and _flight_velocity.length_squared() >= MIN_DIRECTION_LENGTH_SQUARED:
		# Matches FlightPhysics: positive when moving into the wing's underside.
		var along_normal := wing_root.global_basis.y.normalized().dot(
				_flight_velocity.normalized()
		)
		aoa = -asin(clampf(along_normal, -1.0, 1.0))
	_smoothed_aoa = lerpf(_smoothed_aoa, aoa, response)


func _live_glide_pose() -> WingPose:
	var tuck := smoothstep(airspeed_for_fast_beat, full_tuck_airspeed, _smoothed_airspeed)
	var flare := smoothstep(
			deg_to_rad(flare_start_aoa_degrees),
			deg_to_rad(full_flare_aoa_degrees),
			_smoothed_aoa
	)
	return _glide_pose.lerp_to(_tuck_pose, tuck).lerp_to(_flare_pose, flare)


## Turns the stroke frame about the span so its up axis points where the pose
## wants it: the aerodynamic wing normal in flight, world up near a hover, and
## partway toward the beat's thrust while flapping.
func _update_stroke_frame(stroke_weight: float) -> void:
	var wing_root := get_parent() as Node3D
	if not wing_root:
		return
	var span := wing_root.global_basis.x.normalized()
	var wing_up := wing_root.global_basis.y.normalized()

	var rest_up := wing_up
	var level_up := _perpendicular_direction(Vector3.UP, span)
	if level_up != Vector3.ZERO:
		var level_weight := 1.0 - smoothstep(0.0, takeoff_airspeed, _smoothed_airspeed)
		rest_up = wing_up.rotated(span, wing_up.signed_angle_to(level_up, span) * level_weight)

	var stroke_up := rest_up
	var thrust := _perpendicular_direction(_beat_thrust_direction, span)
	if thrust != Vector3.ZERO:
		var thrust_tilt := lerpf(takeoff_thrust_tilt, cruise_thrust_tilt, _beat_airspeed_ratio)
		stroke_up = rest_up.rotated(
				span,
				rest_up.signed_angle_to(thrust, span) * thrust_tilt * stroke_weight
		)
	var stroke_basis := Basis(Vector3.RIGHT, wing_up.signed_angle_to(stroke_up, span))
	_stroke_frame.basis = stroke_basis
	_stroke_frame.position = Vector3.ZERO
	if _fold_weight <= 0.001 or not is_instance_valid(_body_visual):
		return

	# Folding happens against the body, not the airflow: span to the body's
	# right, wing-up out of the back, and chord-back toward the feet, so a
	# rear sweep lays a bone down the back.
	var body_basis := _body_visual.global_basis.orthonormalized()
	var fold_right := body_basis.x
	if fold_right.dot(span) < 0.0:
		fold_right = -fold_right
	var fold_world := Basis(fold_right, body_basis.z, fold_right.cross(body_basis.z))
	var to_local := wing_root.global_basis.orthonormalized().inverse()
	_stroke_frame.basis = stroke_basis.slerp((to_local * fold_world).orthonormalized(), _fold_weight)
	_stroke_frame.position = to_local * body_basis.z * FOLD_BACK_OFFSET * _fold_weight


func _perpendicular_direction(direction: Vector3, axis: Vector3) -> Vector3:
	var perpendicular := direction - axis * direction.dot(axis)
	if perpendicular.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		return Vector3.ZERO
	return perpendicular.normalized()


func _apply_pose(pose: WingPose) -> void:
	for side_index in 2:
		var side := -1.0 if side_index == 0 else 1.0
		var joints := _left_joints if side_index == 0 else _right_joints
		for joint_index in JOINT_COUNT:
			var angles := pose.joints[joint_index]
			# Twist about the bone, sweep within the wing plane, then raise about
			# the parent's chord axis.
			joints[joint_index].basis = (
					Basis(Vector3.BACK, side * angles.x)
					* Basis(Vector3.UP, -side * angles.y)
					* Basis(Vector3.RIGHT, angles.z)
			)


func _make_wing(wing_name: String, side: float) -> Array[Node3D]:
	var wing_root := Node3D.new()
	wing_root.name = wing_name
	_stroke_frame.add_child(wing_root)

	var joints: Array[Node3D] = []
	var parent := wing_root
	for joint_index in JOINT_COUNT:
		var joint := Node3D.new()
		joint.name = JOINT_NAMES[joint_index]
		joint.position = Vector3(
				side * (ROOT_OFFSET if joint_index == 0 else BONE_LENGTHS[joint_index - 1]),
				0.0,
				0.0
		)
		parent.add_child(joint)
		var panel := _make_panel(side, joint_index)
		_panels.append(panel)
		joint.add_child(panel)
		joint.add_child(_make_bone(side, joint_index))
		joints.append(joint)
		parent = joint
	return joints


func _make_panel(side: float, joint_index: int) -> MeshInstance3D:
	var outline: Array = PANEL_OUTLINES[joint_index]
	var vertices := PackedVector3Array()
	# Fan-triangulate the convex outline from its first corner.
	for corner_index in range(1, outline.size() - 1):
		for point: Vector2 in [outline[0], outline[corner_index], outline[corner_index + 1]]:
			vertices.append(Vector3(side * point.x, 0.0, point.y))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	panel.mesh = mesh
	panel.material_override = _make_material(PANEL_COLORS[joint_index])
	return panel


func _make_bone(side: float, joint_index: int) -> MeshInstance3D:
	var length: float = BONE_LENGTHS[joint_index]
	var box := BoxMesh.new()
	box.size = Vector3(length, BONE_THICKNESS, BONE_THICKNESS)
	var bone := MeshInstance3D.new()
	bone.name = "Bone"
	bone.mesh = box
	bone.position = Vector3(side * length * 0.5, 0.0, 0.0)
	bone.material_override = _make_material(BONE_COLOR)
	return bone


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## One frame of wing shape: joint angles plus how far the wing has turned from
## its resting frame into the current beat's stroke frame.
class WingPose:
	## 0 rests in the aerodynamic (or level) frame; 1 is fully in the stroke frame.
	var stroke_weight := 0.0
	## Per joint (shoulder, elbow, wrist) in radians: x = elevation, y = rear
	## sweep, z = twist.
	var joints: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]

	static func from_degrees(new_stroke_weight: float, joint_degrees: Array) -> WingPose:
		var pose := WingPose.new()
		pose.stroke_weight = new_stroke_weight
		for joint_index in joint_degrees.size():
			pose.joints[joint_index] = (joint_degrees[joint_index] as Vector3) * (PI / 180.0)
		return pose

	## Per-second rate of change from one pose to another.
	static func velocity(from: WingPose, to: WingPose, duration: float) -> WingPose:
		var pose := WingPose.new()
		pose.stroke_weight = (to.stroke_weight - from.stroke_weight) / duration
		for joint_index in pose.joints.size():
			pose.joints[joint_index] = (
					to.joints[joint_index] - from.joints[joint_index]
			) / duration
		return pose

	## Cubic Hermite between two poses leaving and arriving at the given velocities.
	static func hermite(
			from: WingPose,
			to: WingPose,
			from_velocity: WingPose,
			to_velocity: WingPose,
			weight: float,
			duration: float
	) -> WingPose:
		var weight_squared := weight * weight
		var weight_cubed := weight_squared * weight
		var from_factor := 2.0 * weight_cubed - 3.0 * weight_squared + 1.0
		var to_factor := 1.0 - from_factor
		var from_velocity_factor := (weight_cubed - 2.0 * weight_squared + weight) * duration
		var to_velocity_factor := (weight_cubed - weight_squared) * duration
		var pose := WingPose.new()
		pose.stroke_weight = clampf(
				from.stroke_weight * from_factor
				+ to.stroke_weight * to_factor
				+ from_velocity.stroke_weight * from_velocity_factor
				+ to_velocity.stroke_weight * to_velocity_factor,
				0.0,
				1.0
		)
		for joint_index in pose.joints.size():
			pose.joints[joint_index] = (
					from.joints[joint_index] * from_factor
					+ to.joints[joint_index] * to_factor
					+ from_velocity.joints[joint_index] * from_velocity_factor
					+ to_velocity.joints[joint_index] * to_velocity_factor
			)
		return pose

	func lerp_to(other: WingPose, weight: float) -> WingPose:
		var pose := WingPose.new()
		pose.stroke_weight = lerpf(stroke_weight, other.stroke_weight, weight)
		for joint_index in joints.size():
			pose.joints[joint_index] = joints[joint_index].lerp(other.joints[joint_index], weight)
		return pose
