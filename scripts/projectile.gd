extends Area3D
# A single shot fired by an enemy. It flies in a straight line and damages the
# first thing it touches. Cover has no take_damage() method, so a shot simply
# stops against it — which is what makes cover actually protect your units.

## How fast the shot travels, in meters per second.
@export var speed: float = 22.0
## How much health it knocks off whatever it hits.
@export var damage: float = 20.0
## How long the shot may live before giving up and vanishing, in seconds. Stops
## missed shots from flying across the whole map forever.
@export var lifetime: float = 4.0

var _direction: Vector3 = Vector3.ZERO   # unit-length "which way we're flying"
var _age: float = 0.0                    # how long we've existed, in seconds

func _ready() -> void:
	# Let us know the moment we overlap a physics body (a unit or a cover box).
	body_entered.connect(_on_body_entered)

# Aim the shot at a point in the world. The enemy calls this right after spawning us.
func launch(target_position: Vector3) -> void:
	# Direction = "from here to the target", shrunk to length 1 so multiplying by
	# speed below gives a consistent travel rate no matter how far the target is.
	_direction = (target_position - global_position).normalized()

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	# Step forward: direction (length 1) * speed (m/s) * delta (seconds) = meters.
	global_position += _direction * speed * delta

func _on_body_entered(body: Node3D) -> void:
	# Units have a take_damage() method; cover does not. So a unit gets hurt, and
	# either way the shot is spent and removes itself.
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
