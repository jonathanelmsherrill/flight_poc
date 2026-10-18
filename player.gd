extends CharacterBody3D


@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_pitch: Node3D = $CameraPivot/CameraPitch
@onready var stamina_bar: ProgressBar = $CanvasLayer/ProgressBar

const GRAVITY := 9.8 #m/s^2
const JUMP := 4.5 # m/s
const MOVE_SPEED := 22 # m/s
const MAX_STAMINA : float = 100
const STAMINA_RECOVERY : float = 7 #/s
const FLAP_COST : float = 7 #Stamina to flap
const FLAP_STRENGTH : float = JUMP
var stamina := MAX_STAMINA


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	pass # Replace with function body.

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta 
	
	var flying := not is_on_floor()
	
	#Stamina
	stamina = clamp(stamina + STAMINA_RECOVERY * delta,0,100)
	stamina_bar.value = stamina

	
	if not flying:
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
		if Input.is_action_just_pressed("jump") :
			velocity.y += JUMP
	
	if flying:

		
		var up_flap_wanted := Input.is_action_just_pressed("jump") 
		var forward_flap_wanted := Input.is_action_just_pressed("move_forward") 
		if(up_flap_wanted or forward_flap_wanted) and stamina > FLAP_COST:
			var flap_direction : Vector3 = Vector3()
			flap_direction.y = 1 if up_flap_wanted else 0
			flap_direction.z = -1 if forward_flap_wanted else 0
			flap_direction = flap_direction.normalized()
			velocity += flap_direction * FLAP_STRENGTH
			stamina -= FLAP_COST
	
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
