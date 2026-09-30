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
@export var aerodynamic_authority := 3.2

# Maximum aerodynamic acceleration the wings/body can physically tolerate.
# At high speed this becomes the limiting factor and forces tighter wing trim.
# How strong/sturdy is the wing? (A glider has large aerodynamic authority and weak load tolerance)
@export var structural_load_tolerance := 20.0

# Base drag from moving through the air.
# Parasite drag increases roughly with velocity squared.
# Lower values mean better streamlining and less speed loss in normal flight.
@export var parasite_drag_coefficient := 0.004 # 0.008

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
# Cycle-averaged acceleration is flap_force * power_stroke_duration
# / flap_cycle_duration / mass.
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
# Handy formula: max_speed= cube_root(power-stroke fraction * flap_power / air_drag_coefficient / mass)
# So 2500 max power at 45 kg and 0.008 drag ~= 11 m/s top speed, about 24 mph.
# At 4,500 W, the current values create an intentionally fantastical flyer.
# Average mechanical power that can be maintained indefinitely, in Watts.
# A power stroke concentrates a cycle's energy into its active window. At
# speed, force is limited by sustainable power * cycle duration
# / power-stroke duration / airspeed.
@export var sustainable_flap_power := 900.0

# Peak mechanical power an exertion (Shift) power stroke may draw, in Watts.
# Normal strokes are limited to the sustainable budget concentrated into the
# stroke; exertion strokes may use whichever limit is higher, paying the excess
# from stamina. Exertion also skips the cadence wait, so each new stroke begins
# as soon as the previous recovery ends.
@export var max_flap_power := 3500.0

# Space held with a direction (W/A/D, or S while exerting) splits the stroke
# between straight up and that direction's horizontal heading. This is the
# stroke's tilt from vertical, in degrees: 0 is pure up, 90 pure horizontal.
@export_range(0.0, 90.0, 1.0) var directed_upward_flap_angle := 45.0

# How long is one beat cycle. It controls cadence and the sustainable energy
# budget assigned to each normal wingbeat, in seconds.
@export var flap_cycle_duration := 1

# At low airspeed, long strokes let the wings grab a large mass of air. Fast
# airflow requires a shorter stroke and shallower visual angle of attack.
@export_range(0.01, 100.0, 0.1) var fast_power_stroke_airspeed := 26.0
@export_range(0.01, 2.0, 0.01) var low_airspeed_power_stroke_duration := 0.55
@export_range(0.01, 2.0, 0.01) var high_airspeed_power_stroke_duration := 0.15

# Force is inactive while the animator folds and returns the wings to their
# ready position. No new power stroke can begin during this interval.
@export_range(0.01, 2.0, 0.01) var low_airspeed_flap_recovery_duration := 0.35
@export_range(0.01, 2.0, 0.01) var high_airspeed_flap_recovery_duration := 0.18


@export_group("Ground Movement")

# Normal walking/running speed, in metres per second.
@export var walk_speed := 4.0

# Seconds to reach walking speed from a standstill, or to stop from it. Bigger
# velocity changes take proportionally longer: a full reversal takes twice this,
# and slowing from a sprint takes sprint speed / walk speed times this.
@export_range(0.01, 2.0, 0.01) var ground_direction_change_time := 0.1

# Sprinting (Shift + forward) begins at this speed and builds toward
# sprint_max_speed over sprint_build_time, raising the wings as it goes.
@export var sprint_start_speed := 4.0
@export var sprint_max_speed := 12.0
@export_range(0.01, 10.0, 0.01) var sprint_build_time := 2.5

# Power spent while sprinting, in Watts. Stamina only drains by the amount this
# exceeds sustainable_flap_power, so the default costs roughly 300 W.
@export var sprint_power := 1200.0

@export_group("Stamina")

# Energy reserve above sustainable output. Higher values allow more extra
# wingbeats and other strenuous actions before exhaustion, in kilojoules.
@export var stamina_capacity_kilojoules := 10.0

# Recovery is calculated from the difference between sustainable power and all
# reported energy use, so no separate regeneration rate is needed.
