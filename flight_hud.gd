extends Control

@export var player: Player
@export var camera: Camera3D

@onready var desired_marker: Label = $IntendedDirection
@onready var velocity_marker: Label = $ActualDirection
@onready var aim_marker: Label = $AimReticle

var aim_reticle_pos : Vector2

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	setup_label(desired_marker)
	setup_label(velocity_marker)
	setup_label(aim_marker)
	aim_reticle_pos = get_viewport().get_visible_rect().size / 2.0
	place_reticle(aim_marker, aim_reticle_pos)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var intent_direction := player.player_intended_direction()
	var player_velocity := player.velocity
	place_reticle(desired_marker,direction_to_screen(intent_direction))
	place_reticle(velocity_marker, direction_to_screen(player_velocity))
	desired_marker.visible = desired_marker.position.distance_squared_to(aim_reticle_pos) > 2
	velocity_marker.visible = player.velocity.length() >= 1

# Project the direction to 100 meters away and figure out where that appears on the camera
func direction_to_screen(direction: Vector3) -> Vector2:
	var world_point := player.global_position + direction.normalized() * 100.0
	return camera.unproject_position(world_point)

#Gotta handle the reticle size - the anchor point is the top left
func place_reticle(reticle: Control, screen_pos: Vector2) -> void:
	reticle.position = screen_pos - reticle.size / 2.0

# Fix weirdness around label container size and make sure text is centered.
func setup_label(label: Control) -> void:
	label.custom_minimum_size = Vector2(32, 32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
