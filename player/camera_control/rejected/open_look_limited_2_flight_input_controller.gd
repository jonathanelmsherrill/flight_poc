class_name OpenLookLimited2FlightInputController
extends FlightInputController

const WEAK_RESPONSE_END := deg_to_rad(10.0)
const NORMAL_RESPONSE_ANGLE := deg_to_rad(45.0)
const MAX_RESPONSE_ANGLE := deg_to_rad(90.0)
const WEAK_RESPONSE := 0.08
const STRONG_RESPONSE := 2.0


func get_display_name() -> String:
	return "Open Look Limited 2"


func create_camera_behavior() -> FlightCameraBehavior:
	return OpenLookLimited1FlightCameraBehavior.new()


func get_turn_response_multiplier(steering_direction: Vector3) -> float:
	var reference_direction := camera_controller.get_active_reference_direction()
	var displacement_angle := reference_direction.angle_to(steering_direction)
	if displacement_angle <= WEAK_RESPONSE_END:
		return WEAK_RESPONSE
	if displacement_angle <= NORMAL_RESPONSE_ANGLE:
		return lerpf(
				WEAK_RESPONSE,
				1.0,
				smoothstep(WEAK_RESPONSE_END, NORMAL_RESPONSE_ANGLE, displacement_angle)
		)
	return lerpf(
			1.0,
			STRONG_RESPONSE,
			smoothstep(NORMAL_RESPONSE_ANGLE, MAX_RESPONSE_ANGLE, displacement_angle)
	)
