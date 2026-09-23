class_name FlightController
extends RefCounted

class NegativeAoaClampResult:
	var force: Vector3
	var lift_up_direction: Vector3
	var was_clamped: bool

const GRAVITY := 9.8
const GENTLE_MIN_RESPONSE_TIME := 0.6 #For small turns, we take at least this long to avoid small sharp corrections needlessly costing drag 
const AGGRESSIVE_MIN_TURN_RESPONSE_TIME := 0.6 # 
const GENTLE_MAX_TURN_RATE:= PI/8.0 #For gentle turns, pi/4 = 45o/second 
const AGGRESSIVE_MAX_TURN_RATE := PI/1.5 # For aggressive turns   
const MIN_FLIGHT_SPEED := 0.2
const MIN_LIFT_COMMAND_FORCE := 15.0

## This takes the intent from the player controller and tries to translate it into flight directions.
## Note that with discrete physics it matters whether gravity is added to the current velocity before
## or after we run this control. It is constructed under the assumption gravity will be added after.
## If we added it before we could get rid of the support force section, but it would possibly
## complicate computing the turn speed. 
func get_control_command(
		intent: FlightIntent,
		flyer_state: FlyerState,
		flyer_profile: FlyerProfile
) -> FlightControlCommand:
	var command := FlightControlCommand.new()
	var desired_direction := _safe_normalized(intent.desired_direction, flyer_state.body_direction)
	command.target_body_direction = desired_direction



	# Control follows the flyer's path through the surrounding air. A moving air
	# mass can therefore carry the world-space trajectory without the controller
	# immediately cancelling that motion.
	var flight_velocity := flyer_state.air_relative_velocity
	var flight_speed := flight_velocity.length()

	if flight_speed < MIN_FLIGHT_SPEED :
		command.target_wing_surface_normal = _safe_normalized(
				flyer_state.wing_normal,
				Vector3.UP
		)
		command.info_intended_aoa = 0.0
		return command

	var flight_direction := flight_velocity / flight_speed
	if intent.wants_airbrake:
		# Present the entire wing surface to the airflow. FlightPhysics resolves
		# this into its maximum separated-flow pressure drag.
		command.target_wing_surface_normal = Vector3.UP.slerp(-1*flight_direction,0.9)
		command.info_intended_aoa = PI * 0.5
		command.info_requested_aerodynamic_force = -flight_direction * (
				flyer_profile.aerodynamic_authority
				* flight_speed * flight_speed
				* FlightPhysics.get_high_aoa_drag_coefficient(command.info_intended_aoa)
		)
		return command

	var steering_direction := _orthogonal_complement(desired_direction, flight_direction)

	# Wings can only oppose the component of gravity perpendicular to the
	# current flight path. Gravity along the path remains, naturally exchanging
	# potential energy and speed during climbs and dives.
	var gravity_force := Vector3.DOWN * flyer_profile.base_mass * GRAVITY
	# And we want to preemptively oppose it, so steering_force takes us where we want to go from here
	var support_force := -_orthogonal_component(gravity_force, flight_direction)

	#OPTION 1: This is a conceptually simple way of computing the steering force: What velocity is needed to change
	# our air velocity vector to our desired velocity in one second? Simple subtraction. 
	# Divide by turn response time to shrink/grow.
	# Differs only for very large turns (like 180o). We compute 'what would it take to just up and reverse direction'
	# but of course we can't do that, we have to curve a circle, and this code ends up being about 50% too small. 
