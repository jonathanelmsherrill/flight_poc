class_name Player
extends CharacterBody3D

@export var flyer_profile: FlyerProfile

const GROUND_MOVE_SPEED := 8.0
const JUMP_VELOCITY := 4.5
const BODY_DIRECTION_RESPONSE := 6.0
const WING_DIRECTION_RESPONSE := 18.0
const VISUAL_SHOULDER_OFFSET := 0.65

var ground_input_controller := GroundInputController.new()
var flight_input_controllers: Array[FlightInputController] = [
	OpenLookFlightInputController.new(),
	OpenLookLimited1FlightInputController.new(),
	MechwarriorFlightInputController.new(),
	Mechwarrior2FlightInputController.new()
]
var flight_input_mode_index := 0
var flight_input_controller: FlightInputController
var flight_controller := FlightController.new()
var flight_physics := FlightPhysics.new()
var flyer_state := FlyerState.new()
var physics_result := FlightPhysicsResult.new()
var flight_debug: FlightDebug
var time_since_flap := 10.0
var stamina_energy_kilojoules := 0.0
var reported_energy_used_joules := 0.0
var flap_tween: Tween

@onready var camera_pitch: Node3D = $CameraPivot/CameraPitch
@onready var player_camera: PlayerCamera = $CameraPivot/CameraPitch/FreelookPivot/FreelookPitch/SpringArm3D/Camera3D
@onready var stamina_bar: ProgressBar = $CanvasLayer/ProgressBar
@onready var visual_root: Node3D = $VisualRoot
@onready var wings: Wings = $Wings
@onready var wing_force_arrow: DebugForceArrow = $WingForceArrow

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	flyer_state.body_direction = -global_basis.z
	flyer_state.wing_normal = global_basis.y
	activate_flight_input_mode(0)
	flight_physics.calculate_profile_performance(flyer_profile)
	stamina_energy_kilojoules = flyer_profile.stamina_capacity_kilojoules
	stamina_bar.max_value = flyer_profile.stamina_capacity_kilojoules
	stamina_bar.value = stamina_energy_kilojoules
	flight_debug = FlightDebug.new($CanvasLayer/DebugContainer)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("cycle_flight_input_mode"):
		activate_flight_input_mode((flight_input_mode_index + 1) % flight_input_controllers.size())

	reported_energy_used_joules = 0.0
	time_since_flap = minf(time_since_flap + delta, 10.0)
	update_flyer_state()

	if is_on_floor():
		apply_ground_movement(
				ground_input_controller.get_movement_input(),
				ground_input_controller.is_jump_requested(),
				delta
		)
	else:
		# Flight input controller divines player intent
		# The flight controller then tries to translate that into a physical state
		# And then the physics engine determines what happens.
		apply_flight_movement(flight_input_controller.get_flight_intent(velocity), delta)

	update_stamina_energy(delta)
	update_visual_orientation(delta)
	update_debug_readouts()
	move_and_slide()


func player_intended_direction() -> Vector3:
	return flight_input_controller.current_flight_intent.desired_direction


## Direction Capsule Girl visibly points in flight. Camera-relative control
## limits must use this same reference or they can appear to rotate behind her
## while the controller's abstract body direction changes ahead of her motion.
func visible_flight_direction() -> Vector3:
	var air_velocity := velocity - flyer_state.air_velocity_world
	if flyer_state.is_airborne and air_velocity.length_squared() >= 0.0001:
		return air_velocity.normalized()
	return flyer_state.body_direction.normalized()


func activate_flight_input_mode(mode_index: int) -> void:
	flight_input_mode_index = mode_index
	flight_input_controller = flight_input_controllers[flight_input_mode_index]
	flight_input_controller.activate(player_camera)


