class_name FlightIntent
extends RefCounted

## Player-facing flight request. This intentionally contains no aerodynamic
## details such as angle of attack or wing deployment.
var desired_direction := Vector3.FORWARD
var maneuver_aggression := 0.0
var wants_flap := false
var wants_upward_flap := false
var requests_extra_flap := false


func _init(
		new_desired_direction: Vector3 = Vector3.FORWARD,
		new_maneuver_aggression: float = 0.0
) -> void:
	desired_direction = new_desired_direction.normalized()
	maneuver_aggression = clampf(new_maneuver_aggression, 0.0, 1.0)
