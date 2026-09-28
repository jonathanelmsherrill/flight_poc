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
