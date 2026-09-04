class_name Player
extends CharacterBody3D

#Flight observations to fix


@export var flyer_profile: FlyerProfile

var gravity: float = 9.8
var ground_move_speed: float = 8.0

# JUMP
var jump_velocity: float = 4.5

# FLIGHT
var time_since_flap := 10.0
var current_flap_direction := Vector3.ZERO
var requested_aerodynamic_force := Vector3.ZERO
var aerodynamic_force_calculation_difference := 0.0
# This and the stamina fields can all be multiplied by a value
# and the net effect is the same. Thus, this could hypothetically always be 1. 1 stamina would then be one unit of flap.
# However, keeping it here for now as it allows me to easily modify the cost of flying for experimentation.
const FLAP_STAMINA_COST := 9.0
var extra_flap_cost_multiplier := 1.5
const POWER_STROKE_PERCENTAGE := 0.2
const INDUCED_DRAG_COEFFICIENT := 0.14#Not even sure what unit this is, but folds in wing aspect ratio. 

# Flight - visual
const MAX_VISUAL_TILT := deg_to_rad(55.0)
const FULL_TILT_SPEED := 12.0
const VISUAL_TILT_SPEED := 5.0
var flap_tween: Tween
var stamina : float


@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_pitch: Node3D = $CameraPivot/CameraPitch
@onready var stamina_bar: ProgressBar = $CanvasLayer/ProgressBar
@onready var visual_root: Node3D = $VisualRoot

# Debug
@onready var speed_label: Label = $CanvasLayer/DebugContainer/SpeedLabel
@onready var horizontal_speed_label: Label = $CanvasLayer/DebugContainer/HorizontalSpeedLabel
@onready var vertical_speed_label: Label = $CanvasLayer/DebugContainer/VerticalSpeedLabel
@onready var total_energy_label: Label = $CanvasLayer/DebugContainer/TotalEnergyLabel
@onready var requested_aerodynamic_force_label: Label = $CanvasLayer/DebugContainer/RequestedAerodynamicForceLabel
@onready var aerodynamic_force_difference_label: Label = $CanvasLayer/DebugContainer/AerodynamicForceDifferenceLabel
@onready var lift_label: Label = $CanvasLayer/DebugContainer/LiftLabel
@onready var drag_label: Label = $CanvasLayer/DebugContainer/DragLabel


