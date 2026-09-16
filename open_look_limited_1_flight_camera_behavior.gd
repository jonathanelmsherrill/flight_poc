class_name OpenLookLimited1FlightCameraBehavior
extends OpenLookFlightCameraBehavior

const MAX_SIDE_ANGLE := deg_to_rad(90.0)

var player_direction := Vector3.FORWARD
var last_horizontal_player_direction := Vector3.FORWARD


func activate(body_direction: Vector3) -> void:
	player_direction = body_direction
	_update_horizontal_player_direction()
	_normalize_camera_axes()
	_clamp_camera_yaw()


func handle_mouse_motion(relative: Vector2, viewport_size: Vector2) -> void:
	super.handle_mouse_motion(relative, viewport_size)
	_clamp_camera_yaw()


func update_body_direction(body_direction: Vector3) -> void:
	player_direction = body_direction
	_update_horizontal_player_direction()
	_clamp_camera_yaw()


func _update_horizontal_player_direction() -> void:
	var horizontal_direction := Vector3(player_direction.x, 0.0, player_direction.z)
	if horizontal_direction.length_squared() >= 0.0001:
		last_horizontal_player_direction = horizontal_direction.normalized()


func _normalize_camera_axes() -> void:
	var view_direction := -camera_pitch.global_basis.z.normalized()
	var horizontal_view := Vector3(view_direction.x, 0.0, view_direction.z)
	if horizontal_view.length_squared() < 0.0001:
		horizontal_view = last_horizontal_player_direction
	else:
		horizontal_view = horizontal_view.normalized()
	camera_pivot.global_basis = _basis_from_forward(horizontal_view)
	camera_pitch.rotation = Vector3(
			asin(clampf(view_direction.y, -1.0, 1.0)),
			0.0,
			0.0
	)


func _clamp_camera_yaw() -> void:
	var camera_forward := -camera_pivot.global_basis.z
	var horizontal_camera_forward := Vector3(camera_forward.x, 0.0, camera_forward.z)
	if horizontal_camera_forward.length_squared() < 0.0001:
		return
	horizontal_camera_forward = horizontal_camera_forward.normalized()
	var side_angle := last_horizontal_player_direction.signed_angle_to(
			horizontal_camera_forward,
			Vector3.UP
	)
	var clamped_side_angle := clampf(side_angle, -MAX_SIDE_ANGLE, MAX_SIDE_ANGLE)
	if is_equal_approx(side_angle, clamped_side_angle):
		return
	var clamped_forward := last_horizontal_player_direction.rotated(
			Vector3.UP,
			clamped_side_angle
	)
	camera_pivot.global_basis = _basis_from_forward(clamped_forward)
