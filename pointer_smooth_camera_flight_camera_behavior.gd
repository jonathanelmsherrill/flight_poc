class_name PointerSmoothCameraFlightCameraBehavior
extends OpenLookLimited1FlightCameraBehavior

const MAX_YAW_SPEED := deg_to_rad(120.0)
const MAX_PITCH_SPEED := deg_to_rad(90.0)

var pointer_offset := Vector2.ZERO


func activate(body_direction: Vector3) -> void:
	pointer_offset = Vector2.ZERO
	super.activate(body_direction)


func handle_mouse_motion(relative: Vector2, viewport_size: Vector2) -> void:
	var half_viewport := viewport_size * 0.5
	pointer_offset += Vector2(
			relative.x / maxf(half_viewport.x, 1.0),
			relative.y / maxf(half_viewport.y, 1.0)
	)
	pointer_offset = pointer_offset.limit_length(1.0)


func process_camera(body_direction: Vector3, delta: float) -> void:
	player_direction = body_direction
	_update_horizontal_player_direction()
	camera_pivot.rotate_y(-pointer_offset.x * MAX_YAW_SPEED * delta)
	camera_pitch.rotate_x(-pointer_offset.y * MAX_PITCH_SPEED * delta)
	camera_pitch.rotation.x = clampf(camera_pitch.rotation.x, -MAX_PITCH, MAX_PITCH)
	_clamp_camera_yaw()


func get_control_cursor_offset() -> Vector2:
	return pointer_offset
