extends Node
# The game's single shared random-number generator — think of it as "the dice"
# that everything rolls through. Instead of each script making its own random
# generator, they all call this one. That buys us two things:
#   1. ONE place to set the seed, so we can replay the exact same run when
#      hunting a bug (set randomize_on_start = false and pick a fixed_seed).
#   2. A consistent, readable set of "roll" helpers used everywhere.
#
# Registered as an autoload (see project.godot), so any script can just write
# Rng.roll_variance(...) without needing a reference to it.

# Set to false (and choose a fixed_seed) to make every run roll identically —
# very handy for debugging. Left true, each launch is freshly unpredictable.
var randomize_on_start: bool = true
# The seed used when randomize_on_start is false. Same seed = same rolls.
var fixed_seed: int = 12345

# The actual generator we wrap. The underscore marks it as "internal" — other
# scripts should use the helper methods below rather than poke at it directly.
var _generator := RandomNumberGenerator.new()

func _ready() -> void:
	if randomize_on_start:
		_generator.randomize()       # grab an unpredictable seed from the system
	else:
		_generator.seed = fixed_seed

# THE workhorse for "alive" variance. Returns a value near "base", nudged up or
# down at random. "spread" is a fraction: 0.15 means "within 15% either way".
# e.g. roll_variance(16.0, 0.15) gives something between 13.6 and 18.4.
func roll_variance(base: float, spread: float) -> float:
	# randf_range picks any number between the two bounds, all equally likely.
	var factor := _generator.randf_range(1.0 - spread, 1.0 + spread)
	return base * factor

# A plain random number between minimum and maximum, if you want a raw roll
# rather than a nudge around a base value.
func roll_range(minimum: float, maximum: float) -> float:
	return _generator.randf_range(minimum, maximum)

# A whole-number roll between minimum and maximum, both ends included.
# e.g. roll_int(1, 6) is a six-sided die; roll_int(0, n - 1) picks a list index.
func roll_int(minimum: int, maximum: int) -> int:
	return _generator.randi_range(minimum, maximum)

# Returns true "probability" of the time. chance(0.25) is true about 1 time in 4.
# Handy for "does this happen?" decisions (a stagger, a miss, a bark, etc.).
func chance(probability: float) -> bool:
	return _generator.randf() < probability
