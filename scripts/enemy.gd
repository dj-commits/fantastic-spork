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

	var target := _nearest_player_unit()
	if target != null:
		# Distance to the target, measured flat along the ground.
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		var distance := to_target.length()

		# Can we actually SEE the target, or is cover / a fellow enemy in the way?
		var clear_shot := _has_clear_shot(target)

		# Hold still only when we're in range AND have a clear shot. Otherwise keep
		# moving — either to close the distance or to step around the obstruction.
		if distance <= firing_range and clear_shot:
			move_to(global_position)          # in range with a clear shot — hold
		else:
			move_to(target.global_position)   # advance / reposition for a shot

		# Fire only with a clear shot in range, so we never plug rounds into cover.
		if clear_shot and distance <= sight_range and _time_until_next_shot <= 0.0:
			_fire_at(target)
			_time_until_next_shot = fire_cooldown
	else:
		move_to(global_position)              # no player units left — stand down

	# Hand off to the inherited Pawn movement, which actually walks us toward
	# whatever move_to() target we just set (and applies gravity, etc.).
	super._physics_process(delta)

# The closest player unit anywhere on the map, or null if they're all gone. No
# sight limit — enemies hunt the squad across the whole field; sight_range only
# decides whether we actually open fire (see _physics_process).
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
	var from := global_position + Vector3.UP * 1.0
	var to := target.global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Anything that could block the shot: cover (layer 2), other units
	# (Enemy layer 8), and the player units we're aiming at (Player layer 4)...
	query.collision_mask = 2 | 8 | 4
	query.exclude = [get_rid()]           # ...but never our own body.
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
	# Spawn around chest height and aim at the target's chest.
	shot.global_position = global_position + Vector3.UP * 1.0
	shot.launch(target.global_position + Vector3.UP * 0.9)
