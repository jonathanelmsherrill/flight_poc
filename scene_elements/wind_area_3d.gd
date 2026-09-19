class_name WindArea3D
extends Area3D

@export var local_wind_velocity := Vector3(0.0, 5.0, 0.0)

@onready var wind_collision: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func get_wind_at(world_position: Vector3) -> Vector3:
	# Sampling in the collision shape's local space automatically accounts for
	# scale applied either to this area instance or to the shape itself.
	var local_pos := wind_collision.to_local(world_position)
	var cylinder := wind_collision.shape as CylinderShape3D
	var radius := maxf(cylinder.radius, 0.0001)
	var horizontal_distance := Vector2(
			local_pos.x,
			local_pos.z
	).length()

	var radial_strength := clampf(
			1.0 - horizontal_distance / radius,
			0.0,
			1.0
	)

	var local_wind := local_wind_velocity * radial_strength
	# Scaling the node changes the size of the falloff region through to_local(),
	# but must not multiply the configured wind speed. Keep only the rotation so
	# local_wind_velocity still follows the area's orientation.
	var wind_rotation := global_transform.basis.orthonormalized()
	return wind_rotation * local_wind

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_wind_area"):
		body.enter_wind_area(self)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_wind_area"):
		body.exit_wind_area(self)

