# Flight physics

## Airflow relative to the flyer

Aerodynamic forces use the flyer's velocity relative to the surrounding air:

```gdscript
relative_air_velocity = flyer_velocity - local_air_velocity
```

The flight controller plans turns and wing orientation from relative airflow.
This lets a moving air mass carry the flyer's world-space trajectory: an
updraft increases angle of attack and carries the flyer upward instead of the
controller automatically converting the climb into forward speed.

## Splitting airflow at the wing

The physics engine separates relative airflow into components normal and
tangent to the wing surface:

```gdscript
normal_air_velocity = wing_normal * relative_air_velocity.dot(wing_normal)
surface_air_velocity = relative_air_velocity - normal_air_velocity
```

These components feed different physical mechanisms:

- Lift uses the total relative airspeed and effective angle of attack.
- Baseline parasite drag uses the squared speed tangent to the wing and acts
  opposite that tangent airflow.
- Separated-flow pressure drag uses the squared normal airflow and acts
  opposite the airflow striking the wing surface.
- Induced drag depends only on the lift actually produced and acts downstream,
  opposite the total relative airflow.

This prevents a vertical updraft from automatically multiplying horizontal
baseline drag on a horizontal wing. A tilted wing can still turn normal
pressure into a horizontal force, because that force follows the physical wing
normal.

The high-angle-of-attack pressure formula is equivalent to the usual plate
form based on total airspeed and angle of attack:

```text
airspeed^2 * sin(alpha)^2 = normal_airspeed^2
```

Flow separation blends that pressure drag in between the configured stall
onset and full-separation angles.

## Current limitation

### Steep-dive lateral control

The controller currently clamps requested lift at zero on the camera-down side
to prevent negative AoA and an upside-down wing-normal flip. In a fast, steep
dive this can leave only a tiny lateral request; because aerodynamic authority
is high, that request can still become a large force and demand a near-90° bank,
producing an unexpectedly sharp left or right curve. `MIN_LIFT_COMMAND_FORCE`
does not solve this at high speed. A future control pass should consider a
small bounded negative-AoA range for gentle corrections, with inversion or a
different maneuver required only when the request exceeds that range.

A surface normal distinguishes normal airflow from airflow within the wing
plane, but it cannot distinguish chordwise flow from spanwise flow. The current
model therefore treats every direction within the wing plane the same. Proper
sideslip behavior would require the physical state to carry a complete wing
basis containing normal, chord, and span directions.
