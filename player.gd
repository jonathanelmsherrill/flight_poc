extends CharacterBody3D

#Flight observations to fix
# You slow to a stop too quickly after releasing w. Either drag is too high or wing power too low
# Right now, regular pulse flying drains stamina (Fixed? )
# Lift isn't as significant as I want. I can almost as effectively fly straight up 
# 
#Handy formula: air drag * max_speed_squared = flap_impulse, so max_speed = sqrt(flap_speed/air_drag)

@export var flyer_profile: FlyerProfile

var gravity: float = 9.8
var ground_move_speed: float = 8.0

# JUMP
var jump_velocity: float = 4.5

# FLIGHT
var time_since_flap := 10.0
var extra_flap_min_interval := 0.15
var regular_flap_min_interval := 1.10
var flap_impulse := 2.5
#The below may feel like a flyer parameter, but this and the stamina fields can all be multiplied by a value
#and the net effect is the same. Thus, this could hypothetically always be 1. 1 stamina is one unit of flap.
#However, keeping it here for now as it allows me to easily modify the cost of flying for experimentation.
var flap_stamina_cost := 10
var extra_flap_cost_multiplier := 1.5
var extra_flap_power_multiplier := 1.5

#Stamina
var max_stamina := 100.0
var stamina := max_stamina
var stamina_recovery := 7

#Lift
var FLIGHT_SPEED := 20.0 #This is speed necessary for gravity-equaling lift

#var air_acceleration: float = 3.0 # replaced by forward_flap
var air_turn_rate: float = 2.5
const AIR_DRAG_COEFFICIENT := 0.008



# Flight - visual
const MAX_VISUAL_TILT := deg_to_rad(55.0)
const FULL_TILT_SPEED := 12.0
const VISUAL_TILT_SPEED := 5.0
var flap_tween: Tween

# Sharp-turn behavior
const MIN_SHARP_TURN_SPEED := 1.5
const TURN_BRAKING := 18.0




@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_pitch: Node3D = $CameraPivot/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraPivot/CameraPitch/SpringArm3D
@onready var stamina_bar: ProgressBar = $CanvasLayer/ProgressBar
@onready var visual_root: Node3D = $VisualRoot

# Debug
@onready var speed_label: Label = $CanvasLayer/DebugContainer/SpeedLabel
@onready var lift_label: Label = $CanvasLayer/DebugContainer/LiftLabel
@onready var drag_label: Label = $CanvasLayer/DebugContainer/DragLabel


