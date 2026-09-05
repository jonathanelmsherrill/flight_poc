# Flight POC – Flight Design Handoff

This document captures the current design decisions for the Godot flight prototype. It is intended as a stable implementation reference for Codex/Rider work, not as a transcript of the exploratory discussion that produced it.

The prototype is deliberately trying to produce **gameplay from reasonably coherent physics**, rather than emulate a fighter jet or use arbitrary "flying movement" rules. The goal is a winged humanoid whose altitude, airspeed, flapping, turning, drag, stalls, and landing behavior interact naturally enough to create interesting choices.

---

## 1. Core Design Goals

The flight model should make these behaviors emerge where practical:

- Altitude is valuable stored potential energy.
- Diving trades altitude for airspeed.
- Pulling out of a dive can trade airspeed back into altitude.
- Flapping adds energy to the system.
- Drag removes energy.
- Aerodynamic wing force primarily redirects motion.
- Low-speed flight has poor maneuver authority.
- High-speed flight has more aerodynamic authority, until structural limits force tighter wing trim.
- Hard maneuvers should lose more energy than gentle ones.
- Near-stall and post-stall wing orientations should become increasingly draggy.
- A wing can eventually act as a deliberate airbrake.
- Flat-ground takeoff may be impossible or difficult for weak/low-level flyers and improve with progression.
- Player controls should express **intent**, while a flight controller decides how to realize that intent aerodynamically.

The player should not directly control detailed aerodynamics such as exact angle of attack (AoA).

---

## 2. Current Godot Context

Current engine/language assumptions:

- Godot 4
- GDScript
- Rider as external editor
- `Player` root is a `CharacterBody3D`
- Ground/world geometry uses ordinary Godot static collision
- Camera uses yaw/pitch pivots and a `SpringArm3D`
- There is already:
  - walking
  - jumping
  - flapping
  - stamina
  - third-person camera
  - basic procedural sky
  - simple world geometry
  - debug numeric readouts
  - visual speed tilt
  - flap squash/stretch tween feedback

Representative scene structure is approximately:

```text
Player (CharacterBody3D)
├── CollisionShape3D
├── VisualRoot
│   └── current capsule visual
├── CameraPivot
│   └── CameraPitch
│       └── FreeLookYaw        # planned / partially implemented
│           └── FreeLookPitch  # planned / partially implemented
│               └── SpringArm3D
│                   └── Camera3D
└── CanvasLayer
    ├── stamina UI
    └── debug UI
```

Planned visual expansion:

```text
VisualRoot
├── BodyVisual
├── LeftWingPivot
│   └── LeftWingMesh
└── RightWingPivot
    └── RightWingMesh
```

The wings can initially be crude triangle meshes. Their purpose is not prettiness; it is to make body orientation, wing orientation, and AoA visible while tuning the physics.

---

## 3. Coordinate / State Concepts

These directions must remain conceptually distinct:

1. **Camera direction**
   - Where the player is currently looking / aiming.

2. **Desired flight direction**
   - Where the player is asking Capsule Girl to try to go.

3. **Body direction**
   - Where Capsule Girl's torso/body is actually oriented.

4. **Wing orientation**
   - The actual aerodynamic orientation of the wings.

5. **Velocity direction**
   - Where physics is actually carrying the player.

These may coincide in simple flight, but they should not be assumed identical.

This distinction matters for:

- free look
- aiming while flying
- stalls
- pull-ups
- airbraking
- animation
- future control-rate limitations

---

## 4. Proposed Architecture

Do not continue sprinkling raw "player intended direction" logic throughout the physics loop.

Use explicit layers:

```text
INPUT
mouse / WASD / Shift / freelook
        ↓
FlightIntent
        ↓
FlightController
        ↓
FlightControlCommand
        ↓
actual body + wing state
        ↓
aerodynamic physics
        ↓
CharacterBody3D velocity
```

### 4.1 `FlightIntent`

Suggested file:

```text
flight_intent.gd
```

Suggested type:

