extends Control

@export var player: Player
@export var camera: Camera3D

@onready var desired_marker: Label = $IntendedDirection
@onready var velocity_marker: Label = $ActualDirection
@onready var requested_aerodynamic_force_marker: Label = $RequestedAerodynamicForce
@onready var aim_marker: Label = $AimReticle

var aim_reticle_pos : Vector2
var desired_marker_default_color: Color
var velocity_marker_default_color: Color

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	setup_label(desired_marker)
	setup_label(velocity_marker)
	setup_label(requested_aerodynamic_force_marker)
	setup_label(aim_marker)
	requested_aerodynamic_force_marker.modulate = Color.YELLOW
	desired_marker_default_color = desired_marker.modulate
	velocity_marker_default_color = velocity_marker.modulate
	aim_reticle_pos = get_viewport().get_visible_rect().size / 2.0
	place_reticle(aim_marker, aim_reticle_pos)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var intent_direction := player.player_intended_direction()
	var player_velocity := player.velocity
	var requested_aerodynamic_force := player.flyer_state.info_requested_aerodynamic_force
	place_reticle(desired_marker,direction_to_screen(intent_direction))
	place_reticle(velocity_marker, direction_to_screen(player_velocity))
	place_reticle(
			requested_aerodynamic_force_marker,
			direction_to_screen(requested_aerodynamic_force)
	)
	set_marker_behind_color(
			desired_marker,
			direction_is_behind_camera(intent_direction),
			desired_marker_default_color
	)
	set_marker_behind_color(
			velocity_marker,
			direction_is_behind_camera(player_velocity),
			velocity_marker_default_color
	)
	desired_marker.visible = desired_marker.position.distance_squared_to(aim_reticle_pos) > 2
	velocity_marker.visible = player.velocity.length() >= 1
	requested_aerodynamic_force_marker.visible = requested_aerodynamic_force.length() >= 0.1

# Project the direction to 100 meters away and figure out where that appears on the camera
func direction_to_screen(direction: Vector3) -> Vector2:
	var world_point := player.global_position + direction.normalized() * 100.0
	return camera.unproject_position(world_point)


func direction_is_behind_camera(direction: Vector3) -> bool:
	var world_point := player.global_position + direction.normalized() * 100.0
	return camera.is_position_behind(world_point)


func set_marker_behind_color(marker: Label, is_behind: bool, default_color: Color) -> void:
	marker.modulate = Color.RED if is_behind else default_color

#Gotta handle the reticle size - the anchor point is the top left
func place_reticle(reticle: Control, screen_pos: Vector2) -> void:
	reticle.position = screen_pos - reticle.size / 2.0

# Fix weirdness around label container size and make sure text is centered.
func setup_label(label: Control) -> void:
	label.custom_minimum_size = Vector2(32, 32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