func apply_ground_movement(
		input_vector: Vector2,
		jump_requested: bool,
		delta: float
) -> void:
	flyer_state.info_requested_aerodynamic_force = Vector3.ZERO
	flyer_state.info_effective_aoa = 0.0

	var camera_forward := -camera_pitch.global_basis.z
	var camera_right := camera_pitch.global_basis.x
	camera_forward.y = 0.0
	camera_right.y = 0.0
	var ground_direction := (
			camera_right.normalized() * input_vector.x
			+ camera_forward.normalized() * -input_vector.y
		).normalized()
	velocity.x = ground_direction.x * GROUND_MOVE_SPEED
	velocity.z = ground_direction.z * GROUND_MOVE_SPEED

	if jump_requested:
		velocity.y = JUMP_VELOCITY
		time_since_flap = flyer_profile.flap_cycle_duration / 2.0

	physics_result.lift_force = Vector3.ZERO
	physics_result.induced_drag_force = 0.0
	physics_result.drag_force = Vector3.ZERO
	physics_result.parasite_drag_force = 0.0
	physics_result.high_aoa_drag_force = 0.0
	physics_result.high_aoa_drag_vector = Vector3.ZERO
	physics_result.wing_aerodynamic_force = Vector3.ZERO


func apply_flight_movement(intent: FlightIntent, delta: float) -> void:
	var control := flight_controller.get_control_command(
			intent,
			flyer_state,
			flyer_profile
	)
	flyer_state.info_requested_aerodynamic_force = control.info_requested_aerodynamic_force
	update_body_and_wings(control, delta)
	update_flap_plan(intent)

	update_flyer_state()
	flight_physics.integrate(flyer_state, flyer_profile, delta, physics_result)
	velocity = physics_result.velocity
	report_energy_used(physics_result.flap_energy_used_joules)


func update_body_and_wings(control: FlightControlCommand, delta: float) -> void:
	flyer_state.body_direction = rotate_direction_toward(
			flyer_state.body_direction,
			control.target_body_direction,
			BODY_DIRECTION_RESPONSE * flyer_profile.control_rate * delta
	)
	flyer_state.wing_normal = rotate_direction_toward(
			flyer_state.wing_normal,
			control.target_wing_surface_normal,
			WING_DIRECTION_RESPONSE * flyer_profile.control_rate * delta
	)


func update_flap_plan(intent: FlightIntent) -> void:
	flyer_state.active_flap_direction = Vector3.ZERO
	if flyer_state.airspeed > flyer_profile.max_airspeed_can_flap:
		return

	if intent.wants_upward_flap:
		flyer_state.current_flap_direction = Vector3.UP if intent.maneuver_aggression <= 0.0 else (
				Vector3.UP + intent.desired_direction
			).normalized()
	elif intent.wants_flap:
		flyer_state.current_flap_direction = intent.desired_direction

	if stamina_energy_kilojoules > 0.0 and inside_power_stroke():
		flyer_state.active_flap_direction = flyer_state.current_flap_direction

	var regular_flap_due := time_since_flap >= flyer_profile.flap_cycle_duration
	var extra_flap_requested := (
			intent.requests_extra_flap
			and not inside_power_stroke()
			and not regular_flap_due
	)
	if not intent.wants_flap or not (regular_flap_due or extra_flap_requested):
		return

	if stamina_energy_kilojoules <= 0.0:
		return

	time_since_flap = 0.0
	flyer_state.active_flap_direction = flyer_state.current_flap_direction
	flap_visual()


func inside_power_stroke() -> bool:
	return time_since_flap < flyer_profile.flap_cycle_duration * flyer_profile.power_stroke_fraction


func update_flyer_state() -> void:
	flyer_state.velocity = velocity
	flyer_state.air_relative_velocity = velocity - flyer_state.air_velocity_world
	flyer_state.airspeed = flyer_state.air_relative_velocity.length()
	flyer_state.is_airborne = not is_on_floor()


func rotate_direction_toward(current: Vector3, target: Vector3, weight: float) -> Vector3:
	if target.length_squared() < 0.0001:
		return current.normalized()
	if current.length_squared() < 0.0001:
		return target.normalized()
	return current.normalized().slerp(target.normalized(), clampf(weight, 0.0, 1.0))


## Activities report their actual energy use here. This keeps the stamina
## reserve independent of which system created the demand.
func report_energy_used(energy_used_joules: float) -> void:
	reported_energy_used_joules += maxf(energy_used_joules, 0.0)


