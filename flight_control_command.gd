class_name FlightControlCommand
extends RefCounted

## Controller-facing request for the flyer. Player owns the actual state and
## makes it chase these targets at the profile's control rate.
var target_body_direction := Vector3.FORWARD
var target_wing_lift_direction := Vector3.UP
var target_aoa := 0.0
var requested_aerodynamic_force := Vector3.ZERO
