@abstract
class_name WingAnimation
extends Node3D

## Visual wing implementation used by Player. Implementations own any wing
## geometry they create beneath this node and may animate the supplied body.
@abstract
func configure(body_visual: Node3D, fast_power_stroke_airspeed: float) -> void


## Renders one physical wingbeat without deciding when or where force applies.
@abstract
func play_beat(request: WingBeatAnimationRequest) -> void


## Receives the flyer's velocity every physics frame, beating or not, so rigs
## can shape their resting pose (glide trim, dive tuck, folded while standing).
## Optional.
func update_flight_state(_flight_velocity: Vector3, _is_airborne: bool) -> void:
	pass


## How far the wings open while on the ground, from 0 (folded) to 1 (spread as
## in flight), such as when raised to catch air during a takeoff sprint.
## Optional.
func set_ground_spread(_spread: float) -> void:
	pass
