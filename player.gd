class_name Player
extends CharacterBody3D

@export var flyer_profile: FlyerProfile

const GROUND_MOVE_SPEED := 8.0
const JUMP_VELOCITY := 4.5
const FLAP_STAMINA_COST := 9.0
const EXTRA_FLAP_COST_MULTIPLIER := 1.5
const POWER_STROKE_PERCENTAGE := 0.2
const BODY_DIRECTION_RESPONSE := 6.0
const WING_DIRECTION_RESPONSE := 9.0
const AOA_RESPONSE_RATE := deg_to_rad(240.0)
const BODY_FULL_LEAN_SPEED := 20.0
const VISUAL_SHOULDER_OFFSET := 0.65
#const AOA_RESPONSE_RATE := deg_to_rad(360.0)

var ground_input_controller := GroundInputController.new()
var flight_input_controller := FlightInputController.new()
var flight_controller := FlightController.new()
var flight_physics := FlightPhysics.new()
var flyer_state := FlyerState.new()
var physics_result := FlightPhysicsResult.new()
var time_since_flap := 10.0
var stamina := 0.0
var flap_tween: Tween

@onready var camera_pitch: Node3D = $CameraPivot/CameraPitch
@onready var stamina_bar: ProgressBar = $CanvasLayer/ProgressBar
@onready var visual_root: Node3D = $VisualRoot
@onready var wings: Wings = $Wings
@onready var wing_force_arrow: DebugForceArrow = $WingForceArrow

@onready var speed_label: Label = $CanvasLayer/DebugContainer/SpeedLabel
@onready var horizontal_speed_label: Label = $CanvasLayer/DebugContainer/HorizontalSpeedLabel
@onready var vertical_speed_label: Label = $CanvasLayer/DebugContainer/VerticalSpeedLabel
@onready var total_energy_label: Label = $CanvasLayer/DebugContainer/TotalEnergyLabel
@onready var requested_aerodynamic_force_label: Label = $CanvasLayer/DebugContainer/RequestedAerodynamicForceLabel
@onready var lift_label: Label = $CanvasLayer/DebugContainer/LiftLabel
@onready var drag_label: Label = $CanvasLayer/DebugContainer/DragLabel
@onready var high_aoa_drag_label: Label = $CanvasLayer/DebugContainer/HighAoaDragLabel
@onready var aoa_label: Label = $CanvasLayer/DebugContainer.get_node_or_null("AoaLabel") as Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	flight_input_controller.steering_frame = camera_pitch
	flyer_state.body_direction = -global_basis.z
	flyer_state.wing_lift_direction = global_basis.y
	flyer_state.wing_normal = global_basis.y
	stamina = flyer_profile.max_stamina
	stamina_bar.max_value = flyer_profile.max_stamina
	stamina_bar.value = stamina

## I don't use this but I should probably do this in a debug class insttead of hand adding a bunch of lables later. Leaving as an example.
func ensure_aoa_label() -> void:
	if aoa_label:
		return
	aoa_label = Label.new()
	aoa_label.name = "AoaLabel"
	$CanvasLayer/DebugContainer.add_child(aoa_label)


func _physics_process(delta: float) -> void:
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
		apply_flight_movement(flight_input_controller.get_flight_intent(), delta)

	recover_stamina(delta)
	update_visual_orientation(delta)
	update_debug_readouts()
	move_and_slide()


func player_intended_direction() -> Vector3:
	return flight_input_controller.current_flight_intent.desired_direction


func apply_ground_movement(
		input_vector: Vector2,
		jump_requested: bool,
		delta: float
) -> void:
	flyer_state.requested_aerodynamic_force = Vector3.ZERO
	flyer_state.target_aoa = 0.0
	flyer_state.actual_aoa = move_toward(flyer_state.actual_aoa, 0.0, AOA_RESPONSE_RATE * delta)

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

	debug_lift(0.0)
	debug_drag(0.0)
	debug_high_aoa_drag(Vector3.ZERO)
	physics_result.wing_aerodynamic_force = Vector3.ZERO


func apply_flight_movement(intent: FlightIntent, delta: float) -> void:
	var control := flight_controller.get_control_command(
			intent,
			flyer_state,
			flyer_profile
	)
	flyer_state.requested_aerodynamic_force = control.requested_aerodynamic_force
	update_body_and_wings(control, delta)
	update_flap_plan(intent)

	update_flyer_state()
	flight_physics.integrate(flyer_state, flyer_profile, delta, physics_result)
	velocity = physics_result.velocity
	debug_lift((physics_result.lift_force / flyer_profile.base_mass).dot(Vector3.UP))
	debug_drag(physics_result.get_drag_acceleration(flyer_profile))
	debug_high_aoa_drag(physics_result.high_aoa_drag_vector)


func update_body_and_wings(control: FlightControlCommand, delta: float) -> void:
	flyer_state.body_direction = rotate_direction_toward(
			flyer_state.body_direction,
			control.target_body_direction,
			BODY_DIRECTION_RESPONSE * flyer_profile.control_rate * delta
	)
	flyer_state.wing_lift_direction = rotate_direction_toward(
			flyer_state.wing_lift_direction,
			control.target_wing_lift_direction,
			WING_DIRECTION_RESPONSE * flyer_profile.control_rate * delta
	)
	flyer_state.target_aoa = control.target_aoa
	flyer_state.actual_aoa = move_toward(
			flyer_state.actual_aoa,
			flyer_state.target_aoa,
			AOA_RESPONSE_RATE * flyer_profile.control_rate * delta
	)
	update_wing_surface_normal()


