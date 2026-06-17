extends CharacterBody3D
class_name Pawn
# The base RTS unit — used directly by the player's units and extended by
# enemies (enemy.gd). It handles movement/navigation, health, cover-seeking AND
# shooting: any unit automatically fires at the nearest enemy it can see in
# range. Each team just sets WHICH side is its enemy (see _register_team), so the
# same combat code drives both the player's squad and the enemy squad.
#
# The one piece that differs by team is _decide_movement(): player units hold
# position / follow orders / take cover, while enemies hunt and advance.

## Top walking speed, in meters per second.
@export var move_speed: float = 4.0
## Within this many meters of the destination we ease our speed down, so we
## glide to a gentle stop instead of charging in at full speed and overshooting.
@export var arrival_distance: float = 3.5
## Once we're this close to the destination (measured flat along the ground) we
## call it "arrived" and stop. (Measured flat — see _apply_movement.)
@export var stop_distance: float = 0.3
## How much damage this unit can absorb before it dies.
@export var max_health: float = 100.0
## How much this unit's stats vary from their listed values, as a fraction, so
## no two units feel identical. Set to 0 for fixed, uniform stats.
@export var stat_variance: float = 0.15
## When true, this unit drifts to the nearest open cover spot whenever it has
## nothing else to do. Player units want this; enemies run their own brain.
@export var auto_seek_cover: bool = true
## How far away this unit can spot and shoot an enemy, in meters.
@export var sight_range: float = 16.0
## Seconds to wait between shots.
@export var fire_cooldown: float = 1.2
## The projectile this unit fires.
@export var projectile_scene: PackedScene

var health: float = 0.0              # current health; set to max_health on ready
var claimed_spot: CoverSpot = null   # the cover spot we've reserved, if any

# Who we fight. Set in _register_team(): player units target the "enemies" group
# and shoot things on the Enemy physics layer; enemies flip both around.
var enemy_group: StringName = "enemies"
var target_layer: int = 8            # physics layer our aim/shots look for (8 = Enemy)

@onready var selection_ring: MeshInstance3D = $SelectionRing
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

# How quickly we change speed (m/s, per second) — ramps movement up/down smoothly
# instead of snapping, so it doesn't feel robotic.
const ACCELERATION: float = 12.0
const GRAVITY: float = 20.0          # downward pull so we stay stuck to the ground
# How far above a unit's centre we aim — chest height. Kept BELOW the capsule's
# top so the line-of-sight ray passes through the body instead of skimming over
# the head (which registered no hit and made units think they had no shot).
const AIM_HEIGHT: float = 0.4

var is_selected: bool = false
var _time_until_next_shot: float = 0.0

func _ready() -> void:
	_roll_stats()                   # give this unit its own slightly-varied stats
	set_selected(false)             # start unselected (ring hidden)
	health = max_health             # start at full health (after the roll above)
	# Target our own spot to begin with, so we sit still until given an order.
	nav_agent.target_position = global_position
	_register_team()

# Roll this unit's personal stats on spawn so units don't all feel identical.
# Subclasses override this to roll their own extra stats — and should call
# super._roll_stats() so these rolls still happen.
func _roll_stats() -> void:
	move_speed = Rng.roll_variance(move_speed, stat_variance)
	max_health = Rng.roll_variance(max_health, stat_variance)
	sight_range = Rng.roll_variance(sight_range, stat_variance)
	fire_cooldown = Rng.roll_variance(fire_cooldown, stat_variance)

# Which team we're on and who we shoot. Player units join the selectable "units"
# group and fight "enemies"; enemy.gd overrides this to flip it around.
func _register_team() -> void:
	add_to_group("units")
	enemy_group = "enemies"
	target_layer = 8                # Enemy physics layer

# --- Health ----------------------------------------------------------------

# Take a hit from an incoming projectile; die once we run out of health.
func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		_die()

func _die() -> void:
	_release_cover()                # free our cover spot for someone else
	# queue_free() also drops us out of every group we joined (units / enemies /
	# control groups), so selection and targeting tidy up after us for free.
	queue_free()

# --- Selection / orders -----------------------------------------------------

# Highlight / un-highlight this unit. Called by the selection system.
func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value

# Hand the navigation agent a destination; it works out the route.
func move_to(world_point: Vector3) -> void:
	nav_agent.target_position = world_point

# A manual order from the player. Unlike move_to, this first drops any cover we
# were holding, so the player's command wins over our own cover-seeking.
func order_move_to(world_point: Vector3) -> void:
	_release_cover()
	move_to(world_point)

# --- Per-frame brain --------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time_until_next_shot -= delta
	var target := _pick_target()              # nearest enemy we can see in range
	_decide_movement(target)                  # where to go (team-specific)
	# Shoot whoever we picked, if our weapon has cooled down. Both teams do this.
	if target != null and _time_until_next_shot <= 0.0:
		_fire_at(target)
		_time_until_next_shot = fire_cooldown
	_apply_movement(delta)                    # actually walk toward the nav target

# Decide where to move by setting our nav target. Base behaviour (player units):
# stay put / follow orders, and slip into the nearest open cover when idle. The
# target is only used for shooting here. Enemies override this to hunt + advance.
func _decide_movement(_target: Node3D) -> void:
	if auto_seek_cover and claimed_spot == null and _remaining_distance() <= stop_distance:
		_seek_cover()

