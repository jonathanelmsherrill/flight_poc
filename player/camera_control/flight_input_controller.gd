class_name FlightInputController
extends RefCounted

## Translates device input and camera state into a semantic FlightIntent.
## Concrete control schemes select their matching camera behavior.
var freelook_flight_direction := Vector3.FORWARD
var was_freelooking := false
var current_flight_intent := FlightIntent.new()
var camera_controller: PlayerCamera
var camera_behavior: FlightCameraBehavior

const GENTLE_TURN_ANGLE := deg_to_rad(10.0)
const FULL_AGGRESSION_TURN_ANGLE := deg_to_rad(60.0)

func activate(new_camera_controller: PlayerCamera) -> void:
	camera_controller = new_camera_controller
	if not camera_behavior:
		camera_behavior = create_camera_behavior()
	camera_controller.set_flight_camera_behavior(camera_behavior)
	freelook_flight_direction = _get_steering_direction()
	was_freelooking = Input.is_action_pressed("freelook")


func get_display_name() -> String:
	return "Flight Input"


func create_camera_behavior() -> FlightCameraBehavior:
	return FlightCameraBehavior.new()


func get_flight_intent(current_velocity: Vector3) -> FlightIntent:
	var steering_direction := _get_steering_direction()
	var freelooking := Input.is_action_pressed("freelook")
	if freelooking and not was_freelooking:
		freelook_flight_direction = steering_direction
	elif not freelooking:
		freelook_flight_direction = steering_direction
	was_freelooking = freelooking

	var movement_input := get_movement_input()
	var wants_backward := Input.is_action_pressed("move_backward")
	var wants_exertion := Input.is_action_pressed("exertion")
	var wants_directed_flap := (
			Input.is_action_pressed("move_forward")
			or Input.is_action_pressed("move_left")
			or Input.is_action_pressed("move_right")
	)
	var intent := current_flight_intent
	intent.desired_direction = (
			freelook_flight_direction if freelooking else steering_direction
	).normalized()
	intent.lift_up_direction = (
			camera_controller.get_control_up_direction()
			if camera_controller
			else Vector3.UP
	)
	intent.maneuver_aggression = _get_maneuver_aggression(
			intent.desired_direction,
			current_velocity
	)
	intent.turn_response_multiplier = get_turn_response_multiplier(
			steering_direction
	)
	intent.force_wing_direction = false
	# Backward brakes rather than flapping; exertion adds reverse strokes to it.
	intent.wants_airbrake = wants_backward
	intent.wants_exertion = wants_exertion
	intent.wants_flap = (
			wants_directed_flap
			or Input.is_action_pressed("jump")
			or (wants_exertion and wants_backward)
	)
	intent.wants_upward_flap = Input.is_action_pressed("jump")
	intent.wants_directed_flap = wants_directed_flap or (wants_exertion and wants_backward)
	intent.requests_extra_flap = Input.is_action_just_pressed("jump")
	intent.flap_direction = (
			_get_exertion_flap_direction(movement_input, intent, current_velocity)
			if wants_exertion
			else intent.desired_direction
	)
	return intent


func get_turn_response_multiplier(_steering_direction: Vector3) -> float:
	return 1.0


func get_movement_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")


## Exertion strokes push the way the movement keys point: forward along the
## steering direction, sideways relative to the camera, and backward straight
## against the airflow to reinforce the airbrake.
func _get_exertion_flap_direction(
		movement_input: Vector2,
		intent: FlightIntent,
		current_velocity: Vector3
) -> Vector3:
	var forward := intent.desired_direction
	var right := forward.cross(intent.lift_up_direction)
	if right.length_squared() >= 0.0001:
		right = right.normalized()
	var backward := -forward
	if current_velocity.length_squared() >= 0.0001:
		backward = -current_velocity.normalized()
	var longitudinal := forward if movement_input.y < 0.0 else backward
	return right * movement_input.x + longitudinal * absf(movement_input.y)


func _get_steering_direction() -> Vector3:
	if camera_controller:
		return camera_controller.get_steering_direction()
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
