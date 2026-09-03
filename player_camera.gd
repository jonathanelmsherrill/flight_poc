extends Camera3D

const MOUSE_SENSITIVITY := 0.005
const MAX_PITCH := deg_to_rad(80.0)
const FREELOOK_RETURN_DURATION := 0.15

@onready var player: Player = get_node("../../../../../..")
@onready var camera_pivot: Node3D = get_node("../../../../..")
@onready var camera_pitch: Node3D = get_node("../../../..")
@onready var freelook_pivot: Node3D = get_node("../../..")
@onready var freelook_pitch: Node3D = get_node("../..")
@onready var spring_arm: SpringArm3D = get_node("..")

var freelook_return_tween: Tween


func _ready() -> void:
	spring_arm.add_excluded_object(player.get_rid())


func _input(event: InputEvent) -> void:
	if event.is_action_released("freelook"):
		return_freelook_to_front()

	if not event is InputEventMouseMotion:
		return

	var freelooking := Input.is_action_pressed("freelook")
	if freelooking and freelook_return_tween:
		freelook_return_tween.kill()

	var pivot := freelook_pivot if freelooking else camera_pivot
	var pitch := freelook_pitch if freelooking else camera_pitch

	pivot.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
	pitch.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
	pitch.rotation.x = clampf(pitch.rotation.x, -MAX_PITCH, MAX_PITCH)


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
