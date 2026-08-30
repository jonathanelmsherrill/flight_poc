class_name FlyerProfile
extends Resource


@export_group("Aerodynamics")

# How much aerodynamic force fully deployed wings can generate from airflow.
# Higher values give stronger lift/turning authority at a given airspeed.
# Can be thought of crudely as the size of the wing - larger wings move more air. 
# But in this game wings can be better or worse despite the size. 
# Normally lift = 0.5*density*v^2*wing-area*Lift coefficient 
# where lift_coefficient normally depends on airfoil shape, angle of attack, camber, and flow behavior
# In our abstraction, wing area and the inherent properties of the wing, plus game magic,  
# are rolled into 'aerodynamic_authority'. Velocity is situational, and angle of attack/orientation is 
# accounted for where we determine how that authority is applied. 
# While other figures attempt to be more or less realistic, this is the most unrealistic element of a human shaped flier.
@export var aerodynamic_authority := 1.0

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
# May never use this, but is an interesting thought. 
@export var control_rate := 1


@export_group("Flapping")

# Amount of velocity/energy added by a normal flap.
# Higher values improve acceleration, climbing, takeoff, and recovery from low speed.
# Assuming normal mass (not currently implemented), equals the m/s change from one flap. 
@export var flap_impulse := 2.5


@export_group("Stamina")

# Total stamina available for flapping and other strenuous flight actions.
# Higher values allow longer periods of powered flight before exhaustion.
@export var max_stamina := 100.0

# Stamina restored per second.
# Higher values allow more frequent bursts of powered flight after resting/gliding.
@export var stamina_recovery := 7.0