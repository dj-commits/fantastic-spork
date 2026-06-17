extends CharacterBody3D
# A single selectable RTS unit.
# The selection system (selection.gd) calls set_selected() to highlight us and
# move_to() to give us a destination. From there we walk there ourselves,
# following a path (worked out by the NavigationAgent3D) that bends around
# obstacles like the cover boxes instead of trying to plow straight through.

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
	# is_navigation_finished() is true once we've reached the destination (or we
	# never had one). While we still have road to cover, head for the next point.
	if not nav_agent.is_navigation_finished():
		# The agent hands back the next corner along the path. We flatten it
		# (zero out the up/down part) so we only ever walk along the ground.
		var next_point := nav_agent.get_next_path_position()
		var to_next := next_point - global_position
		to_next.y = 0.0
		if to_next.length() > 0.01:     # guard so we never normalize a zero vector
			# normalized() = "pure direction"; times MOVE_SPEED = "that way, full speed".
			desired = to_next.normalized() * MOVE_SPEED

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
