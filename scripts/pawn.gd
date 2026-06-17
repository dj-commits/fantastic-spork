extends CharacterBody3D
# A single selectable RTS unit.
# The selection system (selection.gd) calls set_selected() to highlight us and
# move_to() to give us a destination. We handle the actual walking ourselves.

@onready var selection_ring: MeshInstance3D = $SelectionRing

const MOVE_SPEED: float = 4.0       # how fast we walk, in meters per second
const STOP_DISTANCE: float = 0.2    # "close enough" to the target — stop fidgeting
const GRAVITY: float = 20.0         # downward pull so we stay stuck to the ground

var is_selected: bool = false
var has_move_order: bool = false    # true while we're walking toward move_target
var move_target: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Join the "units" group so the selection system can find every unit at once.
	add_to_group("units")
	set_selected(false)             # start unselected (ring hidden)

# Highlight / un-highlight this unit. Called by the selection system.
func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value

# Give this unit a place to walk to. Called when the player right-clicks ground.
func move_to(world_point: Vector3) -> void:
	move_target = world_point
	has_move_order = true

func _physics_process(delta: float) -> void:
	# Assume we don't want to move sideways this frame unless we have an order.
	var walk := Vector3.ZERO
	if has_move_order:
		# Vector pointing from us to the target. We zero out the up/down part
		# (y) so we only ever walk along the flat ground, never try to fly.
		var to_target := move_target - global_position
		to_target.y = 0.0
		if to_target.length() > STOP_DISTANCE:
			# normalized() gives a length-1 "pure direction"; multiplying by
			# MOVE_SPEED turns it into "this direction, at walking speed".
			walk = to_target.normalized() * MOVE_SPEED
		else:
			has_move_order = false  # we've arrived — drop the order and stop
	# Keep our chosen sideways speed, and always pull downward with gravity.
	velocity.x = walk.x
	velocity.z = walk.z
	velocity.y -= GRAVITY * delta
	move_and_slide()
	# Once we're resting on the floor, reset downward speed to zero so gravity
	# doesn't keep adding up to a silly large number frame after frame.
	if is_on_floor():
		velocity.y = 0.0