```gdscript
class_name FlightIntent
extends RefCounted
```

Initial interface:

```gdscript
var desired_direction: Vector3
var maneuver_aggression: float
```

Meaning:

- `desired_direction`: desired flight-path direction.
- `maneuver_aggression`: how strongly the player wants the controller to pursue that direction, including how much efficiency / speed / altitude the player is willing to sacrifice.

This should be continuous, probably in a normalized range such as `0.0 .. 1.0`, rather than an enum such as NORMAL / SEVERE / BRAKING.

AoA should **not** be part of `FlightIntent`.

If later this interface proves insufficient, it can be expanded without contaminating the aerodynamic model. Possible future additions include:

```text
energy_priority
allow_stall
combat_priority
climb_priority
```

Do not add these unless they are actually needed.

---

### 4.2 `FlightController`

Suggested file:

```text
flight_controller.gd
```

Suggested type:

```gdscript
class_name FlightController
extends RefCounted
```

The controller consumes:

- `FlightIntent`
- current air-relative velocity
- body/wing state
- `FlyerProfile`

and produces a command for the flyer.

The controller owns decisions such as:

- desired body orientation
- desired lift direction
- desired wing orientation
- target AoA
- whether to remain in efficient trim
- whether to use maximum useful lift
- whether to continue into post-stall / airbrake territory

The controller should have a conspicuous standalone function for AoA selection because this is expected to be heavily tuned for game feel.

Conceptually:

```gdscript
func choose_target_aoa(
    intent: FlightIntent,
    current_state,
    flyer_profile: FlyerProfile
) -> float:
    ...
```

Exact inputs can be refined during implementation.

---

### 4.3 `FlightControlCommand`

Suggested file:

```text
flight_control_command.gd
```

Suggested type:

```gdscript
class_name FlightControlCommand
extends RefCounted
```

Possible initial fields:

```gdscript
var target_body_direction: Vector3
var target_wing_normal: Vector3
var target_aoa: float
```

This interface may change as the wing/body model becomes clearer.

Maintain a distinction between:

```text
target_aoa
actual_aoa
```

Even if initially:

```gdscript
actual_aoa = target_aoa
```

Later `control_rate` can make actual orientation chase the target instead of snapping instantly.

---

### 4.4 `Player`

`Player.gd` remains the orchestrator and owns actual runtime state:

- `velocity`
- stamina
- flap timing/state
- actual body orientation
- actual wing orientation
- Godot node references
- collision/movement
- camera state

The long-term physics loop should read approximately like:

```gdscript
func _physics_process(delta: float) -> void:
    var intent := get_flight_intent()

    var control := flight_controller.get_control_command(
        intent,
        current_flight_state,
        flyer_profile
    )

    update_body_and_wings(control, delta)

    apply_gravity(delta)
    apply_aerodynamics(delta)
    apply_flapping(delta)

    move_and_slide()
```

The exact ordering may change as the force integration is implemented.

---

## 5. `FlyerProfile`

Use a custom Godot `Resource` for persistent/tunable flyer capabilities.

Suggested filename:

```text
flyer_profile.gd
```

Suggested declaration:

```gdscript
class_name FlyerProfile
extends Resource
```

Current profile concepts:

### Aerodynamic authority

```gdscript
@export var aerodynamic_authority := 1.0
```

Meaning:

- how much aerodynamic force fully deployed wings can generate from airflow
- roughly rolls together wing area, inherent aerodynamic quality, and deliberate game-magic
- current velocity and AoA are **not** rolled into this stat; they are situational inputs

The intended conceptual reference is:

```text
lift = 0.5 * density * v² * wing_area * lift_coefficient
```

`aerodynamic_authority` deliberately collapses much of wing area + inherent wing quality into a game-friendly parameter.

This is expected to be the least physically realistic parameter because human-sized wings need fictional assistance.

---

### Structural load tolerance

```gdscript
@export var structural_load_tolerance := 20.0
```

Meaning:

