class_name Player
extends CharacterBody3D

@export var flyer_profile: FlyerProfile

const JUMP_VELOCITY := 4.5
## Horizontal speed at which the flight path, rather than facing, defines forward.
#const MIN_FLIGHT_HEADING_SPEED := 5.0
const BODY_DIRECTION_RESPONSE := 2.0
const WING_DIRECTION_RESPONSE := 3.0
const MIN_WING_DIRECTION_FORCE := 10.0
const VISUAL_SHOULDER_OFFSET := 0.65
const VISUAL_WING_BACK_OFFSET := 0.3

var ground_input_controller := GroundInputController.new()
var flight_input_controllers: Array[FlightInputController] = [
	OpenLookLimited1FlightInputController.new()
]
var flight_input_mode_index := 0
var flight_input_controller: FlightInputController
var flight_controller := FlightController.new()
var flight_physics := FlightPhysics.new()
var flyer_state := FlyerState.new()
var physics_result := FlightPhysicsResult.new()
var flight_debug: FlightDebug
var time_since_flap := 10.0
## Current sprint pace on the ground; 0 when not sprinting.
var ground_sprint_speed := 0.0
## Set when stamina runs out mid-sprint; cleared when sprint is released.
var sprint_needs_release := false
var stamina_energy_kilojoules := 0.0
var reported_energy_used_joules := 0.0
var active_wind_areas: Array[WindArea3D] = []
var debug_target_wing_normal := Vector3.UP
var wing_animation: WingAnimation

@onready var camera_pitch: Node3D = $CameraPivot/CameraPitch
@onready var player_camera: PlayerCamera = $CameraPivot/CameraPitch/FreelookPivot/FreelookPitch/SpringArm3D/Camera3D
@onready var stamina_bar: ProgressBar = $CanvasLayer/ProgressBar
@onready var debug_container: VBoxContainer = $CanvasLayer/DebugContainer
@onready var visual_root: Node3D = $VisualRoot
@onready var wings: Wings = $Wings
@onready var wing_force_arrow: DebugForceArrow = $WingForceArrow



func _ready() -> void:
	# Browsers only permit pointer lock during a user input callback. Requesting
	# it here can fail while leaving the requested mode looking captured, which
	# prevents the click handler below from retrying.
	if not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	flyer_state.body_direction = -global_basis.z
	flyer_state.body_up_direction = global_basis.y
	flyer_state.wing_normal = global_basis.y
	flyer_state.active_power_stroke_duration = FlightPhysics.get_power_stroke_duration(flyer_profile, 0.0)
	flyer_state.active_flap_recovery_duration = FlightPhysics.get_flap_recovery_duration(flyer_profile, 0.0)
	wing_animation = AiOpus3ptWingAnimation1.new()
	wings.set_animation(wing_animation)
	wing_animation.configure(visual_root, flyer_profile.fast_power_stroke_airspeed)
	activate_flight_input_mode(0)
	stamina_energy_kilojoules = flyer_profile.stamina_capacity_kilojoules
	stamina_bar.max_value = flyer_profile.stamina_capacity_kilojoules
	stamina_bar.value = stamina_energy_kilojoules
	flight_debug = FlightDebug.new(debug_container)




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
				ground_input_controller.is_sprint_requested(),
				delta
		)
	else:
		# Landing picks any sprint back up from the landing pace.
		ground_sprint_speed = 0.0
		# Flight input controller divines player intent
		# The flight controller then tries to translate that into a physical state
		# And then the physics engine determines what happens.
		apply_flight_movement(
				flight_input_controller.get_flight_intent(flyer_state.air_relative_velocity),
				delta
		)

	update_stamina_energy(delta)
	update_visual_orientation(delta)
	update_debug_readouts()
	move_and_slide()


func player_intended_direction() -> Vector3:
	return flight_input_controller.current_flight_intent.desired_direction


## Capsule Girl's visible forward direction follows her flight path once she
## has a real heading. Until then, such as just after a standing jump or while
## carrying a moving platform's drift, it stays where she was facing.
func visible_flight_direction() -> Vector3:
	if flyer_state.is_airborne: # and Vector2(velocity.x, velocity.z).length() >= MIN_FLIGHT_HEADING_SPEED:
		return velocity.normalized()
	return flyer_state.body_direction.normalized()


func activate_flight_input_mode(mode_index: int) -> void:
	flight_input_mode_index = mode_index
	flight_input_controller = flight_input_controllers[flight_input_mode_index]
	flight_input_controller.activate(player_camera)


