extends CharacterBody3D


@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_pitch: Node3D = $CameraPivot/CameraPitch

const GRAVITY := 9.8 #m/s^2
const JUMP := 4.5 # m/s
const MOVE_SPEED := 22 # m/s

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	pass # Replace with function body.

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta 
	
	var input_vector := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var forward := camera_pivot.global_basis.z * -1
	var right := camera_pivot.global_basis.x
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	
	var move_direction := (forward * input_vector.y + right * input_vector.x).normalized()
	
	velocity.x = move_direction.x * MOVE_SPEED
	velocity.z = move_direction.z * MOVE_SPEED
	
	#JUMP
	if Input.is_action_just_pressed("jump"):
		velocity.y += JUMP
	
	move_and_slide()
		


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		camera_pivot.rotate_y(-1*event.relative.x * 0.005)
		camera_pitch.rotate_x(-1*event.relative.y * 0.005)
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
