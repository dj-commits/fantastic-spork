extends Pawn
# An enemy unit. It reuses ALL of Pawn's combat, health and navigation, and only
# changes two things:
#   1. it fights the player's "units" (not "enemies"), and
#   2. it HUNTS — advancing on its target and only holding once in firing range,
#      whereas player units stay put / take cover and shoot opportunistically.

## Once this close to its target, the enemy stops advancing and just shoots.
@export var firing_range: float = 9.0

# Fight the player's units instead of the enemy team, aiming shots at the Player
# physics layer.
func _register_team() -> void:
	add_to_group("enemies")
	enemy_group = "units"
	target_layer = 4                # Player physics layer

# Roll firing_range too, on top of the stats Pawn already rolls.
func _roll_stats() -> void:
	super._roll_stats()
	firing_range = Rng.roll_variance(firing_range, stat_variance)

# Hunt: advance on whatever target the base brain handed us, holding once we're
# inside firing range. If we can't see anyone, push toward the nearest unit
# anyway so the across-the-map pursuit keeps going.
func _decide_movement(target: Node3D) -> void:
	if target != null:
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() <= firing_range:
			move_to(global_position)          # in range — hold and shoot
		else:
			move_to(target.global_position)   # close in
	else:
		var prey := _nearest_enemy()
		if prey != null:
			move_to(prey.global_position)
		else:
			move_to(global_position)          # nobody left — stand down