func _physics_process(delta: float) -> void:
	time_since_flap = minf(time_since_flap + delta, 10.0)

	var flying_state := not is_on_floor()
	if not flying_state:
		requested_aerodynamic_force = Vector3.ZERO
		aerodynamic_force_calculation_difference = 0.0

	var input_vector := Input.get_vector(
			"move_left",
			"move_right",
			"move_forward",
			"move_backward"
	)
	var camera_forward := -camera_pitch.global_basis.z
	var camera_right := camera_pitch.global_basis.x

	# Walking uses the camera's heading, ignoring its pitch.
	var ground_forward := camera_forward
	var ground_right := camera_right
	ground_forward.y = 0.0
	ground_right.y = 0.0
	ground_forward = ground_forward.normalized()
	ground_right = ground_right.normalized()


	# Gravity - Always applies unless touching grass. Might someday apply on steep slopes, during a crash/slide, etc
	# sky's not the limit, it's actually the simple use-case. Go down.
	if not is_on_floor():
		velocity.y -= gravity * delta


	# WALKING - Just go where pointed.
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

		# ----------------
		# JUMP / TAP FLAP
		# ----------------
	
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
			time_since_flap = flyer_profile.flap_cycle_duration / 2.0
			
			
		debug_drag(0)
		debug_lift(0.0)

	# FLYING
	if flying_state:
		
		var player_intended_direction := (
				camera_right * input_vector.x +
				camera_forward * -input_vector.y
		).normalized()

		# ----------------
		# FLAP PLAN / POWER STROKE
		# ----------------
		update_flap_plan(player_intended_direction)
		apply_flap_force(delta)

		

		# ----------------
		# LIFT AND TURNING - wings shifting velocity vector based on camera direction + keypress 
		# ----------------

		apply_aerodynamics(delta)

		
			
		# ----------------
		# PARASITICAL DRAG
		# ----------------
		apply_drag_force(flyer_profile.parasite_drag_coefficient*velocity.length_squared(),delta)
		

		# ------------------
		# Tilt to indicate velocity
		var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
		var horizontal_speed := horizontal_velocity.length()
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
	# STAMINA RECOVERY
	# ----------------

	stamina = minf(
			stamina + flyer_profile.stamina_recovery * delta,
			flyer_profile.max_stamina
	)

	stamina = clamp(
			stamina,
			0.0,
			flyer_profile.max_stamina
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

	debug_speed(velocity)
	debug_horizontal_speed(velocity)
	debug_vertical_speed(velocity)
	debug_total_energy()
	debug_requested_aerodynamic_force()
	debug_aerodynamic_force_difference()
	move_and_slide()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	stamina = flyer_profile.max_stamina
	stamina_bar.max_value = flyer_profile.max_stamina
	stamina_bar.value = stamina


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# We assume the player wants to go where they're looking for now
func player_intended_direction() -> Vector3:
	return -camera_pitch.global_basis.z

func inside_power_stroke() -> bool:
	return time_since_flap < (
			flyer_profile.flap_cycle_duration *
			POWER_STROKE_PERCENTAGE
	)

# This triggers flapping - either continuous or the extra one. 
func update_flap_plan(player_intended_direction: Vector3) -> void:
	var movement_held := player_intended_direction.length() > 0.0
	var space_held := Input.is_action_pressed("jump")
	var space_pressed := Input.is_action_just_pressed("jump")
	var wants_flap := movement_held or space_held

	if space_held:
		current_flap_direction = Vector3.UP if not movement_held else (
				Vector3.UP + player_intended_direction
		).normalized()
	elif movement_held:
		current_flap_direction = player_intended_direction

	var regular_flap_due := time_since_flap >= flyer_profile.flap_cycle_duration
	var extra_flap_requested := (
			space_pressed
			and not inside_power_stroke()
			and not regular_flap_due
	)

	if not wants_flap or not (regular_flap_due or extra_flap_requested):
		return

	var stamina_cost := FLAP_STAMINA_COST
	if extra_flap_requested:
		stamina_cost *= extra_flap_cost_multiplier

	if stamina < stamina_cost:
		return

	stamina -= stamina_cost
	time_since_flap = 0.0
	flap_visual()

# This is the continual force delivered during the power stroke of the flap cycle.
func apply_flap_force(delta: float) -> void:
	if not inside_power_stroke() or current_flap_direction == Vector3.ZERO:
		return

	var speed := velocity.length()
	var power_limited_force := flyer_profile.max_flap_force
	if speed > 0.01:
		power_limited_force = flyer_profile.max_flap_power / speed

	var flap_force := minf(
			flyer_profile.max_flap_force,
			power_limited_force
	)
	var flap_acceleration := flap_force / flyer_profile.base_mass
	velocity += current_flap_direction.normalized() * flap_acceleration * delta

# LIFT, BANKING, TURNING
func apply_aerodynamics(delta: float) -> void:
	var air_velocity := velocity # later: velocity - wind_velocity
	var airspeed := air_velocity.length()

	if airspeed < 0.2:
		requested_aerodynamic_force = Vector3.ZERO
		aerodynamic_force_calculation_difference = 0.0
		debug_lift(0.0)
		debug_drag(0.0)
		return

	#Where we trying to go?
	var desired_velocity_direction := player_intended_direction()
	# How hard can we go there?
	var available_force := get_available_aerodynamic_force(airspeed)
	#How hard SHOULD we go there?
	var actual_force := get_requested_aerodynamic_force(
			desired_velocity_direction,
			available_force,
			air_velocity,
			delta
	)
	var chord_based_force := get_chord_based_requested_aerodynamic_force(
			desired_velocity_direction,
			available_force,
			air_velocity,
			delta
	)
	requested_aerodynamic_force = actual_force
	var normal_force_direction := get_normal_force_direction(air_velocity, desired_velocity_direction)
	aerodynamic_force_calculation_difference = (
			actual_force - chord_based_force
	).dot(normal_force_direction)
	# Apply both aerodynamic contributions, then report their resulting components.
	var wing_acceleration := apply_wing_force(actual_force, delta)
	var drag_acceleration := apply_induced_drag(
			actual_force.length(),
			airspeed,
			delta
	)
	var aerodynamic_acceleration := wing_acceleration + drag_acceleration
	debug_lift(aerodynamic_acceleration.dot(Vector3.UP))
	debug_drag(maxf(
			0.0,
			aerodynamic_acceleration.dot(-air_velocity.normalized())
	))




# How much force can we provide? 
func get_available_aerodynamic_force(airspeed: float) -> float:
	#Maximum force
	var airflow_force := (
		flyer_profile.aerodynamic_authority
		* airspeed
		* airspeed
	)
	#How much force can we actually provide without breaking our wings?
	var structural_force := (
		flyer_profile.structural_load_tolerance	* flyer_profile.base_mass
	)
	return minf(airflow_force, structural_force)

# What is the direction of the vector that will take us towards where we want to go?
func get_normal_force_direction(air_velocity: Vector3, player_intended_dir: Vector3) -> Vector3:
	var flight_direction := air_velocity.normalized()
	# Reminder - this takes the player intended direction and subtracts the projection of it along our existing velocity
	# That leaves only the perpendicular component. We're not trying to speed up or slow down. 
	var steering := (
			player_intended_dir
			- flight_direction
			* player_intended_dir.dot(flight_direction)
	)
	if steering.length_squared() < 0.0001:
		return Vector3.ZERO

	return steering.normalized()

# How much force do we actually want to use of our max possible? 
func get_requested_aerodynamic_force(
		desired_velocity_direction: Vector3,
		available_force: float,
		air_velocity: Vector3,
		delta: float
) -> Vector3:
	var desired_force_direction := get_normal_force_direction(air_velocity, desired_velocity_direction)
	if desired_force_direction == Vector3.ZERO:
		return Vector3.ZERO
	var flight_direction := air_velocity.normalized()
	var desired_direction := desired_velocity_direction.normalized()
	var turn_angle := acos(clampf(flight_direction.dot(desired_direction), -1.0, 1.0))
	# A perpendicular impulse of speed * tan(turn_angle) rotates a normalized velocity by turn_angle.
	# A single impulse cannot turn farther than 90 degrees, so larger turns use all available force.
	turn_angle = minf(turn_angle, PI * 0.5 - 0.001)
	var required_force_magnitude := (
			air_velocity.length() *
		tan(turn_angle) /
			delta *
			flyer_profile.base_mass
	)
	return desired_force_direction * minf(
			required_force_magnitude,
			available_force
	)


func get_chord_based_requested_aerodynamic_force(
		desired_velocity_direction: Vector3,
		available_force: float,
		air_velocity: Vector3,
		delta: float
) -> Vector3:
	var desired_force_direction := get_normal_force_direction(air_velocity, desired_velocity_direction)
	if desired_force_direction == Vector3.ZERO:
		return Vector3.ZERO

	var desired_velocity := desired_velocity_direction.normalized() * air_velocity.length()
	var required_velocity_change := desired_velocity - air_velocity
	var required_force_magnitude := (
			required_velocity_change.length() /
			delta *
			flyer_profile.base_mass
	)
	return desired_force_direction * minf(required_force_magnitude, available_force)

func apply_wing_force(force: Vector3, delta: float) -> Vector3:
	var before_speed := velocity.length()
	var acceleration := force / flyer_profile.base_mass
	velocity += acceleration * delta
	#Discreet correction 
	velocity = velocity.normalized() * before_speed
	return acceleration


func apply_induced_drag(wing_force: float,	airspeed: float, delta: float) -> Vector3:
	if airspeed < 0.01:
		return Vector3.ZERO

	var induced_drag_force := (
			INDUCED_DRAG_COEFFICIENT
			* wing_force
			* wing_force
			/ (airspeed * airspeed * flyer_profile.aerodynamic_authority)
	)

	return apply_drag_force(induced_drag_force, delta)

func apply_drag_force(force: float, delta: float) -> Vector3:
	if velocity.length_squared() < 0.0001:
		return Vector3.ZERO
	var drag_direction := -velocity.normalized()
	var acceleration := drag_direction * force / flyer_profile.base_mass
	velocity += acceleration * delta
	return acceleration


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
	speed_label.text = "Speed: %.1f m/s" % (velocity.length() * velocity.sign().z)


func debug_horizontal_speed(velocity: Vector3) -> void:
	horizontal_speed_label.text = "Horizontal Speed: %.1f m/s" % Vector2(
			velocity.x,
			velocity.z
	).length()


func debug_vertical_speed(velocity: Vector3) -> void:
	vertical_speed_label.text = "Vertical Speed: %.1f m/s" % velocity.y


func debug_total_energy() -> void:
	var kinetic_energy := 0.5 * flyer_profile.base_mass * velocity.length_squared()
	var potential_energy := flyer_profile.base_mass * gravity * global_position.y
	total_energy_label.text = "Total Energy: %.0f J" % (kinetic_energy + potential_energy)


func debug_requested_aerodynamic_force() -> void:
	requested_aerodynamic_force_label.text = "Requested Aero Force: %.0f N" % requested_aerodynamic_force.length()


func debug_aerodynamic_force_difference() -> void:
	aerodynamic_force_difference_label.text = "Normal Force Difference: %.1f N" % aerodynamic_force_calculation_difference
	
func debug_lift(lift_acceleration : float):
	lift_label.text = "Lift: %.0f%% gravity" % (
		lift_acceleration / gravity * 100.0
	)

func debug_drag(drag_acceleration : float):
	drag_label.text = "Drag: %.1f m/s²" % drag_acceleration
