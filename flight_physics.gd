class_name FlightPhysics
extends RefCounted

## Aerodynamic coefficient tuning. Aerodynamic authority already includes the
## wing-area and air-density abstraction.
const GRAVITY := 9.8 #m/s^2 
const LIFT_SLOPE := 5.0 # This is the ratio of lift to angle of attack. 1 radian = ~ 60 degrees, so if the stall onset is ~22 degrees, our max lift is 1.33 what it was before.
#const FULL_AUTHORITY_AOA = 1/LIFT_SLOPE # Radians. This is like 14 degrees if lift slope is 4, meaning our air authority is a bit lower than we're used to. 
const NORMAL_TRIM_MAX_AOA := deg_to_rad(6.0)
const STALL_ONSET_AOA := deg_to_rad(15.0)  #This would be more like 9-14 degrees in reality I think. 
const FULL_SEPARATION_AOA := deg_to_rad(25.0) # More like 15-18 degrees
const MAX_AOA := deg_to_rad(90.0)
const PLATE_LIFT_COEFFICIENT := 1.6
const PLATE_DRAG_COEFFICIENT := 1.5
const INDUCED_DRAG_COEFFICIENT := 0.14
const MIN_AIRSPEED := 0.2
const PERFORMANCE_AOA_STEP := 0.25


func calculate_profile_performance(flyer_profile: FlyerProfile) -> void:
	flyer_profile.gravity_fighting_speed_by_aoa.clear()
	var aoa := PERFORMANCE_AOA_STEP
	while aoa < FULL_SEPARATION_AOA:
		flyer_profile.gravity_fighting_speed_by_aoa[aoa] = _get_gravity_fighting_speed(aoa, flyer_profile)
		aoa += PERFORMANCE_AOA_STEP
	flyer_profile.gravity_fighting_speed_by_aoa[FULL_SEPARATION_AOA] = _get_gravity_fighting_speed(
			FULL_SEPARATION_AOA,
			flyer_profile
	)

	var best_lift_to_drag := 0.0
	flyer_profile.optimal_lift_to_drag_aoa = 0.0
	for sample_index in range(1, 101):
		var sample_aoa := FULL_SEPARATION_AOA * float(sample_index) / 100.0
		var minimum_speed := _get_gravity_fighting_speed(sample_aoa, flyer_profile)
		var lift_force := flyer_profile.base_mass * GRAVITY
		var induced_drag := get_induced_drag_force(
				lift_force,
				minimum_speed,
				flyer_profile.aerodynamic_authority
		)
		var parasite_drag := flyer_profile.parasite_drag_coefficient * minimum_speed * minimum_speed
		var lift_to_drag := lift_force / maxf(induced_drag + parasite_drag, 0.0001)
		if lift_to_drag > best_lift_to_drag:
			best_lift_to_drag = lift_to_drag
			flyer_profile.optimal_lift_to_drag_aoa = sample_aoa


func _get_gravity_fighting_speed(aoa: float, flyer_profile: FlyerProfile) -> float:
	var lift_coefficient := get_lift_coefficient(aoa)
	if lift_coefficient <= 0.0001 or flyer_profile.aerodynamic_authority <= 0.0001:
		return INF
	return sqrt(flyer_profile.base_mass * GRAVITY / (
			flyer_profile.aerodynamic_authority * lift_coefficient
	))