func apply_ground_movement(
		input_vector: Vector2,
		jump_requested: bool,
		sprint_requested: bool,
		delta: float
) -> void:
	flyer_state.info_requested_aerodynamic_force = Vector3.ZERO
	flyer_state.info_effective_aoa = 0.0

	var camera_forward := -camera_pitch.global_basis.z
	var camera_right := camera_pitch.global_basis.x
	camera_forward.y = 0.0
	camera_right.y = 0.0
	# Forward always follows the mouse, whether or not we're moving.
	if camera_forward.length_squared() >= 0.0001:
		flyer_state.body_direction = camera_forward.normalized()
	flyer_state.body_up_direction = Vector3.UP
	# Level wings, so any sprint spread and the first moment of a takeoff start
	# from a sensible surface rather than whatever the last landing left.
	flyer_state.wing_normal = Vector3.UP
	var ground_direction := (
			camera_right.normalized() * input_vector.x
			+ camera_forward.normalized() * -input_vector.y
		).normalized()
	var ground_speed := update_ground_sprint(input_vector, sprint_requested, delta)
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z).move_toward(
			ground_direction * ground_speed,
			flyer_profile.walk_speed / flyer_profile.ground_direction_change_time * delta
	)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	if jump_requested:
		velocity.y = JUMP_VELOCITY

	physics_result.lift_force = Vector3.ZERO
	physics_result.induced_drag_force = 0.0
	physics_result.drag_force = Vector3.ZERO
	physics_result.parasite_drag_force = 0.0
	physics_result.high_aoa_drag_force = 0.0
	physics_result.high_aoa_drag_vector = Vector3.ZERO
	physics_result.wing_aerodynamic_force = Vector3.ZERO


## Returns the ground speed to move at. Sprinting only builds while moving
## forward, raising the wings as it goes. Running out of stamina ends it until
## sprint is pressed again, so an empty reserve can't flicker it on and off.
func update_ground_sprint(
		input_vector: Vector2,
		sprint_requested: bool,
		delta: float
) -> float:
	if not sprint_requested:
		sprint_needs_release = false
	var sprinting := sprint_requested and input_vector.y < 0.0 and not sprint_needs_release
	if sprinting and stamina_energy_kilojoules <= 0.0:
		sprinting = false
		sprint_needs_release = true
	if not sprinting:
		ground_sprint_speed = 0.0
		wing_animation.set_ground_spread(0.0)
		return flyer_profile.walk_speed

	if ground_sprint_speed <= 0.0:
		ground_sprint_speed = clampf(
				Vector2(velocity.x, velocity.z).length(),
				flyer_profile.sprint_start_speed,
				flyer_profile.sprint_max_speed
		)
	var sprint_speed_range := maxf(
			flyer_profile.sprint_max_speed - flyer_profile.sprint_start_speed,
			0.01
	)
	ground_sprint_speed = move_toward(
			ground_sprint_speed,
			flyer_profile.sprint_max_speed,
			sprint_speed_range / flyer_profile.sprint_build_time * delta
	)
	report_energy_used(flyer_profile.sprint_power * delta)
	wing_animation.set_ground_spread(
			(ground_sprint_speed - flyer_profile.sprint_start_speed) / sprint_speed_range
	)
	return ground_sprint_speed


func apply_flight_movement(intent: FlightIntent, delta: float) -> void:
	var control := flight_controller.get_control_command(
			intent,
			flyer_state,
			flyer_profile
	)
	flyer_state.info_requested_aerodynamic_force = control.info_requested_aerodynamic_force
	debug_target_wing_normal = control.target_wing_surface_normal
	update_body_and_wings(control, delta)
	update_flap_plan(intent)

	update_flyer_state()
	flight_physics.integrate(flyer_state, flyer_profile, delta, physics_result)
	velocity = physics_result.velocity
	report_energy_used(physics_result.flap_energy_used_joules)


func update_body_and_wings(control: FlightControlCommand, delta: float) -> void:
	var previous_body_direction := flyer_state.body_direction
	flyer_state.body_direction = rotate_direction_toward(
			previous_body_direction,
			control.target_body_direction,
			BODY_DIRECTION_RESPONSE * flyer_profile.control_rate * delta
	)
	flyer_state.body_up_direction = transport_body_up(
			previous_body_direction,
			flyer_state.body_direction,
			flyer_state.body_up_direction
	)
	flyer_state.body_up_direction =Vector3.UP
	# A near-zero requested force has no meaningful direction. Preserve the last
	# physical wing orientation instead of chasing normalization noise.
	if control.info_requested_aerodynamic_force.length_squared() < (
			MIN_WING_DIRECTION_FORCE * MIN_WING_DIRECTION_FORCE
	):
		return
	flyer_state.wing_normal = rotate_direction_toward(
			flyer_state.wing_normal,
			control.target_wing_surface_normal,
			WING_DIRECTION_RESPONSE * flyer_profile.control_rate * delta
	)


