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
@export var aerodynamic_authority := 5

# Maximum aerodynamic acceleration the wings/body can physically tolerate.
# At high speed this becomes the limiting factor and forces tighter wing trim.
# How strong/sturdy is the wing? (A glider has large aerodynamic authority and weak load tolerance)
@export var structural_load_tolerance := 20.0

# Base drag from moving through the air.
# Parasite drag increases roughly with velocity squared.
# Lower values mean better streamlining and less speed loss in normal flight.
@export var parasite_drag_coefficient := 0.008

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
# At low speed, impulse per flap = flap_force * flap_cycle_duration * power_stroke_percentage
# (cycle-averaged) Acceleration is flap_force * power_stroke_percentage / mass
# So assuming 45 kg mass 500 flap force = 2.22 m/s^2.    
@export var max_flap_force := 500.0

# Maximum mechanical power the flyer can deliver through active wingbeats.
# At higher relevant airflow/output speeds, available flap force is limited
# approximately by force <= power / velocity.
# Measured in Watts.
# At high speed, impulse per flap = flap power / velocity * flap_cycle_duration * power_stroke_percentage
# (cycle averaged) Acceleration is flap_power / velocity * power_stroke_percentage / mass
# So you'll notice flap power starts to become limiting when max_power/max_force < velocity in m/s. 
# This also starts to highlight some of the game magic that enables human flight. 500 newtons of flap force?
# Bah, that's a deadlift! No problem! Maintaining that force at speed? Now our brave hero is an absurd 
# 2.5 kilowatt generator. Actually, typical muscle efficiency is around 25%, so she's also a 7.5 KW space heater. 
# For comparison, a real human athlete can manage about 4-500 watts for an hour.  2500 is around the maximum power 
# a top human athelete might produce over a few short seconds. 
# Fun fact: If left to black body emissions, our heroine would have a body temperature of around 500F.
# Those giant wings must also be fantastic heat exchangers. 
# Handy formula: max_speed= cube_root(power_stroke_percentage * flap_power / air_drag_coefficient / mass)	
# So 2500 max power at 45 kg and 0.008 drag ~= 11 m/s top speed, about 24 mph.
# And 4500 max power ~= 30 mph, which actually makes for a nicer game. She sustains twice the instantaneous peak output of top athletes! 
@export var max_flap_power := 4500.0

# How long is one beat cycle. This is mostly visual but also affects the "feel" of flying. 
# Stamina norms out time now so net stamina cost is unaffected, but larger values make it chunkier.
# Game allows for "extra" wingbeats (especially vertical) at extra stamina cost. In seconds.
@export var flap_cycle_duration := 1
# This is the portion of the flap that is the power stroke. Increasing this linearly increases 
# the impulse from flap power and force without costing stamina, 
# so it should probably be left alone. May convert it to a 
# gamewide constant at some point, as there seems little value in having it configurable. 
#@export var power_stroke_percentage := 0.2 

@export_group("Stamina")

# Total stamina available for flapping and other strenuous flight actions.
# Higher values allow longer periods of powered flight before exhaustion.
@export var max_stamina := 200.0

# Stamina restored per second.
# Higher values allow more frequent bursts of powered flight after resting/gliding.
@export var stamina_recovery := 7.5

