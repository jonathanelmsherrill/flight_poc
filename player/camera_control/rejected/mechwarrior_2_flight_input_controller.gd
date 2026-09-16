class_name Mechwarrior2FlightInputController
extends FlightInputController


func get_display_name() -> String:
	return "MechWarrior 2"


func create_camera_behavior() -> FlightCameraBehavior:
	return Mechwarrior2FlightCameraBehavior.new()