- maximum aerodynamic acceleration / load the wings and body can physically tolerate
- at high speed this becomes the limiting factor
- forces tighter wing trim / reduced effective wing deployment at sufficiently high dynamic pressure

Useful distinction:

- a glider-like flyer can have **high aerodynamic authority**
- but **low structural load tolerance**

Thus large efficient wings do not automatically imply brutal maneuver capability at high speed.

High-speed usable flight envelope should mostly emerge from aerodynamic authority + structural tolerance rather than a separate hard max-speed stat.

---

### Parasite drag coefficient

```gdscript
@export var parasite_drag_coefficient := 0.008
```

Meaning:

- baseline drag from moving body/wings through air
- scales approximately with `v²`
- lower is better streamlining

This should remain distinct from induced drag and high-AoA / separated-flow drag.

---

### Control rate

```gdscript
@export var control_rate := 1.0
```

Meaning:

- how quickly body/wings can reorient toward the controller's requested aerodynamic configuration
- example question: "I fell off a cliff; how quickly can I get my wings into a useful orientation?"

This may remain unimplemented until actual body/wing orientation matters enough to justify it.

---

### Flap force and flap power

The earlier `flap_impulse` abstraction is expected to evolve.

Long-term flapping capability should probably use two separate limits:

```text
max_flap_force
max_flap_power
```

Reason:

- force and power are independent physical constraints
- low-speed propulsion is force-limited
- high-speed propulsion becomes power-limited

Approximate available propulsion:

```text
F_flap <= F_max
F_flap <= P_max / v_effective
```

or:

```text
F_flap_available = min(F_max, P_max / v_effective)
```

The exact relevant air-relative velocity needs care during implementation.

Wing pitch / twist / AoA can be thought of as a kind of variable gearing that lets the flyer keep the muscles in a favorable operating region across a broad speed range. Do **not** model this gearing explicitly yet.

---

### Stamina

Keep total stamina and recovery separate:

```gdscript
@export var max_stamina := 100.0
@export var stamina_recovery := 7.0
```

They produce meaningfully different flyer profiles:

- larger pool → longer bursts / sustained powered flight
- higher recovery → more rhythmic flap/glide/recover play

Actual current stamina remains runtime state on `Player`, not in the profile.

---

## 6. Air-Relative Velocity

All aerodynamic calculations should eventually use velocity relative to the air, not raw world velocity.

Conceptually:

```gdscript
var air_velocity_world := Vector3.ZERO  # for now
var air_relative_velocity := velocity - air_velocity_world
var airspeed := air_relative_velocity.length()
```

With still air this reduces to current behavior.

This abstraction later enables:

- wind
- updrafts
- storms
- ship wakes
- thermals
- moving atmospheric regions

without changing the fundamental flight equations.

---

## 7. Force / Energy Responsibilities

Keep each physical mechanism conceptually clean.

### Gravity

- adds downward acceleration
- exchanges kinetic and potential energy naturally
- should not be directly canceled except through generated aerodynamic force

### Flapping

- adds mechanical energy to the system
- eventually governed by max flap force + max flap power
- may initially still be numerically integrated as an instantaneous impulse for convenience

### Wing aerodynamic force

- primarily redirects air-relative velocity
- can change direction without directly adding kinetic energy when perpendicular to velocity
- in discrete Euler integration, a tangential/perpendicular force step can introduce a small artificial energy gain; correcting/renormalizing that discrete artifact is acceptable

### Parasite drag

- removes energy
- approximately proportional to `v²`

### Induced drag

- removes energy as the cost of generating useful aerodynamic force/lift
- derived from actual generated wing force and airspeed rather than being an independent character stat

Approximate structure:

```text
D_induced ∝ wing_force² / (airspeed² * aerodynamic_authority)
```

Exact scaling constant is tunable.

### High-AoA / separated-flow drag

- additional drag when wing incidence becomes aggressive / flow separates
- especially important near and after stall
- eventually turns the wing into an intentional airbrake
- should not be folded into baseline parasite drag

---

## 8. Angle of Attack (AoA)

