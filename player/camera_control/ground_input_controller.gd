class_name GroundInputController
extends RefCounted

## Small counterpart to FlightInputController. Ground movement can grow its
## own input rules without leaking device queries into Player.
func get_movement_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")


func is_jump_requested() -> bool:
	return Input.is_action_just_pressed("jump")
