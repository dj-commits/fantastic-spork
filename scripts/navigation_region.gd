extends NavigationRegion3D
# Builds the "navigation mesh" — the map of where units are allowed to walk —
# when the game starts. It scans this region's child geometry (the ground plane
# and the cover boxes) and produces a walkable surface with the cover carved out.
#
# We build it at runtime instead of storing a pre-baked mesh in the scene file.
# That keeps the scene simple and means the walkable area always matches whatever
# cover is currently in the level, with no manual "re-bake" step to forget.

func _ready() -> void:
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