#	var desired_velocity := desired_direction * flight_speed
#	var required_velocity_change := desired_velocity - flight_velocity
#	var steering_force := steering_direction * (
#		flyer_profile.base_mass
#		* required_velocity_change.length()
#		/ turn_response_time
#	)

	#Option 2: More accurate, but mathematically more complex.
	# Take omega as our desired turn rate in radians/second = turn_angle/turn_response_time  
	# This involves the flyer tracing out an arc each second with length equal to our speed. 
	# One second of that arc is r*omega long, so the radius of the arc is flight_speed/omega = r
	# The required normal centripetal acceleration to curve a circle with turn radius r is speed^2/r.
	# Since r= flight_speed/omega, the centripetal acceleration required is speed*omega.
	# So a normal steering acceleration of speed*turn_angle/response_time will curve an arc over 
	# turn_angle radians in response_time seconds.  Or use turn_rate directly if we max that. 
	var max_turn_rate := lerpf(
			GENTLE_MAX_TURN_RATE,
			AGGRESSIVE_MAX_TURN_RATE,
			intent.maneuver_aggression
	)
	var min_turn_response_time := lerpf(
			GENTLE_MIN_RESPONSE_TIME,
			AGGRESSIVE_MIN_TURN_RESPONSE_TIME,
			intent.maneuver_aggression
	)
	var turn_angle := acos(clampf(flight_direction.dot(desired_direction), -1.0, 1.0))
	# Pick the desired rate - aim for the min_response_time unless it exceeds the max turn rate.
	# Limited control schemes can soften or strengthen the physical steering request.
	var desired_turn_rate := minf(turn_angle / min_turn_response_time, max_turn_rate)
	desired_turn_rate *= intent.turn_response_multiplier
	# The centripetal acceleration described above.
	var steering_force := steering_direction * (
			flyer_profile.base_mass * flight_speed * desired_turn_rate
	)

	var requested_force := support_force + steering_force
	var aoa_clamp := clamp_negative_aoa(
			requested_force,
			intent.lift_up_direction,
			flight_direction,
			flyer_state.wing_normal
	)
	var controlled_force := aoa_clamp.force
	# Retain the force that prompted an unload so Player treats this as an active
	# wing command rather than applying its near-zero-force direction dead zone.
	command.info_requested_aerodynamic_force = (
			requested_force
			if aoa_clamp.was_clamped and controlled_force.length_squared() < (
					MIN_LIFT_COMMAND_FORCE * MIN_LIFT_COMMAND_FORCE
			)
			else controlled_force
	)

	var target_aoa_magnitude := choose_target_aoa(
			intent,
			controlled_force.length(),
			flight_velocity,
			flyer_profile
	)
	var has_directional_lift_request := controlled_force.length_squared() >= (
			MIN_LIFT_COMMAND_FORCE * MIN_LIFT_COMMAND_FORCE
	)
	var requested_lift_direction := aoa_clamp.lift_up_direction
	if has_directional_lift_request:
		requested_lift_direction = controlled_force.normalized()
	var target_wing_lift_side := requested_lift_direction
	command.info_intended_aoa = target_aoa_magnitude
	var gravity_fighting_speed := flyer_profile.get_gravity_fighting_speed(command.info_intended_aoa)
	#if gravity_fighting_speed > 0.0 and flight_speed < gravity_fighting_speed*0.9:
	#		command.info_intended_aoa *= flight_speed / (gravity_fighting_speed*0.9)

	if intent.force_wing_direction:
		# Forced-wing modes place the wings three quarters of the way from the
		# current flight path toward the requested path. Treat this as the wing
		# calculation's direction everywhere below; the body can still face the
		# player's full requested direction.
		# Test air veloicty instead
		flight_velocity = flyer_state.air_relative_velocity
		flight_direction = flight_velocity.normalized()
		var wing_direction := flight_direction.slerp(desired_direction, 0.75).normalized()
		command.target_wing_surface_normal = _safe_normalized(
				_orthogonal_complement(flight_velocity, wing_direction),
				flyer_state.wing_normal
		) * -1
		command.info_requested_aerodynamic_force = (
				command.target_wing_surface_normal
				* flight_speed * flight_speed * flyer_profile.aerodynamic_authority
		)
		command.info_intended_aoa = _get_surface_normal_aoa(
				command.target_wing_surface_normal,
				flight_direction
		)
	else:
		command.target_wing_surface_normal = _get_surface_normal(
				target_wing_lift_side,
				flight_direction,
				command.info_intended_aoa
		)
	return command


## Negative AoA reverses the lift response relative to the camera controls, so
## left and right would feel inverted. Camera-up defines the positive-lift side
## of the airflow-normal plane. Remove only force below that plane, preserving
## lateral force so banking remains available while the wings unload vertically.
func clamp_negative_aoa(
		requested_force: Vector3,
		camera_up_direction: Vector3,
		flight_direction: Vector3,
		current_wing_normal: Vector3
) -> NegativeAoaClampResult:
	var result := NegativeAoaClampResult.new()
	result.lift_up_direction = _orthogonal_component(
			camera_up_direction,
			flight_direction
	)
	if result.lift_up_direction.length_squared() < 0.0001:
		result.lift_up_direction = _orthogonal_component(
				Vector3.UP,
				flight_direction
		)
	if result.lift_up_direction.length_squared() < 0.0001:
		result.lift_up_direction = _orthogonal_component(
				current_wing_normal,
				flight_direction
		)
	result.lift_up_direction = _safe_normalized(
			result.lift_up_direction,
			current_wing_normal
	)

	var downward_force := requested_force.dot(result.lift_up_direction)
	result.was_clamped = downward_force < 0.0
	result.force = requested_force
	if result.was_clamped:
		result.force -= result.lift_up_direction * downward_force
	return result


