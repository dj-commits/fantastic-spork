extends Marker3D
class_name CoverSpot
# A single spot a unit can stand to take cover. These live on the edge markers
# of a cover piece. At most one unit may "claim" a spot at a time, so units
# naturally spread across different spots instead of all piling onto one.
#
# This is the first building block of the bigger unit-intelligence system: a
# claimable point in the world that a behaviour (here, "seek cover") can reserve.

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