func update_flap_plan(intent: FlightIntent) -> void:
	flyer_state.active_flap_direction = Vector3.ZERO
	if flyer_state.airspeed > flyer_profile.max_airspeed_can_flap:
		return

	if stamina_energy_kilojoules > 0.0 and inside_power_stroke():
		flyer_state.active_flap_direction = flyer_state.current_flap_direction

	if not flap_recovery_complete():
		return

	var regular_flap_due := time_since_flap >= flyer_profile.flap_cycle_duration
	var extra_flap_requested := (
			(intent.requests_extra_flap or intent.wants_exertion)
			and not regular_flap_due
	)
	if not intent.wants_flap or not (regular_flap_due or extra_flap_requested):
		return

	var stroke_stamina_cost := FlightPhysics.get_power_stroke_stamina_cost(
			flyer_profile,
			flyer_state.airspeed,
			FlightPhysics.get_power_stroke_duration(flyer_profile, flyer_state.airspeed),
			intent.wants_exertion
	)
	if stamina_energy_kilojoules <= 0.0 or stamina_energy_kilojoules * 1000.0 < stroke_stamina_cost:
		return

	var thrust_direction := intent.flap_direction
	if intent.wants_upward_flap:
		thrust_direction = (
				_split_upward_flap_direction(intent.flap_direction)
				if intent.wants_directed_flap
				else Vector3.UP
		)
	_begin_power_stroke(thrust_direction, intent.wants_exertion)


## Tilts straight up toward the direction's horizontal heading by the profile's
## split angle, so the stroke's lean doesn't depend on camera pitch.
func _split_upward_flap_direction(direction: Vector3) -> Vector3:
	var heading := Vector3(direction.x, 0.0, direction.z)
	if heading.length_squared() < 0.0001:
		return Vector3.UP
	var tilt := deg_to_rad(flyer_profile.directed_upward_flap_angle)
	return Vector3.UP * cos(tilt) + heading.normalized() * sin(tilt)


func _begin_power_stroke(thrust_direction: Vector3, is_exertion: bool) -> void:
	if thrust_direction.length_squared() < 0.0001:
		return
	flyer_state.current_flap_direction = thrust_direction.normalized()
	flyer_state.active_power_stroke_is_exertion = is_exertion
	flyer_state.active_power_stroke_duration = FlightPhysics.get_power_stroke_duration(
			flyer_profile,
			flyer_state.airspeed
	)
	flyer_state.active_flap_recovery_duration = FlightPhysics.get_flap_recovery_duration(
			flyer_profile,
			flyer_state.airspeed
	)
	time_since_flap = 0.0
	flyer_state.active_flap_direction = flyer_state.current_flap_direction
	wing_animation.play_beat(WingBeatAnimationRequest.new(
			flyer_state.airspeed,
			flyer_state.current_flap_direction,
			flyer_state.active_power_stroke_duration,
			flyer_state.active_flap_recovery_duration,
			maxf(
					flyer_profile.flap_cycle_duration
					- flyer_state.active_power_stroke_duration
					- flyer_state.active_flap_recovery_duration,
					0.0
			)
	))


func inside_power_stroke() -> bool:
	return time_since_flap < flyer_state.active_power_stroke_duration


func flap_recovery_complete() -> bool:
	return time_since_flap >= (
			flyer_state.active_power_stroke_duration
			+ flyer_state.active_flap_recovery_duration
	)


func update_flyer_state() -> void:
	flyer_state.local_air_velocity = get_environment_wind()
	flyer_state.velocity = velocity
	flyer_state.air_relative_velocity = velocity - flyer_state.local_air_velocity
	flyer_state.airspeed = flyer_state.air_relative_velocity.length()
	flyer_state.is_airborne = not is_on_floor()


func rotate_direction_toward(current: Vector3, target: Vector3, weight: float) -> Vector3:
	if target.length_squared() < 0.0001:
		return current.normalized()
	if current.length_squared() < 0.0001:
		return target.normalized()
	return current.normalized().slerp(target.normalized(), clampf(weight, 0.0, 1.0))


