class_name FlightInputController
extends RefCounted

## Translates device input and camera state into a semantic FlightIntent.
## Future flight/combat modes and modifiers belong here, not in Player or the
## aerodynamic controller.
var freelook_flight_direction := Vector3.FORWARD
var was_freelooking := false
var current_flight_intent := FlightIntent.new()
var steering_frame: Node3D #This is the camera direction that holds where we're pointing.

const GENTLE_TURN_ANGLE := deg_to_rad(10.0)
const FULL_AGGRESSION_TURN_ANGLE := deg_to_rad(60.0)

func get_flight_intent(current_velocity: Vector3) -> FlightIntent:
	var steering_direction := _get_steering_direction()
	var freelooking := Input.is_action_pressed("freelook")
	if freelooking and not was_freelooking:
		freelook_flight_direction = steering_direction
	elif not freelooking:
		freelook_flight_direction = steering_direction
	was_freelooking = freelooking

	var movement_strength := get_movement_input().length()
	var intent := current_flight_intent
	intent.desired_direction = (
			freelook_flight_direction if freelooking else steering_direction
		).normalized()
	intent.maneuver_aggression = _get_maneuver_aggression(
			intent.desired_direction,
			current_velocity
	)
	intent.force_wing_direction = Input.is_key_pressed(KEY_SHIFT)
	intent.wants_flap = movement_strength > 0.0 or Input.is_action_pressed("jump")
	intent.wants_upward_flap = Input.is_action_pressed("jump")
	intent.requests_extra_flap = Input.is_action_just_pressed("jump")
	return intent


func get_movement_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")


func _get_steering_direction() -> Vector3:
	if steering_frame:
		return -steering_frame.global_basis.z.normalized()
	return Vector3.FORWARD


func _get_maneuver_aggression(desired_direction: Vector3, current_velocity: Vector3) -> float:
	if current_velocity.length_squared() < 0.0001:
		return 0.0

	var turn_angle := acos(clampf(
			current_velocity.normalized().dot(desired_direction.normalized()),
			-1.0,
			1.0
	))
	var aggression := clampf(inverse_lerp(
			GENTLE_TURN_ANGLE,
			FULL_AGGRESSION_TURN_ANGLE,
			turn_angle
	), 0.0, 1.0)
	return aggression