func integrate(
		flyer_state: FlyerState,
		flyer_profile: FlyerProfile,
		delta: float,
		result: FlightPhysicsResult
) -> FlightPhysicsResult:
	result.velocity = flyer_state.velocity
	result.lift_force = Vector3.ZERO
	result.induced_drag_force = 0.0
	result.drag_force = Vector3.ZERO
	result.parasite_drag_force = 0.0
	result.high_aoa_drag_force = 0.0
	result.high_aoa_drag_vector = Vector3.ZERO
	result.wing_aerodynamic_force = Vector3.ZERO
	flyer_state.info_effective_aoa = 0.0
	# Every aerodynamic calculation in this tick uses this one snapshot. The
	# controller built the requested surface normal from the same air velocity.
	var air_velocity := flyer_state.velocity - flyer_state.air_velocity_world
	var airspeed := air_velocity.length()
	var updated_velocity := flyer_state.velocity

	if airspeed >= MIN_AIRSPEED:
		var effective_aoa := _get_effective_aoa(flyer_state.wing_normal, air_velocity)
		flyer_state.info_effective_aoa = effective_aoa
		var lift_direction := _get_lift_direction(flyer_state.wing_normal, air_velocity)
		var dynamic_force := flyer_profile.aerodynamic_authority * airspeed * airspeed
		var lift_force_magnitude := dynamic_force * get_lift_coefficient(effective_aoa)
		var high_aoa_drag_force := dynamic_force * get_high_aoa_drag_coefficient(effective_aoa)
		var lift_force := lift_direction * lift_force_magnitude
		var high_aoa_drag_vector := _get_surface_pressure_drag_force(
				flyer_state.wing_normal,
				air_velocity,
				high_aoa_drag_force
		)
		var direct_wing_force := (lift_force + high_aoa_drag_vector).length()
		var structural_force_limit := flyer_profile.structural_load_tolerance * flyer_profile.base_mass
		if direct_wing_force > structural_force_limit and direct_wing_force > 0.0:
			var structural_scale := structural_force_limit / direct_wing_force
			lift_force *= structural_scale
			high_aoa_drag_vector *= structural_scale
			lift_force_magnitude = lift_force.length()
			high_aoa_drag_force = high_aoa_drag_vector.length()
		direct_wing_force = (lift_force + high_aoa_drag_vector).length()

		result.lift_force = lift_force
		updated_velocity = _apply_energy_neutral_lift(
			updated_velocity,
			flyer_state.air_velocity_world,
			result.lift_force,
			airspeed,
			flyer_profile.base_mass,
			delta
		)
		result.induced_drag_force = get_induced_drag_force(
			direct_wing_force,
			airspeed,
			flyer_profile.aerodynamic_authority
		)
		result.parasite_drag_force = flyer_profile.parasite_drag_coefficient * airspeed * airspeed
		result.high_aoa_drag_force = high_aoa_drag_force
		result.high_aoa_drag_vector = high_aoa_drag_vector
		var induced_drag_vector := _get_airflow_drag_force(
				air_velocity,
				result.induced_drag_force
		)
		var parasite_drag_vector := _get_airflow_drag_force(
				air_velocity,
				result.parasite_drag_force
		)
		result.drag_force = induced_drag_vector + parasite_drag_vector + high_aoa_drag_vector
		result.wing_aerodynamic_force = (
				result.lift_force
				+ high_aoa_drag_vector
				+ induced_drag_vector
		)
		updated_velocity = _apply_drag(
				updated_velocity,
				air_velocity,
				result.induced_drag_force + result.parasite_drag_force,
				flyer_profile.base_mass,
				delta
		)
		updated_velocity = _apply_force(
				updated_velocity,
				high_aoa_drag_vector,
				flyer_profile.base_mass,
				delta
		)

	# Apply gravity after aerodynamic forces so the next tick's controller and
	# this tick's aerodynamic snapshot use the same flight direction.
	updated_velocity.y -= GRAVITY * delta
	result.velocity = _apply_flap_force(
		updated_velocity,
		airspeed,
		flyer_state.active_flap_direction,
		flyer_profile,
		delta
	)
	return result


static func get_lift_coefficient(alpha: float) -> float:
	var absolute_alpha := clampf(absf(alpha), 0.0, MAX_AOA)
	var attached_flow_lift := LIFT_SLOPE * absolute_alpha
	var plate_lift := PLATE_LIFT_COEFFICIENT * sin(absolute_alpha) * cos(absolute_alpha)
	var separation := smoothstep(STALL_ONSET_AOA, FULL_SEPARATION_AOA, absolute_alpha) 
	return lerpf(attached_flow_lift, plate_lift, separation)


static func get_high_aoa_drag_coefficient(alpha: float) -> float:
	var absolute_alpha := clampf(absf(alpha), 0.0, MAX_AOA)
	var plate_drag := PLATE_DRAG_COEFFICIENT * sin(absolute_alpha) * sin(absolute_alpha)
	var separation := smoothstep(STALL_ONSET_AOA, FULL_SEPARATION_AOA, absolute_alpha)
	return plate_drag * separation


