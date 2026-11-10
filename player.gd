extends CharacterBody3D


@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_pitch: Node3D = $CameraPivot/CameraPitch
@onready var stamina_bar: ProgressBar = $CanvasLayer/ProgressBar
@onready var debug_container: DebugContainer = $CanvasLayer/DebugContainer 

const GRAVITY : float = 9.8 #m/s^2
const JUMP := 4.5 # m/s
const MOVE_SPEED := 22 # m/s
const MAX_STAMINA : float = 100
const STAMINA_RECOVERY : float = 7 #/s
const FLAP_COST : float = 7 #Stamina to flap
const FLAP_STRENGTH : float = JUMP
const FLIGHT_SPEED : float = 12.0 # m/s
const FLAP_NORMAL_LENGTH : float = 0.7 # seconds between sustained flaps 
const AIR_DRAG_COEFFICIENT : float = 0.04 # 0.04 * 10^2 = 4 drag at speed 10.
const INDUCED_DRAG_COEFFICIENT : float = 0.05 # 0.05 is about 0.05*(9.8 m/s^2)^2 / (10m/s)^2 = around 0.5 m/s drag at speed 10, to 1 m/s drag around speed 2.5 to 5 m/s drag at speed 1
const GENTLE_MAX_TURN_RATE : float = PI/8.0 #For gentle turns, pi/4 = 45o/second 
const GENTLE_MIN_RESPONSE_TIME : float = 0.6 #For small turns, we take at least this long to avoid small sharp corrections needlessly costing drag
const STRUCTURAL_LOAD_TOLERANCE : float = 900 #Newtons
var BASE_MASS : float = 45 # kg
var stamina := MAX_STAMINA
var time_since_flap : float = 0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	pass # Replace with function body.

func _physics_process(delta: float) -> void:

	
	var flying := not is_on_floor()
	
	#Stamina
	stamina = clamp(stamina + STAMINA_RECOVERY * delta,0,100)
	stamina_bar.value = stamina

	var forward := camera_pitch.global_basis.z * -1
	var right := camera_pitch.global_basis.x
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()

	
	if not flying:
		var input_vector := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
		var move_direction := (forward * input_vector.y + right * input_vector.x).normalized()
	
		velocity.x = move_direction.x * MOVE_SPEED
		velocity.z = move_direction.z * MOVE_SPEED

		#JUMP
		if Input.is_action_just_pressed("jump") :
			velocity.y += JUMP
	
	if flying:
		
		var flying_speed = velocity.length()
		time_since_flap += delta 
		
		# INPUT
		var desired_direction := forward #Camera forward - where we're looking
		var wants_directed_flap := 	Input.is_action_pressed("move_forward")
		var wants_backward := Input.is_action_pressed("move_backward")
		var wants_upward_flap := Input.is_action_pressed("jump")	
		
		# INTENT
		var desired_force := get_desired_force(velocity, desired_direction)
		if desired_force.length() > STRUCTURAL_LOAD_TOLERANCE:
			desired_force *= STRUCTURAL_LOAD_TOLERANCE / desired_force.length()
		
		
		#PHYSICS
		var updated_velocity := apply_energy_neutral_lift(velocity, desired_force, BASE_MASS, delta)
		var effective_lift_force := (updated_velocity - velocity) * BASE_MASS / delta
		var lift_fraction := effective_lift_force.dot(Vector3.UP) / (GRAVITY * BASE_MASS)
				
		# Parasitical Drag
		var air_drag : float = AIR_DRAG_COEFFICIENT * flying_speed * flying_speed * delta
		
		# INDUCED DRAG
		var induced_drag : float = INDUCED_DRAG_COEFFICIENT * effective_lift_force.length_squared() / max(flying_speed * flying_speed,0.1) / BASE_MASS * delta
		
		updated_velocity = updated_velocity.normalized() * max(flying_speed - air_drag - induced_drag, 0)

		var up_flap_wanted := Input.is_action_just_pressed("jump") or wants_upward_flap and time_since_flap > FLAP_NORMAL_LENGTH
		var forward_flap_wanted := Input.is_action_just_pressed("move_forward") or wants_directed_flap and time_since_flap > FLAP_NORMAL_LENGTH
		if(up_flap_wanted or forward_flap_wanted) and stamina > FLAP_COST:
			time_since_flap = 0
			var flap_direction : Vector3 = forward if forward_flap_wanted else Vector3()
			flap_direction.y = 1 if up_flap_wanted else 0
			flap_direction = flap_direction.normalized()
			updated_velocity += flap_direction * FLAP_STRENGTH
			stamina -= FLAP_COST


		
		
		# GRAVITY
		updated_velocity.y -= GRAVITY * delta

		

		# APPLY UPDATE
		velocity = updated_velocity
		
		
		
		# DEBUG DISPLAY


		debug_container.submit("induced_drag", str(induced_drag) + "%")
		debug_container.submit("Lift % of Gravity", str(lift_fraction) + "%")
		debug_container.submit("Drag", str(air_drag/delta) + "m/s")
	
	move_and_slide()

func get_desired_force(flight_velocity : Vector3, desired_direction : Vector3) -> Vector3:
	
	var flight_direction := flight_velocity.normalized()
	var flight_speed := flight_velocity.length()
	
	var gravity_force := Vector3.DOWN * BASE_MASS * GRAVITY# And we want to preemptively oppose it, so steering_force takes us where we want to go from here
	var desired_support_force := -1*orthogonal_component(gravity_force, flight_direction)
	# This counters the component of gravity perpendicular to our flight direction, which works fine when level or pitching down and generally also works when pitching up since lift becomes increasingly less useful for countering gravity.
	var steering_direction := orthogonal_component(desired_direction, flight_direction)
	var turn_angle := acos(clampf(flight_direction.dot(desired_direction), -1.0, 1.0)) # Get the difference in angle
	var desired_turn_rate := minf(turn_angle / GENTLE_MIN_RESPONSE_TIME, GENTLE_MAX_TURN_RATE)
	
	var steering_force := steering_direction * (
			BASE_MASS * flight_speed * desired_turn_rate
	)
	var requested_force := desired_support_force + steering_force
	return requested_force 
	
## We apply our lift force, and make sure the total energy is the same.
func apply_energy_neutral_lift(velocity: Vector3, lift_force: Vector3, mass: float, delta: float) -> Vector3:
	var airspeed := velocity.length()
	var updated_velocity := velocity + lift_force / mass * delta
	return updated_velocity.normalized() * airspeed
		


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		camera_pivot.rotate_y(-1*event.relative.x * 0.005)
		camera_pitch.rotate_x(-1*event.relative.y * 0.005)
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## Also known as vector rejection. Remove all trace of reference_vector from direction,
## leaving a vector perpendicular to reference_vector (on a plane defined by direction and reference vector).
## Identical to the component of "direction" to a vector perpendicular to reference_vector. 
func orthogonal_component(direction: Vector3, reference_vector: Vector3) -> Vector3:
	return direction - reference_vector * direction.dot(reference_vector)		
