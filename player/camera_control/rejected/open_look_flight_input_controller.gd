class_name OpenLookFlightInputController
extends FlightInputController


func get_display_name() -> String:
	return "Open Look"


func create_camera_behavior() -> FlightCameraBehavior:
	return OpenLookFlightCameraBehavior.new()