AoA is now considered an explicit useful state.

`alpha` / AoA means:

> angle between actual wing chord/orientation and incoming airflow

It is **not**:

> angle between current velocity and desired player direction

The requested maneuver influences the controller; the controller chooses a target wing orientation/AoA; actual AoA then determines aerodynamic coefficients.

AoA is valuable for both:

- physics
- eventual animation

Animation can use AoA to drive:

- wing pitch/feathering
- wing spread
- strain poses
- stall buffet
- high-AoA braking poses
- landing flare poses

---

## 9. Body Orientation vs Wing AoA

Capsule Girl should not be treated exactly like a rigid fixed-wing aircraft.

Birdlike / organic wings can meaningfully adjust incidence and twist independently of body pitch.

However, allowing the controller to silently use the entire AoA range while keeping the body visually level creates unintuitive behavior: the flyer can arrive at maximum-lift / near-stall AoA without the player seeing any corresponding commitment.

Current preferred compromise:

- body/intended-flight orientation establishes the **major aerodynamic attitude**
- wings may automatically trim within a modest efficient range
- large AoA excursions should correspond to visible/player-commanded maneuvering

Conceptually:

```text
body / intended flight attitude
        ↓
baseline wing orientation
        ↓
automatic efficient trim
        ↓
actual wing AoA
```

Normal trim should not silently consume the entire maximum-lift margin.

When speed becomes insufficient for level flight using normal trim, Capsule Girl should begin to descend rather than automatically driving the wings all the way to max-lift AoA.

A strong maneuver request can then explicitly access the rest of the AoA envelope.

---

## 10. Lift and Drag Coefficients

Aerodynamic force should eventually be computed from coefficient curves as a function of AoA.

Conceptual structure:

```text
lift  = aerodynamic_authority * airspeed² * CL(alpha)
drag  = aerodynamic_authority * airspeed² * CD_related_terms(alpha)
```

Constants will require scaling because `aerodynamic_authority` already collapses real-world terms such as density and wing area.

---

### 10.1 Attached-flow lift

Before stall, lift coefficient can be approximated roughly linearly:

```text
CL ≈ CL_SLOPE * alpha
```

A zero-lift AoA / camber offset can be added later if desired, but is not currently considered gameplay-important because the controller will select whatever AoA is needed.

---

### 10.2 Attached-flow drag

In ordinary flight:

```text
total drag ≈
    parasite drag
    + induced drag
```

Induced drag already accounts for much of the normal drag cost of demanding greater lift/AoA because useful lift demand rises with lift coefficient.

---

### 10.3 Stall and post-stall / plate approximation

At high AoA, the wing increasingly behaves like a broad plate rather than an efficient attached-flow airfoil.

A useful simplified plate-side model is:

```text
CL_plate ∝ sin(alpha) * cos(alpha)
CD_plate ∝ sin²(alpha)
```

Geometric intuition:

- one `sin(alpha)` comes from how much broadside area is presented to the airflow
- projecting the resulting force into lift/drag introduces the additional `cos(alpha)` / `sin(alpha)`

Useful endpoints:

```text
AoA 0°:
    plate lift ≈ 0
    plate drag contribution ≈ 0

AoA 45°:
    substantial lift
    substantial drag

AoA 90°:
    useful lift ≈ 0
    drag ≈ maximum
    => full airbrake
```

Because baseline parasite drag is already modeled separately, do **not** include an extra `CD0 * cos²(alpha)` term merely to give the plate model nonzero drag at 0°.

---

### 10.4 Smooth stall transition

Blend smoothly from attached-flow coefficients to post-stall plate-like coefficients across a stall region.

Conceptually:

```text
efficient attached flow
        ↓
increasing lift / induced drag
        ↓
stall onset
        ↓
flow separation
        ↓
post-stall plate behavior
        ↓
90° broadside airbrake
```

Use a smooth blend such as `smoothstep()` rather than a hard threshold.

Exact stall angles and curve shape are intentionally tunable.

---

## 11. The Four Important AoA / Control Scenarios

