extends Node3D
class_name CoverSpot
# A single claimable standing position next to a piece of cover. Cover pieces
# create these around themselves at runtime (see cover.gd). At most one unit may
# claim a spot at a time, so units spread across different spots instead of all
# piling onto one.

var occupant: Node = null   # the unit currently holding this spot, or null if free

func _ready() -> void:
	# Join the group so any unit can find every cover spot with one lookup.
	add_to_group("cover_spots")

# Is this spot up for grabs? (A freed/destroyed occupant also counts as gone, so
# a spot never stays locked by a unit that no longer exists.)
func is_available() -> bool:
	return occupant == null or not is_instance_valid(occupant)

func claim(unit: Node) -> void:
	occupant = unit

# Give up the spot — but only if WE are the current holder, so a unit can't
# accidentally free a spot that someone else has since taken.
func release(unit: Node) -> void:
	if occupant == unit:
		occupant = null
