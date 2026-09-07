class_name FlightController
extends RefCounted

const GRAVITY := 9.8
const GENTLE_MIN_RESPONSE_TIME := 0.6 #For small turns, we take at least this long to avoid small sharp corrections needlessly costing drag 
const AGGRESSIVE_MIN_TURN_RESPONSE_TIME := 0.6 # 
const GENTLE_MAX_TURN_RATE:= PI/4.0 #For gentle turns, pi/4 = 45o/second 
const AGGRESSIVE_MAX_TURN_RATE := PI/1.5 # For aggressive turns   
const MIN_AIRSPEED := 0.2

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

	var air_velocity := flyer_state.air_relative_velocity
	var airspeed := flyer_state.airspeed
	if airspeed < MIN_AIRSPEED:
		command.target_wing_lift_direction = _safe_normalized(
				flyer_state.wing_lift_direction,
				Vector3.UP
		)
		command.target_aoa = 0.0 #May need to not do this to avoid visual glitching when landing.
		return command

	var flight_direction := air_velocity / airspeed #aka air_velocity.normalize
	var steering_direction := _orthogonal_complement(desired_direction, flight_direction)

	# Wings can only oppose the component of gravity perpendicular to the
	# current air path. Gravity along the path remains, naturally exchanging
	# potential energy and airspeed during climbs and dives.
	var gravity_force := Vector3.DOWN * flyer_profile.base_mass * GRAVITY
	# And we want to preemptively oppose it, so steering_force takes us where we want to go from here
	var support_force := -_orthogonal_component(gravity_force, flight_direction)

	#OPTION 1: This is a conceptually simple way of computing the steering force: What velocity is needed to change
	# our air velocity vector to our desired velocity in one second? Simple subtraction. 
	# Divide by turn response time to shrink/grow.
	# Differs only for very large turns (like 180o). We compute 'what would it take to just up and reverse direction'
	# but of course we can't do that, we have to curve a circle, and this code ends up being about 50% too small. 
#	var desired_velocity := desired_direction * airspeed
#	var required_velocity_change := desired_velocity - air_velocity
#	var steering_force := steering_direction * (
#		flyer_profile.base_mass
#		* required_velocity_change.length()
#		/ turn_response_time
#	)

	#Option 2: More accurate, but mathematically more complex.
	# Take omega as our desired turn rate in radians/second = turn_angle/turn_response_time  
	# This involves the flyer tracing out an arc each second with length equal to our speed. 
	# One second of that arc is r*omega long, so the radius of the arc is airspeed/omega = r
	# The required normal centripetal acceleration to curve a circle with turn radius r is speed^2/r.
	# Since r= airspeed/omega, the centripetal acceleration required is speed*omega. 
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
	# Pick the desired rate - either the max rate or the 
	var desired_turn_rate := minf(turn_angle / min_turn_response_time, max_turn_rate)
	# To turn desired_turn_rate radians/second demands centripetal acceleration of v*turn_rate
	var steering_force := steering_direction * (
			flyer_profile.base_mass * airspeed * desired_turn_rate
	)

	var requested_force := support_force + steering_force
	command.requested_aerodynamic_force = requested_force
	command.target_wing_lift_direction = _safe_normalized(
			requested_force,
			flyer_state.wing_lift_direction
	)
	command.target_aoa = choose_target_aoa(
			intent,
			requested_force.length(),
			turn_angle,
			air_velocity,
			command.target_wing_lift_direction,
			flyer_profile
	)
	return command


