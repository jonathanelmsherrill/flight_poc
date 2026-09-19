class_name FlyerState
extends RefCounted

## Mutable runtime state shared by the flight controller and physics engine.
## Player refreshes the velocity-derived fields before each simulation step.
var velocity := Vector3.ZERO
var local_air_velocity := Vector3.ZERO
var air_relative_velocity := Vector3.ZERO
var airspeed := 0.0
var is_airborne := false

var body_direction := Vector3.FORWARD
## Authoritative physical orientation of the wing surface.
var wing_normal := Vector3.UP
var current_flap_direction := Vector3.ZERO
var active_flap_direction := Vector3.ZERO

## Diagnostics derived from, or requested for, the physical wing state.
var info_effective_aoa := 0.0
var info_requested_aerodynamic_force := Vector3.ZERO
