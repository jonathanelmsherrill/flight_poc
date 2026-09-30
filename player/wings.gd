class_name Wings
extends Node3D

## Shared attachment and aerodynamic orientation for interchangeable visual
## wing implementations.
const MIN_DIRECTION_LENGTH_SQUARED := 0.0001

var span_direction := Vector3.RIGHT
var wing_animation: WingAnimation


## Replaces the active visual rig. Wings owns its lifetime and makes it a child
## so every implementation inherits this node's attachment transform.
func set_animation(new_animation: WingAnimation) -> void:
	if is_instance_valid(wing_animation):
		remove_child(wing_animation)
		wing_animation.queue_free()
	wing_animation = new_animation
	wing_animation.name = "WingAnimation"
	add_child(wing_animation)


## Places and orients the visual wing rig from the physical wing surface.
## This runs whether the flyer is gliding or flapping; animations only change
## their own local joints beneath this transform.
func update_aerodynamic_pose(
		flight_velocity: Vector3,
		wing_surface_normal: Vector3,
		shoulder_position: Vector3,
		body_right: Vector3,
		is_airborne: bool = true
) -> void:
	if wing_surface_normal.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		return

	var surface_normal := wing_surface_normal.normalized()
	# The span starts at the body's right each frame; airflow then sets its line
	# while the sign stays toward that right. Carrying the previous span instead
	# lets it drift to the left, e.g. turning in place or strafing then backing
	# up, which mirrors the rig.
	if body_right.length_squared() >= MIN_DIRECTION_LENGTH_SQUARED:
		span_direction = body_right.normalized()
	if flight_velocity.length_squared() >= MIN_DIRECTION_LENGTH_SQUARED:
		var flight_direction := flight_velocity.normalized()
		var requested_span_direction := flight_direction.cross(surface_normal)
		if requested_span_direction.length_squared() >= MIN_DIRECTION_LENGTH_SQUARED:
			requested_span_direction = requested_span_direction.normalized()
			if requested_span_direction.dot(span_direction) < 0.0:
				requested_span_direction = -requested_span_direction
			span_direction = requested_span_direction

	# At a 90 degree AoA, airflow and surface normal align and cannot define a
	# span direction. Keep the previous span, projected back into the wing plane.
	span_direction = span_direction - surface_normal * span_direction.dot(surface_normal)
	if span_direction.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		span_direction = _fallback_span_direction(surface_normal)
	else:
		span_direction = span_direction.normalized()

	var chord_back := span_direction.cross(surface_normal).normalized()
	global_position = shoulder_position
	global_basis = Basis(span_direction, surface_normal, chord_back)
	if is_instance_valid(wing_animation):
		wing_animation.update_flight_state(flight_velocity, is_airborne)


## Chooses a stable direction across the wing when airflow cannot determine
## one, such as when the wing is presented directly into the airflow.
func _fallback_span_direction(surface_normal: Vector3) -> Vector3:
	var reference := Vector3.RIGHT
	if absf(reference.dot(surface_normal)) > 0.9:
		reference = Vector3.FORWARD
	return (reference - surface_normal * reference.dot(surface_normal)).normalized()