static func get_maximum_lift_aoa() -> float:
	return deg_to_rad(30.0)

## What's the maxumum lift we can get from Aoa? (A flat wing has 0 lift, a plate has 0 lift, there is a max in between)
static func get_maximum_possible_lift_coefficient() -> float:
	return get_lift_coefficient(get_maximum_lift_aoa())


static func get_attached_aoa_for_lift_coefficient(lift_coefficient: float) -> float:
	return clampf(lift_coefficient / LIFT_SLOPE, 0.0, STALL_ONSET_AOA)


## The wing normal is the physical state. Its component along the airflow is
## the sine of the wing's effective angle of attack.
func _get_effective_aoa(wing_normal: Vector3, air_velocity: Vector3) -> float:
	if wing_normal.length_squared() < 0.0001 or air_velocity.length_squared() < 0.0001:
		return 0.0
	var airflow_direction := air_velocity.normalized()
	var surface_normal := wing_normal.normalized()
	var along_airflow := clampf(surface_normal.dot(airflow_direction), -1.0, 1.0)
	return atan2(along_airflow, sqrt(maxf(0.0, 1.0 - along_airflow * along_airflow)))


static func get_induced_drag_force(
		lift_force: float,
		airspeed: float,
		aerodynamic_authority: float
) -> float:
	if airspeed < 0.01 or aerodynamic_authority <= 0.001:
		return 0.0
	return INDUCED_DRAG_COEFFICIENT * lift_force * lift_force / (
			airspeed * airspeed * aerodynamic_authority
	)


func _get_lift_direction(wing_normal: Vector3, air_velocity: Vector3) -> Vector3:
	var airflow_direction := air_velocity.normalized()
	var perpendicular_normal := wing_normal - airflow_direction * wing_normal.dot(airflow_direction)
	if perpendicular_normal.length_squared() < 0.0001:
		return Vector3.ZERO
	return perpendicular_normal.normalized()


func _get_surface_pressure_drag_force(
		wing_normal: Vector3,
		air_velocity: Vector3,
		drag_force: float
) -> Vector3:
	if drag_force <= 0.0:
		return Vector3.ZERO
	var normal_air_velocity := wing_normal * air_velocity.dot(wing_normal)
	if normal_air_velocity.length_squared() < 0.0001:
		return Vector3.ZERO
	return -normal_air_velocity.normalized() * drag_force

## We apply our lift force, then make sure the total energy is the same.
func _apply_energy_neutral_lift(
		velocity: Vector3,
		air_velocity_world: Vector3,
		lift_force: Vector3,
		airspeed: float,
		mass: float,
		delta: float
) -> Vector3:
	if lift_force.length_squared() < 0.0001:
		return velocity
	var updated_velocity := velocity + lift_force / mass * delta
	var air_velocity_after_lift := updated_velocity - air_velocity_world
	if air_velocity_after_lift.length_squared() < 0.0001:
		return updated_velocity
	return air_velocity_world + air_velocity_after_lift.normalized() * airspeed


func _apply_drag(
		velocity: Vector3,
		air_velocity: Vector3,
		drag_force: float,
		mass: float,
		delta: float
) -> Vector3:
	if drag_force <= 0.0 or air_velocity.length_squared() < 0.0001:
		return velocity
	return velocity - air_velocity.normalized() * drag_force / mass * delta


func _get_airflow_drag_force(
		air_velocity: Vector3,
		drag_force: float
) -> Vector3:
	if drag_force <= 0.0 or air_velocity.length_squared() < 0.0001:
		return Vector3.ZERO
	return -air_velocity.normalized() * drag_force


func _apply_force(
		velocity: Vector3,
		force: Vector3,
		mass: float,
		delta: float
) -> Vector3:
	return velocity + force / mass * delta


func _apply_flap_force(
		velocity: Vector3,
		airspeed: float,
		flap_direction: Vector3,
		flyer_profile: FlyerProfile,
		delta: float
) -> Vector3:
	if flap_direction.length_squared() < 0.0001:
		return velocity
	var power_limited_force := flyer_profile.max_flap_power / maxf(airspeed, 0.01)
	var flap_force := minf(flyer_profile.max_flap_force, power_limited_force)
	return velocity + flap_direction.normalized() * flap_force / flyer_profile.base_mass * delta