func update_stamina_energy(delta: float) -> void:
	var sustainable_energy_joules := flyer_profile.sustainable_flap_power * delta
	stamina_energy_kilojoules = clampf(
			stamina_energy_kilojoules + (
				sustainable_energy_joules - reported_energy_used_joules
			) / 1000.0,
			0.0,
			flyer_profile.stamina_capacity_kilojoules
	)
	stamina_bar.value = stamina_energy_kilojoules


func update_visual_orientation(_delta: float) -> void:
	var air_velocity := velocity - flyer_state.air_velocity_world
	# The pill's local up axis follows its travel direction in flight. Walking
	# retains the upright pose so it reads as a standing character.
	if flyer_state.is_airborne and air_velocity.length_squared() >= 0.0001:
		visual_root.basis = _basis_with_local_up(air_velocity.normalized())
	elif not flyer_state.is_airborne:
		visual_root.basis = _basis_with_local_up(Vector3.UP)
	var shoulder_position := visual_root.global_position + (
			visual_root.global_basis.y * VISUAL_SHOULDER_OFFSET
	)
	wings.update_aerodynamic_pose(
			air_velocity,
		flyer_state.wing_normal,
		shoulder_position
	)
	wing_force_arrow.show_force(physics_result.wing_aerodynamic_force, shoulder_position)


func _basis_with_local_up(up_direction: Vector3) -> Basis:
	var reference_forward := Vector3.FORWARD
	if absf(reference_forward.dot(up_direction)) > 0.95:
		reference_forward = Vector3.RIGHT
	var right := reference_forward.cross(up_direction).normalized()
	var back := right.cross(up_direction).normalized()
	return Basis(right, up_direction, back)


func flap_visual() -> void:
	if flap_tween:
		flap_tween.kill()
	visual_root.scale = Vector3.ONE
	flap_tween = create_tween()
	flap_tween.tween_property(visual_root, "scale", Vector3(1.25, 0.85, 1.25), 0.08)
	flap_tween.tween_property(visual_root, "scale", Vector3.ONE, 0.18)


func update_debug_readouts() -> void:
	flight_debug.submit(
			"FlightInputModeLabel",
			"Flight input: %s" % flight_input_controller.get_display_name()
	)
	flight_debug.submit("SpeedLabel", "Speed: %.1f m/s" % (velocity.length() * velocity.sign().z))
	flight_debug.submit("HorizontalSpeedLabel", "Horizontal Speed: %.1f m/s" % Vector2(
			velocity.x,
			velocity.z
	).length())
	flight_debug.submit("VerticalSpeedLabel", "Vertical Speed: %.1f m/s" % velocity.y)
	flight_debug.submit("AoaLabel", "AoA: %.1f°" % rad_to_deg(flyer_state.info_effective_aoa))
	var kinetic_energy := 0.5 * flyer_profile.base_mass * velocity.length_squared()
	var potential_energy := flyer_profile.base_mass * FlightPhysics.GRAVITY * global_position.y
	flight_debug.submit("TotalEnergyLabel", "Total Energy: %.0f J" % (kinetic_energy + potential_energy))
	flight_debug.submit("RequestedAerodynamicForceLabel", "Requested Aero Force: %.0f N" % flyer_state.info_requested_aerodynamic_force.length())
	var lift_acceleration := (physics_result.lift_force / flyer_profile.base_mass).dot(Vector3.UP)
	flight_debug.submit("LiftLabel", "Lift: %.0f%% gravity" % (lift_acceleration / FlightPhysics.GRAVITY * 100.0))
	flight_debug.submit("DragLabel", "Drag: %.1f m/s²" % physics_result.get_drag_acceleration(flyer_profile))
	var high_aoa_horizontal_force := Vector2(
			physics_result.high_aoa_drag_vector.x,
			physics_result.high_aoa_drag_vector.z
	).length()
	flight_debug.submit("HighAoaDragLabel", "High AoA drag: H %.0f N, V %.0f N" % [
		high_aoa_horizontal_force,
		physics_result.high_aoa_drag_vector.y
	])
	flight_debug.submit("LiftVelocityDotLabel", "Lift force dot velocity: %.1f W" % physics_result.lift_force.dot(velocity))
	flight_debug.submit("DragVelocityDotLabel", "Drag force dot velocity: %.1f W" % physics_result.drag_force.dot(velocity))


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