func transport_body_up(
		previous_forward: Vector3,
		new_forward: Vector3,
		previous_up: Vector3
) -> Vector3:
	var old_forward := previous_forward.normalized()
	var forward := new_forward.normalized()
	var up := previous_up - old_forward * previous_up.dot(old_forward)
	if up.length_squared() < 0.0001:
		up = flyer_state.wing_normal - old_forward * flyer_state.wing_normal.dot(old_forward)
	up = up.normalized()

	var turn_axis := old_forward.cross(forward)
	if turn_axis.length_squared() >= 0.0001:
		var turn_angle := acos(clampf(old_forward.dot(forward), -1.0, 1.0))
		up = up.rotated(turn_axis.normalized(), turn_angle)

	up -= forward * up.dot(forward)
	if up.length_squared() < 0.0001:
		return previous_up.normalized()
	return up.normalized()


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
	# The pill's long local axis follows travel in flight while its local top
	# follows the persistent body-top direction. Walking remains world-upright.
	# Both are built from world directions, so they set the global basis and
	# stay correct however the Player node itself is placed in a scene.
	if flyer_state.is_airborne and velocity.length_squared() >= 0.0001:
		visual_root.global_basis = _basis_with_body_direction_and_top(
				velocity.normalized(),
				flyer_state.body_up_direction
		)
	elif not flyer_state.is_airborne:
		visual_root.global_basis = _basis_with_up_and_forward(Vector3.UP, flyer_state.body_direction)
	var shoulder_position := visual_root.global_position + (
			visual_root.global_basis.y * VISUAL_SHOULDER_OFFSET
	) + visual_root.global_basis.z * VISUAL_WING_BACK_OFFSET
	wings.update_aerodynamic_pose(
			velocity,
		flyer_state.wing_normal,
		shoulder_position,
		visual_root.global_basis.x,
		flyer_state.is_airborne
	)
	wing_force_arrow.show_force(physics_result.wing_aerodynamic_force, shoulder_position)


func _basis_with_body_direction_and_top(
		body_direction: Vector3,
		body_top_direction: Vector3
) -> Basis:
	var forward := body_direction.normalized()
	var top := body_top_direction - forward * body_top_direction.dot(forward)
	if top.length_squared() < 0.0001:
		top = flyer_state.wing_normal - forward * flyer_state.wing_normal.dot(forward)
	top = top.normalized()
	var right := forward.cross(top).normalized()
	top = right.cross(forward).normalized()
	return Basis(right, forward, top)


func _basis_with_up_and_forward(up_direction: Vector3, forward_direction: Vector3) -> Basis:
	var up := up_direction.normalized()
	var forward := forward_direction - up * forward_direction.dot(up)
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
		if absf(forward.dot(up)) > 0.95:
			forward = Vector3.RIGHT
		forward -= up * forward.dot(up)
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	var back := right.cross(up).normalized()
	return Basis(right, up, back)


func update_debug_readouts() -> void:
	flight_debug.submit("SpeedLabel", "Speed: %.1f m/s" % (velocity.length() * velocity.sign().z))
	flight_debug.submit("HorizontalSpeedLabel", "Horizontal Speed: %.1f m/s" % Vector2(
			velocity.x,
			velocity.z
	).length())
	flight_debug.submit("VerticalSpeedLabel", "Vertical Speed: %.1f m/s" % velocity.y)
	flight_debug.submit("WindVelocityLabel", "World wind: %s m/s" % flyer_state.local_air_velocity)
	flight_debug.submit("AoaLabel", "AoA: %.1f°" % rad_to_deg(flyer_state.info_effective_aoa))
	var kinetic_energy := 0.5 * flyer_profile.base_mass * velocity.length_squared()
	var potential_energy := flyer_profile.base_mass * FlightPhysics.GRAVITY * global_position.y
	flight_debug.submit("TotalEnergyLabel", "Total Energy: %.0f J" % (kinetic_energy + potential_energy))
	flight_debug.submit("RequestedAerodynamicForceLabel", "Requested Aero Force: %.0f N" % flyer_state.info_requested_aerodynamic_force.length())
	var target_wing_error := rad_to_deg(flyer_state.wing_normal.angle_to(debug_target_wing_normal))
	var target_airflow_incidence := 0.0
	if flyer_state.air_relative_velocity.length_squared() >= 0.0001:
		target_airflow_incidence = absf(rad_to_deg(
				debug_target_wing_normal.angle_to(flyer_state.air_relative_velocity)
		) - 90.0)
	flight_debug.submit(
			"AerodynamicForceDifferenceLabel",
			"Wing target error: %.1f deg | target AoA: %.1f deg" % [
				target_wing_error,
				target_airflow_incidence
			]
	)
	var lift_acceleration := (physics_result.lift_force / flyer_profile.base_mass).dot(Vector3.UP)
	flight_debug.submit("LiftLabel", "Lift: %.0f%% gravity" % (lift_acceleration / FlightPhysics.GRAVITY * 100.0))
	flight_debug.submit("DragLabel", "Drag: %.1f m/s²" % physics_result.get_drag_acceleration(flyer_profile))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("toggle_debug_panel"):
		debug_container.visible = not debug_container.visible
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Wind


func enter_wind_area(area: WindArea3D) -> void:
	if not active_wind_areas.has(area):
		active_wind_areas.append(area)

func exit_wind_area(area: WindArea3D) -> void:
	active_wind_areas.erase(area)

func get_environment_wind() -> Vector3:
	var wind := Vector3.ZERO

	for area in active_wind_areas:
		wind += area.get_wind_at(global_position)

	return wind
