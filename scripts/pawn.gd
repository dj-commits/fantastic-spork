extends CharacterBody3D
# A single selectable RTS unit.
# The selection system (selection.gd) calls set_selected() to highlight us and
# move_to() to give us a destination. From there we walk there ourselves,
# following a path (worked out by the NavigationAgent3D) that bends around
# obstacles like the cover boxes instead of trying to plow straight through.

## Within this many meters of the destination we ease our speed down, so we
## glide to a gentle stop instead of charging in at full speed and overshooting.
@export var arrival_distance: float = 3.5
## Once we're this close to the destination (measured flat along the ground) we
## call it "arrived" and stop. (Measured flat — see _physics_process.)
@export var stop_distance: float = 0.3

@onready var selection_ring: MeshInstance3D = $SelectionRing
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

const MOVE_SPEED: float = 4.0        # top walking speed, in meters per second
# How quickly we change speed, in meters per second, *per second*. This is what
# stops movement feeling robotic: instead of snapping to full speed and to a
# dead stop, we ramp up and ease down. Lower = heavier / more gradual.
const ACCELERATION: float = 12.0
const GRAVITY: float = 20.0          # downward pull so we stay stuck to the ground

var is_selected: bool = false

func _ready() -> void:
	# Join the "units" group so the selection system can find every unit at once.
	add_to_group("units")
	set_selected(false)             # start unselected (ring hidden)
	# Target our own spot to begin with, so we sit still until given an order.
	# (A NavigationAgent3D's default target is the world origin, so without this
	# every unit would immediately wander off toward (0,0,0) on startup.)
	nav_agent.target_position = global_position

# Highlight / un-highlight this unit. Called by the selection system.
func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value

# Give this unit a place to walk to. Called when the player right-clicks ground.
# We just hand the destination to the navigation agent; it figures out the route.
func move_to(world_point: Vector3) -> void:
	nav_agent.target_position = world_point

func _physics_process(delta: float) -> void:
	# First work out the velocity we WANT this frame ("desired"), then ease our
	# real velocity toward it so we speed up and slow down smoothly.
	var desired := Vector3.ZERO

	# How far we still are from the FINAL destination, measured FLAT along the
	# ground (we deliberately zero out the y). This is the crux of the jitter fix:
	# a unit's origin sits at its waist (~0.9m up), but the target and navigation
	# mesh sit on the floor. If we left that height gap in the distance, a unit
	# standing right on its target would still read ~0.9m away — so it could never
	# "arrive", and kept nudging back and forth. Flat distance really hits 0.
	var to_target := nav_agent.target_position - global_position
	to_target.y = 0.0
	var remaining := to_target.length()

	# Keep steering until we're within stop_distance of the target. Once inside,
	# desired stays zero, so we ease to a halt and stay put.
	if remaining > stop_distance:
		# The agent hands back the next corner along the path (it bends around
		# cover). Flatten it too, so we only ever walk along the ground.
		var next_point := nav_agent.get_next_path_position()
		var to_next := next_point - global_position
		to_next.y = 0.0
		if to_next.length() > 0.01:     # guard so we never normalize a zero vector
			# Pick a speed: full speed normally, eased down over the last
			# "arrival_distance" meters so we glide to a gentle stop.
			var speed := MOVE_SPEED
			if remaining < arrival_distance:
				# remaining / arrival_distance slides from 1.0 down to 0.0 as we
				# close in, easing the speed off the nearer we get.
				speed = MOVE_SPEED * (remaining / arrival_distance)
			# normalized() = "pure direction"; times speed = "that way, this fast".
			desired = to_next.normalized() * speed

	# Ease the horizontal (sideways) part of our velocity toward the desired one.
	# move_toward() nudges a value toward a target by at most a set step, so this
	# single call handles BOTH speeding up and slowing down — that's the smooth feel.
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(desired, ACCELERATION * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# Gravity is handled separately from the steering above: always pull down.
	velocity.y -= GRAVITY * delta
	move_and_slide()
	# Once we're resting on the floor, reset downward speed so gravity doesn't
	# keep piling up into a silly-large number frame after frame.
	if is_on_floor():
		velocity.y = 0.0
