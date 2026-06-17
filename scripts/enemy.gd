extends Pawn
# An enemy unit. It reuses everything a Pawn can do — walking, navigation,
# health, taking damage — and adds the combat brain on top: find the nearest of
# the player's units, advance until it's in range, then shoot on a cooldown.
#
# Because it overrides _register_team() to join "enemies" (not "units"), the
# player's selection system never picks it up, so it can't be selected or ordered.

## How close one of the player's units must be before this enemy notices it and
## starts to engage.
@export var sight_range: float = 16.0
## Once this close to its target, the enemy stops advancing and just shoots.
@export var firing_range: float = 9.0
## Seconds to wait between shots.
@export var fire_cooldown: float = 1.2
## The projectile scene this enemy fires (assigned in enemy.tscn).
@export var projectile_scene: PackedScene

# How far above a unit's centre we aim — roughly chest height. Kept BELOW the
# capsule's top (~0.9 above centre) on purpose: aiming at the very top made the
# line-of-sight ray skim over the target's head and hit nothing, so enemies
# thought they had no shot. A level chest-high ray passes through the body.
const AIM_HEIGHT: float = 0.4

var _time_until_next_shot: float = 0.0

# Join the enemy team instead of the player's selectable "units" group.
func _register_team() -> void:
	add_to_group("enemies")

# Roll our combat stats on spawn so each enemy engages from a slightly different
# range, paces its shots differently, and has a bit more/less health. super
# keeps the inherited health roll from Pawn.
func _roll_stats() -> void:
	super._roll_stats()
	sight_range = Rng.roll_variance(sight_range, stat_variance)
	firing_range = Rng.roll_variance(firing_range, stat_variance)
	fire_cooldown = Rng.roll_variance(fire_cooldown, stat_variance)

func _physics_process(delta: float) -> void:
	# Count down toward our next allowed shot.
	_time_until_next_shot -= delta

	var target := _pick_target()
	if target != null:
		# We can see this one and it's within sight range. Hold once we're in
		# firing range, otherwise close the distance for the shot.
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() <= firing_range:
			move_to(global_position)          # in range with a clear shot — hold
		else:
			move_to(target.global_position)   # close in

		if _time_until_next_shot <= 0.0:
			_fire_at(target)
			_time_until_next_shot = fire_cooldown
	else:
		# Nobody in sight — advance on the nearest unit to flush them out, so the
		# across-the-map hunt still happens even when we can't yet see anyone.
		var prey := _nearest_player_unit()
		if prey != null:
			move_to(prey.global_position)
		else:
			move_to(global_position)          # all player units gone — stand down

	# Hand off to the inherited Pawn movement, which actually walks us toward
	# whatever move_to() target we just set (and applies gravity, etc.).
	super._physics_process(delta)

# Choose who to shoot: among the player units we can actually SEE within sight
# range, prefer ones caught in the open over ones in cover, and the nearest
# within each of those groups. Returns null if we can't see anyone.
func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_in_cover := true            # treat "no target yet" as the worst case
	var best_distance := INF
	for unit in get_tree().get_nodes_in_group("units"):
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

# The closest player unit anywhere on the map, or null if they're all gone. No
# sight limit — used to keep hunting the squad across the field when we can't
# see anyone to shoot yet.
func _nearest_player_unit() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	for unit in get_tree().get_nodes_in_group("units"):
		var distance := global_position.distance_to(unit.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = unit
	return nearest

# True only if a straight line from our muzzle to the target is unobstructed —
# i.e. the first thing the ray hits is the target itself, not cover or a fellow
# enemy. Uses the same start/aim points as the actual shot, so what we check is
# what we'd fire.
func _has_clear_shot(target: Node3D) -> bool:
	var from := global_position + Vector3.UP * AIM_HEIGHT
	var to := target.global_position + Vector3.UP * AIM_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Only COVER (layer 2) and the player units themselves (Player layer 4) can
	# block a shot. We deliberately leave OUT fellow enemies (Enemy layer 8): our
	# projectiles pass straight through our own squad anyway (no friendly fire), so
	# a teammate in the line doesn't actually stop the shot. Counting them as
	# blockers made a crowd of enemies all refuse to fire on a cornered unit —
	# each one's view was "blocked" by the others.
	query.collision_mask = 2 | 4
	query.exclude = [get_rid()]           # never our own body
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	# Clear only if the very first thing the ray meets is the target.
	return hit and hit.collider == target

func _fire_at(target: Node3D) -> void:
	if projectile_scene == null:
		return
	var shot := projectile_scene.instantiate()
	# Add the shot to the running scene, NOT as our child — otherwise it would
	# ride along with us as we move instead of flying off on its own.
	get_tree().current_scene.add_child(shot)
	# Spawn at chest height and aim at the target's chest — matching the
	# line-of-sight check above, so what we cleared is what we fire.
	shot.global_position = global_position + Vector3.UP * AIM_HEIGHT
	shot.launch(target.global_position + Vector3.UP * AIM_HEIGHT)
