class_name OpenLookFlightCameraBehavior
extends FlightCameraBehavior

const MOUSE_SENSITIVITY := 0.005
const MAX_PITCH := deg_to_rad(80.0)


func handle_mouse_motion(relative: Vector2, _viewport_size: Vector2) -> void:
	camera_pivot.rotate_y(-relative.x * MOUSE_SENSITIVITY)
	camera_pitch.rotate_x(-relative.y * MOUSE_SENSITIVITY)
	camera_pitch.rotation.x = clampf(camera_pitch.rotation.x, -MAX_PITCH, MAX_PITCH)