func update_wing_surface_normal() -> void:
	if flyer_state.airspeed < FlightPhysics.MIN_AIRSPEED:
		flyer_state.wing_normal = flyer_state.wing_lift_direction
		return

	var flight_direction := flyer_state.air_relative_velocity / flyer_state.airspeed
	var surface_normal := (
			flyer_state.wing_lift_direction * cos(flyer_state.actual_aoa)
			+ flight_direction * sin(flyer_state.actual_aoa)
	)
	if surface_normal.length_squared() < 0.0001:
		flyer_state.wing_normal = flyer_state.wing_lift_direction
		return
	flyer_state.wing_normal = surface_normal.normalized()


func update_flap_plan(intent: FlightIntent) -> void:
	flyer_state.active_flap_direction = Vector3.ZERO
	if intent.wants_upward_flap:
		flyer_state.current_flap_direction = Vector3.UP if intent.maneuver_aggression <= 0.0 else (
				Vector3.UP + intent.desired_direction
			).normalized()
	elif intent.wants_flap:
		flyer_state.current_flap_direction = intent.desired_direction

	if inside_power_stroke():
		flyer_state.active_flap_direction = flyer_state.current_flap_direction

	var regular_flap_due := time_since_flap >= flyer_profile.flap_cycle_duration
	var extra_flap_requested := (
			intent.requests_extra_flap
			and not inside_power_stroke()
			and not regular_flap_due
	)
	if not intent.wants_flap or not (regular_flap_due or extra_flap_requested):
		return

	var stamina_cost := FLAP_STAMINA_COST
	if extra_flap_requested:
		stamina_cost *= EXTRA_FLAP_COST_MULTIPLIER
	if stamina < stamina_cost:
		return

	stamina -= stamina_cost
	time_since_flap = 0.0
	flyer_state.active_flap_direction = flyer_state.current_flap_direction
	flap_visual()


func inside_power_stroke() -> bool:
	return time_since_flap < flyer_profile.flap_cycle_duration * POWER_STROKE_PERCENTAGE


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


func recover_stamina(delta: float) -> void:
	stamina = clampf(
			stamina + flyer_profile.stamina_recovery * delta,
			0.0,
			flyer_profile.max_stamina
	)
	stamina_bar.value = stamina


func update_visual_orientation(delta: float) -> void:
	var air_velocity := velocity - flyer_state.air_velocity_world
	if air_velocity.length_squared() >= 0.0001:
		var lean_fraction := smoothstep(0.0, BODY_FULL_LEAN_SPEED, air_velocity.length())
		var body_axis := Vector3.UP.slerp(air_velocity.normalized(), lean_fraction)
		var target_basis := _basis_with_local_up(body_axis)
		visual_root.basis = visual_root.basis.slerp(
				target_basis,
				clampf(8.0 * delta, 0.0, 1.0)
		)
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
	debug_speed(velocity)
	debug_horizontal_speed(velocity)
	debug_vertical_speed(velocity)
	debug_aoa()
	debug_total_energy()
	debug_requested_aerodynamic_force()


func debug_speed(current_velocity: Vector3) -> void:
	speed_label.text = "Speed: %.1f m/s" % (current_velocity.length() * current_velocity.sign().z)


func debug_horizontal_speed(current_velocity: Vector3) -> void:
	horizontal_speed_label.text = "Horizontal Speed: %.1f m/s" % Vector2(
			current_velocity.x,
			current_velocity.z
	).length()


func debug_vertical_speed(current_velocity: Vector3) -> void:
	vertical_speed_label.text = "Vertical Speed: %.1f m/s" % current_velocity.y


func debug_aoa() -> void:
	aoa_label.text = "AoA: %.1f°" % rad_to_deg(flyer_state.actual_aoa)


func debug_total_energy() -> void:
	var kinetic_energy := 0.5 * flyer_profile.base_mass * velocity.length_squared()
	var potential_energy := flyer_profile.base_mass * FlightPhysics.GRAVITY * global_position.y
	total_energy_label.text = "Total Energy: %.0f J" % (kinetic_energy + potential_energy)


func debug_requested_aerodynamic_force() -> void:
	requested_aerodynamic_force_label.text = "Requested Aero Force: %.0f N" % flyer_state.requested_aerodynamic_force.length()


func debug_lift(lift_acceleration: float) -> void:
	lift_label.text = "Lift: %.0f%% gravity" % (lift_acceleration / FlightPhysics.GRAVITY * 100.0)


func debug_drag(drag_acceleration: float) -> void:
	drag_label.text = "Drag: %.1f m/s²" % drag_acceleration


func debug_high_aoa_drag(drag_force: Vector3) -> void:
	var horizontal_force := Vector2(drag_force.x, drag_force.z).length()
	high_aoa_drag_label.text = "High AoA drag: H %.0f N, V %.0f N" % [
		horizontal_force,
		drag_force.y
	]


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
