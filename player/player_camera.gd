class_name PlayerCamera
extends Camera3D

const MAX_PITCH := deg_to_rad(80.0)
const FREELOOK_RETURN_DURATION := 0.15

@onready var player: Player = get_node("../../../../../..")
@onready var camera_pivot: Node3D = get_node("../../../../..")
@onready var camera_pitch: Node3D = get_node("../../../..")
@onready var freelook_pivot: Node3D = get_node("../../..")
@onready var freelook_pitch: Node3D = get_node("../..")
@onready var spring_arm: SpringArm3D = get_node("..")

var freelook_return_tween: Tween
var flight_camera_behavior: FlightCameraBehavior


func _ready() -> void:
	spring_arm.add_excluded_object(player.get_rid())


func _process(delta: float) -> void:
	if flight_camera_behavior:
		flight_camera_behavior.process_camera(_get_reference_direction(), delta)


func _input(event: InputEvent) -> void:
	if event.is_action_released("freelook"):
		return_freelook_to_front()

	if not event is InputEventMouseMotion:
		return

	var freelooking := Input.is_action_pressed("freelook")
	if freelooking and freelook_return_tween:
		freelook_return_tween.kill()

	if freelooking:
		freelook_pivot.rotate_y(-event.relative.x * OpenLookLimited1FlightCameraBehavior.MOUSE_SENSITIVITY)
		freelook_pitch.rotate_x(-event.relative.y * OpenLookLimited1FlightCameraBehavior.MOUSE_SENSITIVITY)
		freelook_pitch.rotation.x = clampf(freelook_pitch.rotation.x, -MAX_PITCH, MAX_PITCH)
	elif flight_camera_behavior:
		flight_camera_behavior.handle_mouse_motion(
				event.relative,
				get_viewport().get_visible_rect().size
		)


func set_flight_camera_behavior(new_behavior: FlightCameraBehavior) -> void:
	flight_camera_behavior = new_behavior
	flight_camera_behavior.setup(camera_pivot, camera_pitch)
	flight_camera_behavior.activate(_get_reference_direction())


func get_steering_direction() -> Vector3:
	if flight_camera_behavior:
		flight_camera_behavior.update_body_direction(_get_reference_direction())
		return flight_camera_behavior.get_steering_direction()
	return -camera_pitch.global_basis.z.normalized()


func get_control_cursor_screen_position() -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	if not flight_camera_behavior:
		return viewport_size * 0.5
	return viewport_size * 0.5 + (
			flight_camera_behavior.get_control_cursor_offset()
			* viewport_size * 0.45
	)


func get_active_reference_direction() -> Vector3:
	return _get_reference_direction()


func _get_reference_direction() -> Vector3:
	if flight_camera_behavior:
		return flight_camera_behavior.get_reference_direction(player)
	return player.visible_flight_direction()


func return_freelook_to_front() -> void:
	if freelook_return_tween:
		freelook_return_tween.kill()

	freelook_return_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	freelook_return_tween.set_parallel(true)
	freelook_return_tween.tween_property(
			freelook_pivot,
			"rotation:y",
			0.0,
			FREELOOK_RETURN_DURATION
	)
	freelook_return_tween.tween_property(
			freelook_pitch,
			"rotation:x",
			0.0,
			FREELOOK_RETURN_DURATION
	)
