class_name MechwarriorFlightCameraBehavior
extends FlightCameraBehavior

const MAX_CONTROL_CONE := deg_to_rad(45.0)

var control_cursor_offset := Vector2.ZERO
var body_basis := Basis.IDENTITY


func activate(body_direction: Vector3) -> void:
	control_cursor_offset = Vector2.ZERO
	update_body_direction(body_direction)


func handle_mouse_motion(relative: Vector2, viewport_size: Vector2) -> void:
	var half_viewport := viewport_size * 0.5
	control_cursor_offset += Vector2(
			relative.x / maxf(half_viewport.x, 1.0),
			relative.y / maxf(half_viewport.y, 1.0)
	)
	control_cursor_offset = control_cursor_offset.limit_length(1.0)


func update_body_direction(body_direction: Vector3) -> void:
	body_basis = _basis_from_forward(body_direction)
	camera_pivot.global_basis = body_basis
	camera_pitch.rotation = Vector3.ZERO


func get_steering_direction() -> Vector3:
	return _direction_from_cursor(control_cursor_offset)


func get_control_cursor_offset() -> Vector2:
	return control_cursor_offset


func _direction_from_cursor(cursor_offset: Vector2) -> Vector3:
	var base_forward := -body_basis.z
	var cursor_distance := minf(cursor_offset.length(), 1.0)
	if cursor_distance < 0.0001:
		return base_forward
	var cursor_direction := cursor_offset / cursor_distance
	var tangent_direction := (
			body_basis.x * cursor_direction.x
			- body_basis.y * cursor_direction.y
	).normalized()
	var cone_angle := cursor_distance * MAX_CONTROL_CONE
	return base_forward * cos(cone_angle) + tangent_direction * sin(cone_angle)


func _cursor_from_direction(direction: Vector3) -> Vector2:
	var normalized_direction := direction.normalized()
	var base_forward := -body_basis.z
	var forward_amount := clampf(normalized_direction.dot(base_forward), -1.0, 1.0)
	var cone_angle := acos(forward_amount)
	var tangent := normalized_direction - base_forward * forward_amount
	if tangent.length_squared() < 0.0001:
		return Vector2.ZERO
	var tangent_direction := tangent.normalized()
	return Vector2(
			tangent_direction.dot(body_basis.x),
			-tangent_direction.dot(body_basis.y)
	) * cone_angle / MAX_CONTROL_CONE
