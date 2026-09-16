class_name FlightControlCommand
extends RefCounted

## Controller-facing request for the flyer. Player owns the physical wing
## state and makes it chase the requested surface normal at the profile's
## control rate.
var target_body_direction := Vector3.FORWARD
var target_wing_surface_normal := Vector3.UP

## Controller estimates for diagnostics only. Physics derives its effective
## angle of attack from the actual surface normal and current airflow.
var info_intended_aoa := 0.0
var info_requested_aerodynamic_force := Vector3.ZERO
