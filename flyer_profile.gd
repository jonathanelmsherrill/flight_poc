class_name FlyerProfile
extends Resource


@export_group("Mass")
#This may never change, but since we're working in forces now. in kg. Impulse / mass = delta-v. 
@export var base_mass := 45

@export_group("Aerodynamics")

# How much aerodynamic force fully deployed wings can generate from airflow.
# Higher values give stronger lift/turning authority at a given airspeed.
# Can be thought of crudely as the size of the wing - larger wings move more air. 
# But in this game wings can be better or worse despite the size. 
# Normally lift = 0.5*density*v^2*wing-area*Lift coefficient 
# where lift_coefficient normally depends on airfoil shape, angle of attack, camber, and flow behavior.
# In our abstraction, wing area and the inherent properties of the wing, plus game magic,  
# are rolled into 'aerodynamic_authority'. Velocity is situational, and angle of attack/orientation is 
# accounted for where we determine how that authority is applied. 
# While other figures attempt to be more-or-less realistic, this is the most unrealistic element of a human shaped flier.
# Right now this also controls induced drag, which is partially accurate in that
# both computations depend on wing area, but drag does depend on aspect ratio (wing length vs width; a 
# long thin wing generates less induced drag than a broad one) and that is presumed constant and not modeled. 
# Realistic values (ish) would be 0.7 to 2 (unit is kg/m if you're interested). 
# That is, a real person with physically plausible wings might be around 1, which is a very satisfying number for base reality. 
# Max perpendicular FORCE = authority*velocity squared, so if 1, 5m/s = 25kgm/s^2
# Which is woefully incapable of keeping a 45 kg human in the air.   
# Thus our fantasy winged flying human needs to be closer to 5.  
# Doubling it halves induced drag and doubles lift. 12 lets you turn on a dime.
@export var aerodynamic_authority := 2.8

# Maximum aerodynamic acceleration the wings/body can physically tolerate.
# At high speed this becomes the limiting factor and forces tighter wing trim.
# How strong/sturdy is the wing? (A glider has large aerodynamic authority and weak load tolerance)
@export var structural_load_tolerance := 20.0

# Base drag from moving through the air.
# Parasite drag increases roughly with velocity squared.
# Lower values mean better streamlining and less speed loss in normal flight.
@export var parasite_drag_coefficient := 0.004 # 0.008

## Runtime performance data calculated by FlightPhysics when the player starts.
var gravity_fighting_speed_by_aoa: Dictionary[float, float] = {}
var optimal_lift_to_drag_aoa := 0.0


func get_gravity_fighting_speed(aoa: float) -> float:
	if gravity_fighting_speed_by_aoa.is_empty():
		return 0.0
	var lower_aoa := gravity_fighting_speed_by_aoa.keys().min() as float
	var upper_aoa := gravity_fighting_speed_by_aoa.keys().max() as float
	if aoa < lower_aoa:
		return 0.0
	var clamped_aoa := clampf(aoa, lower_aoa, upper_aoa)
	var lower_speed := gravity_fighting_speed_by_aoa[lower_aoa]
	var upper_speed := gravity_fighting_speed_by_aoa[upper_aoa]
	for sample_aoa in gravity_fighting_speed_by_aoa:
		if sample_aoa <= clamped_aoa and sample_aoa >= lower_aoa:
			lower_aoa = sample_aoa
			lower_speed = gravity_fighting_speed_by_aoa[sample_aoa]
		if sample_aoa >= clamped_aoa and sample_aoa <= upper_aoa:
			upper_aoa = sample_aoa
			upper_speed = gravity_fighting_speed_by_aoa[sample_aoa]
	if is_equal_approx(lower_aoa, upper_aoa):
		return lower_speed
	return lerpf(lower_speed, upper_speed, inverse_lerp(lower_aoa, upper_aoa, clamped_aoa))

# How quickly the flyer can reorient their body/wings toward the desired maneuver.
# Higher values mean more responsive steering and faster changes in wing force direction.
# E.g, "I fell off a cliff, how long does it take to reorient to control my flight again?"
# May never use this, but is an interesting thought. Might also be useful for things like 
# "What's my minimum angle of attack at high speed" - newbies might not be able to do that perfectly.
# Maybe a flight skill thing? Anyway doesn't do anything yet. 
@export var control_rate := 1


@export_group("Flapping")

# Maximum force the flyer can generate through an active wingbeat.
# Dominates at low airspeed, where available power is not yet limiting.
# Measured in Newtons. 
# At low speed, impulse per flap = flap_force * power-stroke duration.
# Cycle-averaged acceleration is flap_force * power_stroke_fraction / mass.
# So assuming 45 kg mass 500 flap force = 2.22 m/s^2.    
@export var max_flap_force := 350.0

# Active flapping is disabled above this airspeed, in metres per second.
# The limit protects the flyer from attempting power strokes at unsafe speed.
@export var max_airspeed_can_flap := 45.0

# Sustainable mechanical power the flyer can deliver through active wingbeats.
# At higher relevant airflow/output speeds, available flap force is limited
# approximately by force <= stroke power / velocity.
# Measured in Watts.
# At high speed, impulse per flap = stroke power / velocity * power stroke duration.
# The force becomes limited when sustainable power / stroke fraction / max force
# is less than the airspeed.
# This also starts to highlight some of the game magic that enables human flight. 500 newtons of flap force?
# Bah, that's a deadlift! No problem! Maintaining that force at speed? Now our brave hero is an absurd 
# 2.5 kilowatt generator. Actually, typical muscle efficiency is around 25%, so she's also a 7.5 KW space heater. 
# For comparison, a real human athlete can manage about 4-500 watts for an hour.  2500 is around the maximum power 
# a top human athelete might produce over a few short seconds. 
# Fun fact: If left to black body emissions, our heroine would have a body temperature of around 500F.
# Those giant wings must also be fantastic heat exchangers. 
# Handy formula: max_speed= cube_root(power_stroke_percentage * flap_power / air_drag_coefficient / mass)	
# So 2500 max power at 45 kg and 0.008 drag ~= 11 m/s top speed, about 24 mph.
# At 4,500 W, the current values create an intentionally fantastical flyer.
# Average mechanical power that can be maintained indefinitely, in Watts.
# A power stroke concentrates a cycle's energy into its active window. At
# speed, force is limited by sustainable power / stroke fraction / airspeed.
@export var sustainable_flap_power := 900.0

# How long is one beat cycle. It controls cadence and the sustainable energy
# budget assigned to each normal wingbeat, in seconds.
@export var flap_cycle_duration := 1
# Portion of each cycle that produces force. A shorter stroke has a higher
# instantaneous limit because the same cycle energy is concentrated in it.
@export_range(0.01, 1.0) var power_stroke_fraction := 0.2

@export_group("Stamina")

# Energy reserve above sustainable output. Higher values allow more extra
# wingbeats and other strenuous actions before exhaustion, in kilojoules.
@export var stamina_capacity_kilojoules := 10.0

# Recovery is calculated from the difference between sustainable power and all
# reported energy use, so no separate regeneration rate is needed.
