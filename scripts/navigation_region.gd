extends NavigationRegion3D
# Builds the "navigation mesh" — the map of where units are allowed to walk —
# when the game starts. It scans this region's child geometry (the ground plane
# and the cover boxes) and produces a walkable surface with the cover carved out.
#
# We build it at runtime instead of storing a pre-baked mesh in the scene file.
# That keeps the scene simple and means the walkable area always matches whatever
# cover is currently in the level, with no manual "re-bake" step to forget.
#
# It ALSO scatters random cover across the field first, so the navmesh is carved
# around everything we drop.

# The cover types we scatter, each with the y-offset that rests it on the ground
# (= half its height). Only pieces that work as standing cover are listed.
const COVER_TYPES := [
	{ "scene": preload("res://scenes/full_cover.tscn"), "rest_y": 1.0 },
	{ "scene": preload("res://scenes/cover_2x2x2.tscn"), "rest_y": 1.0 },
	{ "scene": preload("res://scenes/cover_4x4x4.tscn"), "rest_y": 2.0 },
]

## How many cover pieces to scatter across the battlefield.
@export var cover_count: int = 30
## Half-size (x, z) of the rectangular area the cover is scattered within.
@export var scatter_area := Vector2(24.0, 32.0)
## Smallest allowed gap (meters) between scattered pieces, so it isn't crowded.
@export var min_cover_spacing: float = 6.0

func _ready() -> void:
	_scatter_cover()                 # drop random cover BEFORE we bake the navmesh
	var nav_mesh := NavigationMesh.new()

	# agent_radius = how wide we pretend each unit is while planning paths. The
	# walkable area is shrunk inward by this much around every wall, so a unit's
	# CENTRE never plans closer than this to an obstacle.
	#
	# Sizing matters here: the two cover walls leave a 1.0m gap between them
	# (each is 3m long, placed 4m apart -> facing edges at z=1.5 and z=2.5). A
	# radius of 0.5 would eat 0.5m off each side (0.5 + 0.5 = 1.0) and close the
	# gap completely. The pawn is really only 0.3 wide, so we use 0.25 — that
	# leaves a ~0.5m corridor down the middle: wide enough for one unit to slip
	# through single-file, too narrow for two side-by-side.
	#
	# (0.25 also lines up with cell_size below, so the erosion rounds to exactly
	# one cell. 0.3 would round UP to two cells and shut the gap again.)
	nav_mesh.set_agent_radius(0.25)
	nav_mesh.set_agent_height(1.8)

	# cell_size = the resolution of the scan. Smaller is more accurate but slower
	# to build; 0.25m is plenty for a level this size.
	nav_mesh.set_cell_size(0.25)
	nav_mesh.set_cell_height(0.25)

	# Build the walkable area from the *visible meshes* of this region's children
	# (the ground plane and cover boxes), rather than their collision shapes.
	nav_mesh.set_parsed_geometry_type(NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES)
	nav_mesh.set_source_geometry_mode(NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN)

	navigation_mesh = nav_mesh

	# false = bake right now, on the main thread, so the path data is ready
	# before any unit asks for a route. The level is small, so this is fast.
	bake_navigation_mesh(false)

# Randomly drop cover across the field, keeping pieces from bunching up. Runs
# before the bake so the navmesh is carved around everything we place.
func _scatter_cover() -> void:
	var placed: Array[Vector3] = []
	var attempts := 0
	var max_attempts := cover_count * 20    # give up eventually if it's too tight
	while placed.size() < cover_count and attempts < max_attempts:
		attempts += 1
		var spot := Vector3(
			Rng.roll_range(-scatter_area.x, scatter_area.x),
			0.0,
			Rng.roll_range(-scatter_area.y, scatter_area.y))
		if _too_close(spot, placed):
			continue
		placed.append(spot)
		_spawn_cover(spot)

# True if "spot" sits within min_cover_spacing of any piece we've already placed.
func _too_close(spot: Vector3, placed: Array[Vector3]) -> bool:
	for other in placed:
		if other.distance_to(spot) < min_cover_spacing:
			return true
	return false

func _spawn_cover(ground_spot: Vector3) -> void:
	# Pick a random cover type, rest it on the ground, and turn it a random way
	# so the field doesn't look like a grid. Adding it as our child means the
	# bake includes it and its cover-spot markers register themselves.
	var type: Dictionary = COVER_TYPES[Rng.roll_int(0, COVER_TYPES.size() - 1)]
	var piece: Node3D = type["scene"].instantiate()
	add_child(piece)
	piece.position = ground_spot + Vector3.UP * float(type["rest_y"])
	piece.rotation.y = Rng.roll_range(0.0, TAU)
