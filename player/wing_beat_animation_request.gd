class_name WingBeatAnimationRequest
extends RefCounted

## Everything the wing animator needs to render one physical power stroke.
## thrust_direction is the world-space force applied to the flyer; the visible
## wing stroke moves air in the opposite direction.
var airflow_speed := 0.0
var thrust_direction := Vector3.UP
var power_stroke_duration := 0.2
var recovery_duration := 0.2
## Time spent cocked for the next regular stroke before relaxing to a glide.
var prepared_hold_duration := 0.0


func _init(
		new_airflow_speed: float = 0.0,
		new_thrust_direction: Vector3 = Vector3.UP,
		new_power_stroke_duration: float = 0.2,
		new_recovery_duration: float = 0.2,
		new_prepared_hold_duration: float = 0.0
) -> void:
	airflow_speed = maxf(new_airflow_speed, 0.0)
	thrust_direction = new_thrust_direction.normalized()
	power_stroke_duration = maxf(new_power_stroke_duration, 0.01)
	recovery_duration = maxf(new_recovery_duration, 0.01)
	prepared_hold_duration = maxf(new_prepared_hold_duration, 0.0)
