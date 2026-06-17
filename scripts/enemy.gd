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

		if distance > firing_range:
			move_to(target.global_position)   # too far — advance toward them
		else:
			move_to(global_position)          # close enough — hold position

		if _time_until_next_shot <= 0.0:
			_fire_at(target)
			_time_until_next_shot = fire_cooldown
	else:
		move_to(global_position)              # nobody in sight — stand still

	# Hand off to the inherited Pawn movement, which actually walks us toward
	# whatever move_to() target we just set (and applies gravity, etc.).
	super._physics_process(delta)

# The closest player unit within sight_range, or null if none are near enough.
func _nearest_player_unit() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := sight_range     # ignore anything beyond our sight
	for unit in get_tree().get_nodes_in_group("units"):
		var distance := global_position.distance_to(unit.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = unit
	return nearest

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