The controller should eventually handle these as one continuous system, not four separate physics modes.

### 11.1 Level flight

Goal:

- maintain desired level trajectory efficiently

Controller:

- use minimal efficient AoA / trim needed to approximately offset gravity
- remain inside normal trim range
- if airspeed is insufficient, begin settling into a glide rather than silently consuming all emergency AoA margin

---

### 11.2 Efficient climb / maneuver

Goal:

- player asks for a modestly different flight direction

Controller:

- determine required trajectory curvature
- choose the smallest efficient AoA that produces sufficient lift
- use bank/wing-force orientation to point lift appropriately
- preserve energy where reasonable

---

### 11.3 Emergency / maximum lift

Goal:

- player makes a strong maneuver request

Controller:

- increase AoA toward the angle producing maximum useful lift
- accept increased induced/profile drag
- use all available aerodynamic authority if required

If requested maneuver exceeds maximum useful lift, physics cannot satisfy it.

---

### 11.4 Airbrake / post-stall command

Goal:

- player continues commanding beyond maximum useful lift / requests an intentionally extreme maneuver

Controller:

- allow AoA to continue beyond max-lift AoA
- useful lift eventually falls
- high-AoA drag rises strongly
- near 90° the wing acts mostly as a broadside airbrake

This should emerge continuously from AoA rather than an `if airbrake: drag *= N` rule.

---

## 12. Gravity and Maneuvering

A wing force perpendicular to velocity can redirect velocity without directly adding kinetic energy.

But to curve a horizontal trajectory upward, net upward acceleration must exceed gravity.

For a pull-up:

```text
wing force must:
    1. counter gravity
    2. provide additional centripetal acceleration
```

Thus a flyer whose absolute maximum aerodynamic force is only approximately `1g` at a given airspeed has essentially no upward maneuver margin at that speed.

However, if the player aggressively increases AoA without enough airspeed to pull up successfully, the wings should still become increasingly draggy and eventually stall / airbrake. This is why explicit AoA / post-stall drag is important.

---

## 13. Control Philosophy

The player should express intent, not micromanage aerodynamic surfaces.

Current control concepts:

### Normal mode

Approximate intent:

> "Try to get me where I'm pointing, but fly sensibly and preserve combat usefulness / altitude / energy."

Likely properties:

- efficient AoA preference
- conservative automatic trim
- avoids accidental stalls
- avoids unnecessarily steep climbs/dives
- camera/aim can wander somewhat around actual flight orientation

### Freelook

Approximate intent:

> "Let me look/aim independently without changing my current flight intent."

Likely properties:

- freezes/decouples desired flight direction
- widens camera cone
- future shooting may follow camera rather than flight heading

### Aggressive / flight-focus modifier (possibly Shift)

Not committed yet.

Possible interpretation:

> "I really mean this maneuver. Accept higher AoA, energy loss, stall risk, or airbraking."

This should modify maneuver aggression / controller constraints rather than create an entirely separate physics system.

It may prove unnecessary if mouse displacement / other intent signals are sufficient.

---

## 14. Camera / Freelook Structure

Planned camera branch:

```text
CameraPivot        # normal steering yaw / desired-flight frame
└── CameraPitch    # normal steering pitch
    └── FreeLookYaw
        └── FreeLookPitch
            └── SpringArm3D
                └── Camera3D
```

Meaning:

- `CameraPivot + CameraPitch` represent the normal desired-flight viewing frame
- freelook pivots add camera-only offsets

In normal mode:

```text
camera direction ≈ desired flight direction
```

During freelook:

```text
camera direction != desired flight direction
```

When freelook ends, camera should recenter toward the preserved desired-flight frame rather than retroactively steering Capsule Girl to wherever the player looked.

---

## 15. Flapping Notes

Current prototype flapping has already produced useful game feel:

- Space can produce vertical/upward-biased flap effort
- movement input can bias flap effort toward intended travel direction
- holding input can produce repeated wingbeats
- rapid taps can represent vigorous takeoff effort at extra stamina cost
- stamina is a meaningful energy-management mechanic

