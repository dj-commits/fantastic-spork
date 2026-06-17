extends CharacterBody3D
class_name Pawn
# The base RTS unit. Player units use this script directly; enemies extend it
# (see enemy.gd) to reuse all the movement, navigation and health below while
# adding their own combat behaviour.
#
# The selection system (selection.gd) calls set_selected() to highlight us and
# move_to() to give us a destination. From there we walk there ourselves,
# following a path (worked out by the NavigationAgent3D) that bends around
# obstacles like the cover boxes instead of trying to plow straight through.

## Top walking speed, in meters per second.
@export var move_speed: float = 4.0
## Within this many meters of the destination we ease our speed down, so we
## glide to a gentle stop instead of charging in at full speed and overshooting.
@export var arrival_distance: float = 3.5
## Once we're this close to the destination (measured flat along the ground) we
## call it "arrived" and stop. (Measured flat — see _physics_process.)
@export var stop_distance: float = 0.3
## How much damage this unit can absorb before it dies.
@export var max_health: float = 100.0
## How much this unit's stats vary from their listed values, as a fraction, so
## no two units feel identical. 0.15 = each rolled stat lands within 15% either
## way. Set to 0 for fixed, uniform stats. (See Rng and _roll_stats.)
@export var stat_variance: float = 0.15
## When true, this unit drifts to the nearest open cover spot whenever it has
## nothing else to do. Player units want this; enemies run their own brain.
@export var auto_seek_cover: bool = true

var health: float = 0.0              # current health; set to max_health on ready
var claimed_spot: CoverSpot = null   # the cover spot we've reserved, if any

@onready var selection_ring: MeshInstance3D = $SelectionRing
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

# How quickly we change speed, in meters per second, *per second*. This is what
# stops movement feeling robotic: instead of snapping to full speed and to a
# dead stop, we ramp up and ease down. Lower = heavier / more gradual.
const ACCELERATION: float = 12.0
const GRAVITY: float = 20.0          # downward pull so we stay stuck to the ground

var is_selected: bool = false

func _ready() -> void:
	_roll_stats()                   # give this unit its own slightly-varied stats
	set_selected(false)             # start unselected (ring hidden)
	health = max_health             # start at full health (after the roll above)
	# Target our own spot to begin with, so we sit still until given an order.
	# (A NavigationAgent3D's default target is the world origin, so without this
	# every unit would immediately wander off toward (0,0,0) on startup.)
	nav_agent.target_position = global_position
	_register_team()

# Roll this unit's personal stats on spawn so units don't all feel identical.
# Subclasses override this to roll their own extra stats — and should call
# super._roll_stats() so this health roll still happens. Adding variance to a
# new stat is a one-liner: stat = Rng.roll_variance(stat, stat_variance).
func _roll_stats() -> void:
	move_speed = Rng.roll_variance(move_speed, stat_variance)
	max_health = Rng.roll_variance(max_health, stat_variance)

# Which group this unit belongs to. Player units are selectable, so they join
# "units" (the group the selection system searches). Enemies override this to
# join "enemies" instead, which keeps them out of the player's selection.
func _register_team() -> void:
	add_to_group("units")

# Take a hit from an incoming projectile. Calling _die() once we run out of health.
func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		_die()

func _die() -> void:
	_release_cover()                # free our cover spot for someone else
	# queue_free() also drops us out of every group we joined (units, enemies,
	# control groups), so selection and enemy targeting tidy up after us for free.
	queue_free()

# Highlight / un-highlight this unit. Called by the selection system.
func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value

# Give this unit a place to walk to. We just hand the destination to the
# navigation agent; it figures out the route. (Used both by player orders and
# by our own cover-seeking below.)
func move_to(world_point: Vector3) -> void:
	nav_agent.target_position = world_point

# A manual order from the player. Unlike move_to, this first drops any cover we
# were holding, so the player's command wins over our own cover-seeking.
func order_move_to(world_point: Vector3) -> void:
	_release_cover()
	move_to(world_point)

# --- Cover-seeking (the unit's first scrap of autonomy) --------------------

# Reserve the nearest free cover spot and head for it. Called automatically when
# we're idle (see _physics_process). Does nothing if every spot is taken.
func _seek_cover() -> void:
	var spot := _nearest_available_cover()
	if spot == null:
		return                          # nowhere free to hide right now
	spot.claim(self)
	claimed_spot = spot
	# Cover spots already sit just outside the cover (cover.gd places them there),
	# so we can head straight to one. The nav agent re-plans the route each frame,
	# so it self-corrects even if the navmesh wasn't ready the moment we asked —
	# and because this is a real spot beside cover, it's never the world origin.
	move_to(spot.global_position)

# The closest cover spot that nobody has claimed, or null if there are none.
func _nearest_available_cover() -> CoverSpot:
	var nearest: CoverSpot = null
	var nearest_distance := INF
	for spot in get_tree().get_nodes_in_group("cover_spots"):
		if not spot.is_available():
			continue
		var distance := global_position.distance_to(spot.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = spot
	return nearest

func _release_cover() -> void:
	if claimed_spot != null:
		claimed_spot.release(self)
		claimed_spot = null

# True once this unit has actually REACHED the cover it claimed — not while it's
# still out in the open running toward it. Enemies use this to prefer shooting
# units that are exposed.
func is_in_cover() -> bool:
	if claimed_spot == null:
		return false
	var to_spot := claimed_spot.global_position - global_position
	to_spot.y = 0.0
	return to_spot.length() <= 1.0

# How far we still are from our destination, measured FLAT along the ground (the
# y is zeroed — see the long note in _physics_process for why that matters).
func _remaining_distance() -> float:
	var to_target := nav_agent.target_position - global_position
	to_target.y = 0.0
	return to_target.length()

func _physics_process(delta: float) -> void:
	# Idle behaviour: a unit with nothing to do (reached its target and hasn't
	# claimed cover) quietly slides into the nearest open cover spot. Enemies set
	# auto_seek_cover = false and run their own combat brain instead.
	if auto_seek_cover and claimed_spot == null and _remaining_distance() <= stop_distance:
		_seek_cover()

	# First work out the velocity we WANT this frame ("desired"), then ease our
	# real velocity toward it so we speed up and slow down smoothly.
	var desired := Vector3.ZERO

	# How far we still are from the destination, measured FLAT along the ground
	# (y zeroed). This is the crux of the jitter fix: a unit's origin sits at its
	# waist (~0.9m up) but the target and navigation mesh sit on the floor. If we
	# left that height gap in, a unit standing right on its target would read
	# ~0.9m away — so it could never "arrive" and kept nudging back and forth.
	var remaining := _remaining_distance()

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
			var speed := move_speed
			if remaining < arrival_distance:
				# remaining / arrival_distance slides from 1.0 down to 0.0 as we
				# close in, easing the speed off the nearer we get.
				speed = move_speed * (remaining / arrival_distance)
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
