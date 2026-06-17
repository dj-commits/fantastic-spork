extends StaticBody3D
class_name Cover
# A piece of cover. On spawn it places its own cover spots — one just outside the
# middle of each vertical face — so units can stand against it with the cover
# between them and trouble.
#
# The spots are worked out from the collision box's size, so cover of ANY
# dimensions gets sensible spots automatically, with no hand-placed markers.

## How far outside each face (in meters) a unit stands when using this cover.
@export var stand_off: float = 0.8

func _ready() -> void:
	var shape: Shape3D = $CollisionShape3D.shape
	if shape is BoxShape3D:
		_create_cover_spots(shape.size)

func _create_cover_spots(box_size: Vector3) -> void:
	# half = distance from the cover's centre out to each face.
	var half := box_size * 0.5
	# One standing spot just past the centre of each of the four side faces
	# (+X, -X, +Z, -Z). We don't bother with the top/bottom faces.
	var offsets := [
		Vector3(half.x + stand_off, 0.0, 0.0),
		Vector3(-half.x - stand_off, 0.0, 0.0),
		Vector3(0.0, 0.0, half.z + stand_off),
		Vector3(0.0, 0.0, -half.z - stand_off),
	]
	for offset in offsets:
		var spot := CoverSpot.new()
		spot.position = offset       # local to us, so it rotates/moves with the cover
		add_child(spot)