Long-term refactor:

- represent flap capability in force/power terms
- optionally apply flap force over the duration of an animated wingbeat
- current instantaneous velocity change can remain as an integration shortcut initially

A finite-duration flap may eventually look/feel better because:

- acceleration becomes smooth over the visible wingbeat
- aerodynamic state can change during the flap
- orientation changes during the flap can matter

But position remains continuous even with instantaneous velocity changes, so do not assume this refactor is visually necessary until tested.

---

## 16. Debugging / Instrumentation

Existing numeric debug HUD includes values such as:

- speed
- lift
- drag

Continue using numeric readouts for tuning.

Add optional 3D debug vectors to make geometry observable.

High-value vectors:

```text
velocity
desired flight direction
body forward
wing normal / wing chord
lift force
drag force
gravity
flap force
```

Useful debug state values:

```text
airspeed
target AoA
actual AoA
CL
CD / high-AoA contribution
induced drag
parasite drag
available aerodynamic scale
structural-load usage
maneuver aggression
```

The purpose is to answer visually:

> Why is Capsule Girl not going where the player asked?

Numeric values explain magnitude; vectors explain geometry.

---

## 17. Immediate Implementation Plan

Recommended next steps:

### Step 1 – Create architectural seams

Add:

```text
flight_intent.gd
flight_control_command.gd
flight_controller.gd
```

Do not attempt to perfect the controller immediately.

First move input interpretation behind `FlightIntent`.

---

### Step 2 – Make AoA explicit

Add:

```text
target_aoa
actual_aoa
```

Implement a first standalone:

```gdscript
choose_target_aoa(...)
```

Keep it simple and easy to tune.

Do not bury AoA-selection policy inside coefficient math.

---

### Step 3 – Add coefficient functions

Create clearly named functions:

```gdscript
get_lift_coefficient(alpha: float) -> float
get_high_aoa_drag_coefficient(alpha: float) -> float
```

Blend attached-flow and post-stall behavior smoothly.

Keep induced drag and parasite drag separate.

---

### Step 4 – Apply aerodynamic force from actual wing state

Replace direct "requested force capped by available force" logic with:

```text
requested maneuver
    ↓
controller target orientation / AoA
    ↓
actual wing orientation / AoA
    ↓
CL/CD
    ↓
actual force
```

Retain discrete energy correction if needed when numerically applying a theoretically energy-neutral perpendicular wing force.

---

### Step 5 – Add programmer-art wings

Add triangle wings with pivots.

Make body and wing orientation visually obvious.

Use this to validate whether apparently correct controller decisions actually feel/read correctly.

---

### Step 6 – Add debug vectors

Visualize:

- actual velocity
- intended direction
- lift
- drag
- wing orientation

Use these while tuning `choose_target_aoa()`.

---

## 18. Deliberately Deferred

Do not solve these until the current AoA/controller model is working:

- detailed muscle force–velocity curve
- explicit wing "gearing" / pitch transmission range
- mass/loadout effects
- left/right wing asymmetry for detailed roll control
- wind / atmospheric velocity fields
- realistic feather deformation
- injury / structural damage above load limits
- exact bird/anatomical airfoil data
- sophisticated stall hysteresis
- Reynolds-number effects
- CFD-level aerodynamics

Possible future derived mechanics include:

- equipment mass affecting flight
- different flyer archetypes based on force/power/drag/load tolerance
- automatic high-speed wing tuck
- stall recovery skill
- landing flares / deliberate stalled airbrakes
- combat shooting while freelooking
- high-speed structural danger

---

## 19. Design Principle to Preserve

The most important architectural principle is:

> **Input expresses what the player wants. The flight controller decides what the flyer should do. The aerodynamic model decides what physics actually permits.**

Do not collapse those three layers back together unless a later prototype clearly demonstrates that the separation is unnecessary.

This project benefits from letting behaviors emerge from the physics where practical, but game feel has priority over aerodynamic purity.