# --- Combat -----------------------------------------------------------------

# The nearest enemy we can actually SEE within sight range, preferring ones
# caught in the open over ones in cover. Null if we can't see anyone.
func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_in_cover := true            # treat "no target yet" as the worst case
	var best_distance := INF
	for unit in get_tree().get_nodes_in_group(enemy_group):
		var distance := global_position.distance_to(unit.global_position)
		if distance > sight_range:
			continue                      # too far to engage
		if not _has_clear_shot(unit):
			continue                      # something's in the way — can't see them
		var in_cover: bool = unit.is_in_cover()
		if _is_better_target(in_cover, distance, best_in_cover, best_distance):
			best = unit
			best_in_cover = in_cover
			best_distance = distance
	return best

# A candidate beats the current best if it's exposed while the best is in cover,
# or — when both are the same — if it's closer.
func _is_better_target(cand_in_cover: bool, cand_distance: float,
		best_in_cover: bool, best_distance: float) -> bool:
	if cand_in_cover != best_in_cover:
		return not cand_in_cover          # the exposed one wins outright
	return cand_distance < best_distance  # same cover status -> nearer wins

# The closest enemy anywhere, ignoring sight (used by enemies to keep hunting
# across the map when they can't see anyone to shoot yet).
func _nearest_enemy() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	for unit in get_tree().get_nodes_in_group(enemy_group):
		var distance := global_position.distance_to(unit.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = unit
	return nearest

# True only if a level, chest-high line from us to the target is unobstructed —
# the first thing it hits is the target, not cover. We test against cover and the
# ENEMY team's layer only, so our own teammates never block the shot (our
# projectiles pass through them anyway — there's no friendly fire).
func _has_clear_shot(target: Node3D) -> bool:
	var from := global_position + Vector3.UP * AIM_HEIGHT
	var to := target.global_position + Vector3.UP * AIM_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2 | target_layer   # cover (layer 2) + the enemy's layer
	query.exclude = [get_rid()]                # never our own body
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit and hit.collider == target

func _fire_at(target: Node3D) -> void:
	if projectile_scene == null:
		return
	var shot := projectile_scene.instantiate()
	# Add to the running scene (not as our child) so it flies free of us.
	get_tree().current_scene.add_child(shot)
	# Tell the shot what it may hit: cover and the enemy team's layer. This is
	# what lets the SAME projectile serve both sides without friendly fire.
	shot.collision_mask = 2 | target_layer
	# Spawn at chest height and aim at the target's chest — matching the
	# line-of-sight check above, so what we cleared is what we fire.
	shot.global_position = global_position + Vector3.UP * AIM_HEIGHT
	shot.launch(target.global_position + Vector3.UP * AIM_HEIGHT)

# --- Cover-seeking ----------------------------------------------------------

# Reserve the nearest free cover spot and head for it. Does nothing if every
# spot is taken.
func _seek_cover() -> void:
	var spot := _nearest_available_cover()
	if spot == null:
		return                          # nowhere free to hide right now
	spot.claim(self)
	claimed_spot = spot
	# Cover spots already sit just outside the cover (cover.gd places them there),
	# so we head straight to one. The nav agent re-plans the route each frame, so
	# it self-corrects even if the navmesh wasn't ready the moment we asked — and
	# because this is a real spot beside cover, it's never the world origin.
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
# still out in the open running toward it. Used to prefer shooting exposed units.
func is_in_cover() -> bool:
	if claimed_spot == null:
		return false
	var to_spot := claimed_spot.global_position - global_position
	to_spot.y = 0.0
	return to_spot.length() <= 1.0

# --- Movement ---------------------------------------------------------------

# How far we still are from our destination, measured FLAT along the ground (the
# y is zeroed). This matters: a unit's origin sits at its waist (~0.9m up) but
# the target and navigation mesh sit on the floor, so leaving the height gap in
# would make a unit standing on its target still read ~0.9m away — it could never
# "arrive" and would jitter back and forth.
func _remaining_distance() -> float:
	var to_target := nav_agent.target_position - global_position
	to_target.y = 0.0
	return to_target.length()

# Walk toward whatever nav target _decide_movement set, easing speed up and down
# and applying gravity.
func _apply_movement(delta: float) -> void:
	var desired := Vector3.ZERO
	var remaining := _remaining_distance()
	# Keep steering until we're within stop_distance of the target. Once inside,
	# desired stays zero, so we ease to a halt and stay put.
	if remaining > stop_distance:
		# The agent hands back the next corner along the path (it bends around
		# cover). Flatten it so we only ever walk along the ground.
		var next_point := nav_agent.get_next_path_position()
		var to_next := next_point - global_position
		to_next.y = 0.0
		if to_next.length() > 0.01:     # guard so we never normalize a zero vector
			# Full speed normally, eased down over the last "arrival_distance"
			# meters so we glide to a gentle stop.
			var speed := move_speed
			if remaining < arrival_distance:
				speed = move_speed * (remaining / arrival_distance)
			desired = to_next.normalized() * speed

	# Ease our horizontal velocity toward the desired one — move_toward handles
	# both speeding up and slowing down with one step.
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(desired, ACCELERATION * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# Gravity is separate from the steering above: always pull down.
	velocity.y -= GRAVITY * delta
	move_and_slide()
	if is_on_floor():
		velocity.y = 0.0