## The angle of attack defines how much lift our wings give. At 0 (effective; ignoring how you get it, like chamfer or Bernoulli)
## wings provide zero lift. More AoA means more lift - up to a point. Find the AoA needed for our desired force, up to the max.
func choose_target_aoa(
		intent: FlightIntent,
		required_force: float,
		flight_velocity: Vector3,
		flyer_profile: FlyerProfile
) -> float:
	var flight_speed := flight_velocity.length()
	if flight_speed < MIN_FLIGHT_SPEED:
		return 0.0

	# ------------- Typical angle of attack range -----------------
	# Our base force factor - multiply by aoe lift factor to get actual lift. 
	var wing_force_base_factor := flyer_profile.aerodynamic_authority * flight_speed * flight_speed
	if wing_force_base_factor <= 0.001:
		return 0.0
	# What aoe lift multiple do we need?
	var necessary_lift_multiple := required_force / wing_force_base_factor
	var required_aoa := FlightPhysics.get_attached_aoa_for_lift_coefficient(necessary_lift_multiple)
	# If a reasonable ask just use the necessary AOA.
	if required_aoa <= FlightPhysics.NORMAL_TRIM_MAX_AOA:
		return required_aoa
	else:
		return FlightPhysics.NORMAL_TRIM_MAX_AOA 
	# ^^ This gives good glides and decent drag but doesn't allow air braaks and forces glides we dont want.
	# We end up around 9 m/s with drag of 1 ish.
		
	# ---------- 'Aggressive' AoA' --------------
	var max_allowed_aoa := inverse_lerp(
		FlightPhysics.NORMAL_TRIM_MAX_AOA,
		FlightPhysics.get_maximum_possible_lift_coefficient(),
		intent.maneuver_aggression
	)
	return minf(required_aoa, max_allowed_aoa)
	## ^^ This gives back original behavior. Oddly enough we just burn a little more velocity but the end bevarior is the same 
	var target_aoa := required_aoa

	return target_aoa

## Get the surface normal from a target lift direction and intended AOA into the flight direction (airflow). 
func _get_surface_normal(
		target_lift_direction: Vector3,
		flight_direction: Vector3,
		intended_aoa: float
) -> Vector3:
	return _safe_normalized(
			target_lift_direction * cos(intended_aoa)
			- flight_direction * sin(intended_aoa),
			target_lift_direction
	)

## The inverse of the above function, get the aoa (informational) from the surface normal.
func _get_surface_normal_aoa(surface_normal: Vector3, flight_direction: Vector3) -> float:
	if surface_normal.length_squared() < 0.0001 or flight_direction.length_squared() < 0.0001:
		return 0.0
	var along_flight := clampf(
			surface_normal.normalized().dot(flight_direction.normalized()),
			-1.0,
			1.0
	)
	return -atan2(along_flight, sqrt(maxf(0.0, 1.0 - along_flight * along_flight)))

## Also known as vector rejection. Remove all trace of reference_vector from direction,
## leaving a vector perpendicular to reference_vector (on a plane defined by direction and reference vector).
func _orthogonal_component(direction: Vector3, reference_vector: Vector3) -> Vector3:
	return direction - reference_vector * direction.dot(reference_vector)


func _orthogonal_complement(direction: Vector3, reference_vector: Vector3) -> Vector3:
	var perpendicular := _orthogonal_component(direction, reference_vector)
	return Vector3.ZERO if perpendicular.length_squared() < 0.0001 else perpendicular.normalized()

## Normalize the direction, or use fallback if the direction is essentially zero. 
func _safe_normalized(direction: Vector3, fallback: Vector3) -> Vector3:
	if direction.length_squared() >= 0.0001:
		return direction.normalized()
	return fallback.normalized() if fallback.length_squared() >= 0.0001 else Vector3.UP
