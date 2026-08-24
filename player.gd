extends CharacterBody3D

var gravity: float = 9.8
var move_speed: float = 6.0

# JUMP
var jump_velocity: float = 3.5

# FLIGHT
var flap_interval := 1.25
var flap_impulse := 5.2
var flap_timer := 0.0
var tap_flap_min_interval := 0.15
var tap_flap_timer := 0.0
var max_stamina := 100.0
var stamina := max_stamina
var stamina_recovery := 25.0
var flap_stamina_cost := 14.0
var tap_flap_cost_multiplier := 1.5
var MAX_UP_VELOCITY := 6.0
var FLIGHT_SPEED := 9.0
var air_acceleration: float = 4.0
var air_turn_rate: float = 2.5
const AIR_DRAG_COEFFICIENT := 0.04 # 0.04 * 10^2 = 4 drag at speed 10.
const MAX_TURN_DRAG := 3.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_pitch: Node3D = $CameraPivot/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraPivot/CameraPitch/SpringArm3D
@onready var stamina_bar: ProgressBar = $CanvasLayer/ProgressBar



func _physics_process(delta: float) -> void:
	flap_timer = max(flap_timer - delta,-10)
	tap_flap_timer = max(tap_flap_timer - delta, 0.0)
	
	var flying_state = not is_on_floor()

	if not is_on_floor():
		# Gravity. Keeping seperate from flying state in case that's ever not just not on floor.
		velocity.y -= gravity * delta

	#move_and_slide()

	var input_vector := Input.get_vector(
			"move_left",
			"move_right",
			"move_forward",
			"move_backward"
	)

	var forward := -camera_pivot.global_basis.z
	var right := camera_pivot.global_basis.x

	forward.y = 0
	right.y = 0

	forward = forward.normalized()
	right = right.normalized()

	var direction := (
			right * input_vector.x +
			forward * -input_vector.y
	).normalized()

	if not flying_state: 
		#Walking
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed

	if flying_state:
		# Lift
		var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
		var horizontal_speed := horizontal_velocity.length()
		var lift_fraction := clampf(horizontal_speed / FLIGHT_SPEED, 0.0, 1.0)
		var lift_acceleration := gravity * lift_fraction
		velocity.y += lift_acceleration * delta
		# Thrust and turning
		var turn_sharpness := 0.0
		if direction.length() > 0.0:
			if horizontal_speed > 0.01:
				var current_direction := horizontal_velocity.normalized()
				turn_sharpness = acos(
					clampf(current_direction.dot(direction), -1.0, 1.0)
				) / PI
				var new_direction := current_direction.slerp(
					direction,
					clampf(air_turn_rate * delta, 0.0, 1.0)
				).normalized()
				horizontal_velocity = new_direction * horizontal_speed
			else:
				horizontal_velocity = direction

			# Thrust has no hard speed cap; drag defines the eventual top speed.
			horizontal_speed += air_acceleration * delta

		var air_drag := AIR_DRAG_COEFFICIENT * horizontal_speed * horizontal_speed
		var turn_drag := MAX_TURN_DRAG * turn_sharpness * turn_sharpness
		horizontal_speed = maxf(
			0.0,
			horizontal_speed - (air_drag + turn_drag) * delta
		)
		if horizontal_speed > 0.0:
			horizontal_velocity = horizontal_velocity.normalized() * horizontal_speed

		velocity.x = horizontal_velocity.x
		velocity.z = horizontal_velocity.z

	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = jump_velocity
		elif tap_flap_timer <= 0.0:
			var tap_flap_cost := flap_stamina_cost * tap_flap_cost_multiplier
			if stamina >= tap_flap_cost:
				# A fresh press while airborne bypasses the hold-flap cooldown.
				flap()
				stamina -= tap_flap_cost
				flap_timer = flap_interval
				tap_flap_timer = tap_flap_min_interval

	if Input.is_action_pressed("jump") and stamina >= flap_stamina_cost and flap_timer <= 0.0:
		flap()
		stamina -= flap_stamina_cost
		flap_timer = flap_interval
	
	#if not Input.is_action_pressed("jump") or stamina < flap_stamina_cost:
	stamina = min(stamina + stamina_recovery * delta, max_stamina)

	stamina = clamp(stamina, 0.0, max_stamina)
	stamina_bar.value = stamina
	move_and_slide()	
	

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	spring_arm.add_excluded_object(get_rid())
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina	

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion:
		camera_pivot.rotate_y(-event.relative.x * 0.005)
		camera_pitch.rotate_x(-event.relative.y * 0.005)
		camera_pitch.rotation.x = clamp(
			camera_pitch.rotation.x,
			deg_to_rad(-80),
			deg_to_rad(80)
		)


func flap() -> void:
	var flap_target_velocity := MAX_UP_VELOCITY
	var flap_effectiveness: float = clamp(
			1.0 - velocity.y / flap_target_velocity,
			0.0,
			1.0
	)
	
	velocity.y += flap_impulse * flap_effectiveness
	
