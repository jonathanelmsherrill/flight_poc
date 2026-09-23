extends AnimatableBody3D

@export var velocity := Vector3(0.0, 0.0, 3.0)

# Called every (physics) frame. 
func _physics_process(delta: float) -> void:
	global_position += velocity * delta

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every (visual) frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
