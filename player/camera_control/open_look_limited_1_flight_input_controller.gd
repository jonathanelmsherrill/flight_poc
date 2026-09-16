class_name OpenLookLimited1FlightInputController
extends FlightInputController


func get_display_name() -> String:
	return "Open Look Limited 1"


func create_camera_behavior() -> FlightCameraBehavior:
	return OpenLookLimited1FlightCameraBehavior.new()
