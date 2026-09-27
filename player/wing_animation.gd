class_name WingAnimation
extends Node

## Owns the visual timing and articulation of Capsule Girl's wingbeats.
## Airspeed is the wind speed experienced by the wings, so low-speed,
## force-limited beats are broad and slow while high-speed beats are compact
## and fast.
enum BeatType {
	FORWARD,
	EXTRA_UP,
}

const JOINT_COUNT := 3

@export_group("Airspeed Response")
@export var airspeed_for_fast_beat := 22.0
@export_range(0.1, 1.0) var slow_beat_cycle_fraction := 0.72
@export_range(0.1, 1.0) var fast_beat_cycle_fraction := 0.28

@export_group("Wingbeat Shape")
@export_range(1.0, 90.0) var slow_beat_angle_degrees := 62.0
@export_range(1.0, 90.0) var fast_beat_angle_degrees := 28.0
@export_range(1.0, 2.0) var extra_up_amplitude_multiplier := 1.15
@export_range(0.5, 1.0) var extra_up_duration_multiplier := 0.9

var _left_joints: Array[Node3D] = []
var _right_joints: Array[Node3D] = []
var _flap_tween: Tween


func configure(left_joints: Array[Node3D], right_joints: Array[Node3D]) -> void:
	_left_joints = left_joints
	_right_joints = right_joints


func play_flap(beat_type: BeatType, airspeed: float, cycle_duration: float) -> void:
	if _left_joints.size() != JOINT_COUNT or _right_joints.size() != JOINT_COUNT:
		push_warning("WingAnimation needs three joints on each wing before it can flap.")
		return

	var airspeed_ratio := clampf(
			maxf(airspeed, 0.0) / maxf(airspeed_for_fast_beat, 0.01),
			0.0,
			1.0
	)
	# Ease the response so small airspeed changes around takeoff do not make the
	# cadence jump abruptly.
	airspeed_ratio = smoothstep(0.0, 1.0, airspeed_ratio)
	var amplitude := deg_to_rad(lerpf(
			slow_beat_angle_degrees,
			fast_beat_angle_degrees,
			airspeed_ratio
	))
	var duration := maxf(cycle_duration, 0.01) * lerpf(
			slow_beat_cycle_fraction,
			fast_beat_cycle_fraction,
			airspeed_ratio
	)
	if beat_type == BeatType.EXTRA_UP:
		amplitude *= extra_up_amplitude_multiplier
		duration *= extra_up_duration_multiplier

	if _flap_tween:
		_flap_tween.kill()
	_flap_tween = create_tween()

	# The outer two joints fold farther on recovery, then open during the
	# downstroke. This reads as one bird-like articulated wing rather than three
	# rigid panels rotating in unison.
	var raised_pose := PackedFloat32Array([
		amplitude * 0.48,
		amplitude * 0.34,
		amplitude * 0.24,
	])
	var dropped_pose := PackedFloat32Array([
		-amplitude * (0.48 if beat_type == BeatType.EXTRA_UP else 0.36),
		amplitude * 0.08,
		amplitude * 0.04,
	])
	_tween_pose(raised_pose, duration * 0.40, Tween.TRANS_SINE, Tween.EASE_OUT)
	_tween_pose(dropped_pose, duration * 0.42, Tween.TRANS_QUAD, Tween.EASE_IN)
	_tween_pose(PackedFloat32Array([0.0, 0.0, 0.0]), duration * 0.18,
			Tween.TRANS_SINE, Tween.EASE_OUT)


func _tween_pose(
		angles: PackedFloat32Array,
		duration: float,
		transition: Tween.TransitionType,
		ease: Tween.EaseType
) -> void:
	var first_tweener: PropertyTweener
	for joint_index in JOINT_COUNT:
		for side_index in 2:
			var side := -1.0 if side_index == 0 else 1.0
			var joints := _left_joints if side_index == 0 else _right_joints
			var tweener := _flap_tween.tween_property(
					joints[joint_index],
					"rotation:z",
					side * angles[joint_index],
					duration
			) if first_tweener == null else _flap_tween.parallel().tween_property(
					joints[joint_index],
					"rotation:z",
					side * angles[joint_index],
					duration
			)
			if first_tweener == null:
				first_tweener = tweener
			tweener.set_trans(transition).set_ease(ease)
