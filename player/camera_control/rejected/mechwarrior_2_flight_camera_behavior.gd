class_name Mechwarrior2FlightCameraBehavior
extends MechwarriorFlightCameraBehavior

var anchored_steering_direction := Vector3.FORWARD


func activate(body_direction: Vector3) -> void:
	super.activate(body_direction)
	anchored_steering_direction = body_direction.normalized()
	control_cursor_offset = Vector2.ZERO


func handle_mouse_motion(relative: Vector2, viewport_size: Vector2) -> void:
	super.handle_mouse_motion(relative, viewport_size)
	anchored_steering_direction = _direction_from_cursor(control_cursor_offset)


func update_body_direction(body_direction: Vector3) -> void:
	super.update_body_direction(body_direction)
	control_cursor_offset = _cursor_from_direction(anchored_steering_direction)
	if control_cursor_offset.length_squared() > 1.0:
		control_cursor_offset = control_cursor_offset.normalized()
		anchored_steering_direction = _direction_from_cursor(control_cursor_offset)


func get_steering_direction() -> Vector3:
	return anchored_steering_direction
