class_name FlightCameraBehavior
extends RefCounted

var camera_pivot: Node3D
var camera_pitch: Node3D


func setup(new_camera_pivot: Node3D, new_camera_pitch: Node3D) -> void:
	camera_pivot = new_camera_pivot
	camera_pitch = new_camera_pitch


func activate(body_direction: Vector3) -> void:
	update_body_direction(body_direction)


func get_reference_direction(player: Player) -> Vector3:
	return player.visible_flight_direction()


func process_camera(body_direction: Vector3, _delta: float) -> void:
	update_body_direction(body_direction)


func handle_mouse_motion(_relative: Vector2, _viewport_size: Vector2) -> void:
	pass


func update_body_direction(_body_direction: Vector3) -> void:
	pass


func get_steering_direction() -> Vector3:
	if camera_pitch:
		return -camera_pitch.global_basis.z.normalized()
	return Vector3.FORWARD


func get_control_cursor_offset() -> Vector2:
	return Vector2.ZERO


func _basis_from_forward(direction: Vector3) -> Basis:
	var forward := direction.normalized()
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	var reference_up := Vector3.UP
	if absf(forward.dot(reference_up)) > 0.98:
		reference_up = Vector3.FORWARD
	var right := forward.cross(reference_up).normalized()
	var up := right.cross(forward).normalized()
	return Basis(right, up, -forward)