func _physics_process(delta: float) -> void:
	time_since_flap = minf(time_since_flap + delta, 10.0)

	var flying_state := not is_on_floor()

	# Gravity
	if flying_state:
		velocity.y -= gravity * delta

	var input_vector := Input.get_vector(
			"move_left",
			"move_right",
			"move_forward",
			"move_backward"
	)
	var fresh_keypress := (Input.is_action_just_pressed("move_left") 
		or Input.is_action_just_pressed("move_right")
		or Input.is_action_just_pressed("move_forward")
		or Input.is_action_just_pressed("move_backward"))
		

	var camera_forward := -camera_pitch.global_basis.z
	var camera_right := camera_pitch.global_basis.x

	# Walking uses the camera's heading, ignoring its pitch.
	var ground_forward := camera_forward
	var ground_right := camera_right
	ground_forward.y = 0.0
	ground_right.y = 0.0
	ground_forward = ground_forward.normalized()
	ground_right = ground_right.normalized()


	# WALKING
	if not flying_state:
		var player_intended_direction := (
				ground_right * input_vector.x +
				ground_forward * -input_vector.y
		).normalized()
		
		velocity.x = player_intended_direction.x * ground_move_speed
		velocity.z = player_intended_direction.z * ground_move_speed
		
		visual_root.rotation.x = lerp_angle(
				visual_root.rotation.x,
				0.0,
				VISUAL_TILT_SPEED * delta
		)
		debug_drag(0)
		debug_lift(0.0)
		debug_speed(velocity)

	# FLYING
	if flying_state:
		var player_intended_direction := (
				camera_right * input_vector.x +
				camera_forward * -input_vector.y
		).normalized()
		
		var horizontal_velocity := Vector3(
				velocity.x,
				0.0,
				velocity.z
		)		
		var horizontal_speed := horizontal_velocity.length()


		# ----------------
		# LIFT
		# ----------------

		var lift_fraction := clampf(
				horizontal_speed / FLIGHT_SPEED / 1.1,
				0.0,
				1.1
		)

		var lift_acceleration := gravity * lift_fraction
		velocity.y += lift_acceleration * delta
		debug_lift(lift_acceleration)

		var flight_velocity := velocity
		var flight_speed := flight_velocity.length()


		# ----------------
		# TURNING - wings shifting velocity vector based on camera direction + keypress 
		# ----------------

		var turn_sharpness := 0.0

		if player_intended_direction.length() > 0.0: # Only turn if we indicate we're trying to move

			if flight_speed > 0.01:
				var current_direction := flight_velocity.normalized()

				# 0 = same direction
				# 0.5 = 90 degrees
				# 1 = complete reversal
				turn_sharpness = acos(
						clampf(
								current_direction.dot(player_intended_direction),
								-1.0,
								1.0
						)
				) / PI

				# Redirect at a constant angular rate
				var direction_dot := clampf(
						current_direction.dot(player_intended_direction),
						-1.0,
						1.0
				)
				var remaining_angle := acos(direction_dot)
				var new_direction: Vector3

				if remaining_angle <= 0.0001:
					new_direction = player_intended_direction
				else:
					var turn_fraction := minf(
							air_turn_rate * delta / remaining_angle,
							1.0
					)
					new_direction = current_direction.slerp(
							player_intended_direction,
							turn_fraction
					).normalized()

				flight_velocity = new_direction * flight_speed
				horizontal_velocity = Vector3(
						flight_velocity.x,
						0.0,
						flight_velocity.z
				)
				horizontal_speed = horizontal_velocity.length()
				velocity.y = flight_velocity.y

			else:
				# If we're basically stationary, just establish
				# an initial direction.
				horizontal_velocity = player_intended_direction

		# ----------------
		# THRUST / FLAPPING
		# ----------------
		# Refresh after flap impulses so their added velocity is not discarded.
		horizontal_velocity = Vector3(velocity.x, 0.0, velocity.z)
		horizontal_speed = horizontal_velocity.length()
		var movement_input := player_intended_direction.length() > 0.0
		var space_held := Input.is_action_pressed("jump")
		var space_pressed := Input.is_action_just_pressed("jump")
		var wants_flap := movement_input or space_held
		var force_flap := (
				space_pressed
				and time_since_flap >= extra_flap_min_interval
				and time_since_flap < regular_flap_min_interval
		)

		if flying_state and wants_flap and (
				force_flap or time_since_flap >= regular_flap_min_interval
		) and stamina >= flap_stamina_cost:
			var flap_direction := player_intended_direction
			if space_held:
				flap_direction = Vector3.UP if not movement_input else (
						Vector3.UP + player_intended_direction
				).normalized()

			var velocity_conversion_fraction := clampf(
					horizontal_speed / (2.0 * flap_impulse),
					0.0,
					1.0
			)
			var thrust_effectiveness := (1.0 - (
					0.75 * turn_sharpness * velocity_conversion_fraction
			)) * extra_flap_power_multiplier if force_flap else 1.0
			
			flap(flap_direction, thrust_effectiveness)
			stamina -= flap_stamina_cost * extra_flap_cost_multiplier if force_flap else flap_stamina_cost
			time_since_flap = 0.0
		debug_speed(velocity)
		# Include any flap impulse in the vector passed to drag.
		horizontal_velocity = Vector3(velocity.x, 0.0, velocity.z)
		horizontal_speed = horizontal_velocity.length()
			
		# ----------------
		# DRAG
		# ----------------
		# Narrow turns keep nearly all current speed.
		# Very sharp turns push the allowed speed toward
		# MIN_SHARP_TURN_SPEED.
		var braking_factor := turn_sharpness * turn_sharpness
		var turn_speed_limit := lerpf(
				horizontal_speed,
				MIN_SHARP_TURN_SPEED,
				braking_factor
		)

		horizontal_speed = move_toward(
				horizontal_speed,
				turn_speed_limit,
				TURN_BRAKING * delta
		)

		# Normal air drag increases with total 3D speed.
		flight_velocity = Vector3(
				horizontal_velocity.x,
				velocity.y,
				horizontal_velocity.z
		)
		flight_speed = flight_velocity.length()

		var air_drag := (
				AIR_DRAG_COEFFICIENT *
				flight_speed *
				flight_speed
		)

		flight_speed = maxf(
				0.0,
				flight_speed - air_drag * delta
		)
		debug_drag(air_drag)

		# Reapply final speed to the full 3D direction.
		if flight_velocity.length() > 0.01:
			velocity = flight_velocity.normalized() * flight_speed

		# ------------------
		# Tilt to indicate velocity
		
		var speed_fraction := clampf(
				horizontal_speed / FULL_TILT_SPEED,
				0.0,
				1.0
		)
		
		var target_tilt := -MAX_VISUAL_TILT * speed_fraction
		
		visual_root.rotation.x = lerp_angle(
		visual_root.rotation.x,
		target_tilt,
		VISUAL_TILT_SPEED * delta
		)



	# ----------------
	# JUMP / TAP FLAP
	# ----------------

	if Input.is_action_just_pressed("jump"):

		if not flying_state:
			velocity.y = jump_velocity
			time_since_flap = regular_flap_min_interval / 2.0

		elif time_since_flap >= extra_flap_min_interval:
			var tap_flap_cost := (
					flap_stamina_cost *
					extra_flap_cost_multiplier
			)

			if stamina >= tap_flap_cost:
				flap(Vector3.UP)

				stamina -= tap_flap_cost
				time_since_flap = 0.0



	# ----------------
	# STAMINA
	# ----------------

	stamina = min(
			stamina + stamina_recovery * delta,
			max_stamina
	)

	stamina = clamp(
			stamina,
			0.0,
			max_stamina
	)

	stamina_bar.value = stamina
	
	# -----------
	# Camera and tilt
	#-------------
	# That is, if we're tilted, point the tilt in the direction of motion.
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.1:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		
		visual_root.rotation.y = lerp_angle(
		visual_root.rotation.y,
		target_yaw,
		5.0 * delta
		)

	move_and_slide()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	spring_arm.add_excluded_object(
			get_rid()
	)

	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseMotion:
		camera_pivot.rotate_y(
				-event.relative.x * 0.005
		)

		camera_pitch.rotate_x(
				-event.relative.y * 0.005
		)

		camera_pitch.rotation.x = clamp(
				camera_pitch.rotation.x,
				deg_to_rad(-80),
				deg_to_rad(80)
		)


func flap(flap_direction: Vector3, flap_effectiveness: float = 1.0) -> void:
	velocity += flap_direction.normalized() * flap_impulse * flap_effectiveness
	flap_visual()
	


func flap_visual() -> void:
	if flap_tween:
		flap_tween.kill()

	visual_root.scale = Vector3.ONE

	flap_tween = create_tween()

	flap_tween.tween_property(
			visual_root,
			"scale",
			Vector3(1.25, 0.85, 1.25),
			0.08
	)

	flap_tween.tween_property(
			visual_root,
			"scale",
			Vector3.ONE,
			0.18
	)


func debug_speed(velocity : Vector3):
	speed_label.text = "Speed: %.1f m/s" % velocity.length()
	
func debug_lift(lift_acceleration : float):
	lift_label.text = "Lift: %.0f%% gravity" % (
		lift_acceleration / gravity * 100.0
	)

func debug_drag(drag_acceleration : float):
	drag_label.text = "Drag: %.1f m/s²" % drag_acceleration
