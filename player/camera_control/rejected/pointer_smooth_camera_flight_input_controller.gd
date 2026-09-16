class_name PointerSmoothCameraFlightInputController
extends FlightInputController


func get_display_name() -> String:
	return "Pointer + Smooth Camera"


func create_camera_behavior() -> FlightCameraBehavior:
	return PointerSmoothCameraFlightCameraBehavior.new()
