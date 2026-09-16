class_name MechwarriorFlightInputController
extends FlightInputController


func get_display_name() -> String:
	return "MechWarrior"


func create_camera_behavior() -> FlightCameraBehavior:
	return MechwarriorFlightCameraBehavior.new()