func choose_target_aoa(
		intent: FlightIntent,
		required_force: float,
		turn_angle: float,
		air_velocity: Vector3,
		target_lift_direction: Vector3,
		flyer_profile: FlyerProfile
) -> float:
	var airspeed := air_velocity.length()
	if airspeed < MIN_AIRSPEED:
		return 0.0

	var dynamic_force := flyer_profile.aerodynamic_authority * airspeed * airspeed
	if dynamic_force <= 0.001:
		return 0.0

	var normal_trim_coefficient := FlightPhysics.get_lift_coefficient(
			FlightPhysics.NORMAL_TRIM_MAX_AOA
	)
	var requested_coefficient := required_force / dynamic_force
	var turn_airbrake_fraction := clampf(turn_angle / (PI * 0.5), 0.0, 1.0)
	var normal_trim_aoa := FlightPhysics.get_attached_aoa_for_lift_coefficient(
			minf(requested_coefficient, normal_trim_coefficient)
	)

	# Normal flight never silently spends the emergency lift margin. A stronger
	# request can extend from efficient trim through maximum useful lift.
	if requested_coefficient <= normal_trim_coefficient and turn_airbrake_fraction <= 0.0:
		return normal_trim_aoa

	if intent.maneuver_aggression <= 0.0:
		return FlightPhysics.NORMAL_TRIM_MAX_AOA

	var maximum_lift_coefficient := FlightPhysics.get_maximum_useful_lift_coefficient()
	var emergency_fraction := inverse_lerp(
			normal_trim_coefficient,
			maximum_lift_coefficient,
			requested_coefficient
	)
	var target_aoa := lerpf(
		FlightPhysics.NORMAL_TRIM_MAX_AOA,
		FlightPhysics.get_maximum_useful_lift_aoa(),
		clampf(emergency_fraction * intent.maneuver_aggression, 0.0, 1.0)
	)

	# A force shortfall or a large direction change can request post-stall AoA.
	# Do not turn that request into arbitrary braking: each candidate must still
	# produce direct wing force toward the desired path and velocity correction.
	var force_airbrake_fraction := 0.0
	if requested_coefficient > maximum_lift_coefficient:
		force_airbrake_fraction = inverse_lerp(
			maximum_lift_coefficient,
			maximum_lift_coefficient * 2.0,
			requested_coefficient
		)
	var airbrake_fraction := maxf(force_airbrake_fraction, turn_airbrake_fraction)
	if airbrake_fraction > 0.0:
		var requested_post_stall_aoa := lerpf(
			target_aoa,
			FlightPhysics.MAX_AOA,
			clampf(airbrake_fraction * intent.maneuver_aggression, 0.0, 1.0)
		)
		target_aoa = _get_highest_helpful_aoa(
			target_aoa,
			requested_post_stall_aoa,
			intent.desired_direction,
			air_velocity,
			target_lift_direction,
			flyer_profile
		)

	return target_aoa


func _get_highest_helpful_aoa(
		base_aoa: float,
		requested_aoa: float,
		desired_direction: Vector3,
		air_velocity: Vector3,
		target_lift_direction: Vector3,
		flyer_profile: FlyerProfile
) -> float:
	var airspeed := air_velocity.length()
	if airspeed < MIN_AIRSPEED or requested_aoa <= base_aoa:
		return base_aoa

	var desired_velocity_change := desired_direction.normalized() * airspeed - air_velocity
	if desired_velocity_change.length_squared() < 0.0001:
		return base_aoa

	var highest_helpful_aoa := base_aoa
	const CANDIDATE_COUNT := 12
	for index in range(1, CANDIDATE_COUNT + 1):
		var candidate_aoa := lerpf(
			base_aoa,
			requested_aoa,
			float(index) / CANDIDATE_COUNT
		)
		var candidate_force := _get_predicted_direct_wing_force(
			candidate_aoa,
			air_velocity,
			target_lift_direction,
			flyer_profile
		)
		if candidate_force.dot(desired_direction) <= 0.0:
			break
		if candidate_force.dot(desired_velocity_change) <= 0.0:
			break
		highest_helpful_aoa = candidate_aoa

	return highest_helpful_aoa


func _get_predicted_direct_wing_force(
		alpha: float,
		air_velocity: Vector3,
		target_lift_direction: Vector3,
		flyer_profile: FlyerProfile
) -> Vector3:
	var airspeed := air_velocity.length()
	if airspeed < MIN_AIRSPEED:
		return Vector3.ZERO

	var flight_direction := air_velocity / airspeed
	var surface_normal := _safe_normalized(
			target_lift_direction * cos(alpha) + flight_direction * sin(alpha),
			target_lift_direction
	)
	var lift_direction := _orthogonal_complement(surface_normal, flight_direction)
	var dynamic_force := flyer_profile.aerodynamic_authority * airspeed * airspeed
	var lift_force := lift_direction * dynamic_force * FlightPhysics.get_lift_coefficient(alpha)
	var normal_air_velocity := surface_normal * air_velocity.dot(surface_normal)
	var plate_drag_force := Vector3.ZERO
	if normal_air_velocity.length_squared() >= 0.0001:
		plate_drag_force = -normal_air_velocity.normalized() * (
			dynamic_force * FlightPhysics.get_high_aoa_drag_coefficient(alpha)
		)

	var direct_wing_force := lift_force + plate_drag_force
	var structural_force_limit := flyer_profile.structural_load_tolerance * flyer_profile.base_mass
	if direct_wing_force.length() > structural_force_limit:
		direct_wing_force = direct_wing_force.normalized() * structural_force_limit
	return direct_wing_force

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
