class_name FlyerState
extends RefCounted

## Mutable runtime state shared by the flight controller and physics engine.
## Player refreshes the velocity-derived fields before each simulation step.
var velocity := Vector3.ZERO
var air_velocity_world := Vector3.ZERO
var air_relative_velocity := Vector3.ZERO
var airspeed := 0.0
var is_airborne := false

var body_direction := Vector3.FORWARD
## The direction this wing produces lift at zero AoA.
var wing_lift_direction := Vector3.UP
## The actual normal of the wing surface, including its current AoA tilt.
var wing_normal := Vector3.UP
var target_aoa := 0.0
var actual_aoa := 0.0
var current_flap_direction := Vector3.ZERO
var active_flap_direction := Vector3.ZERO
var requested_aerodynamic_force := Vector3.ZERO
