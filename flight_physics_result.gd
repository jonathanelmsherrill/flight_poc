class_name FlightPhysicsResult
extends RefCounted

## Integration output plus the force breakdown used by Player's debug HUD.
var velocity := Vector3.ZERO
var lift_force := Vector3.ZERO
var induced_drag_force := 0.0
var parasite_drag_force := 0.0
var high_aoa_drag_force := 0.0
var high_aoa_drag_vector := Vector3.ZERO


func get_drag_acceleration(flyer_profile: FlyerProfile) -> float:
	return (
			induced_drag_force + parasite_drag_force + high_aoa_drag_force
		) / flyer_profile.base_mass
