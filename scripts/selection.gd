extends Control
# RTS-style unit selection and move orders.
#
# This lives on a screen-filling Control so it can DRAW the drag-selection box
# on top of the 3D view. Its mouse_filter is set to "Ignore" in the scene, so
# the Control never swallows clicks — it's purely a canvas to draw on. All the
# actual input is read below in _unhandled_input.
#
# How it works for the player:
#   * Left-click a unit         -> select just that unit
#   * Left-click empty ground   -> clear the selection
#   * Left-click + drag a box   -> select every unit inside the box
#   * Right-click ground        -> send the selected units there
#   * Ctrl + number (1-9, 0)    -> move selected units into that group only
#                                  (or toggle them out if already in it)
#   * Ctrl+Shift + number       -> ALSO add them to that group (keep them in
#                                  any other groups too — StarCraft style)
#   * number (1-9, 0)           -> re-select everything in that group

# How far (in pixels) the mouse must move before we count it as a drag rather
# than a click. Stops a tiny hand-wobble from turning a click into a box select.
const DRAG_THRESHOLD: float = 8.0

# Gap (in meters) between units when a group arrives at a destination, so they
# spread out into a little grid instead of stacking on the exact same spot.
const FORMATION_SPACING: float = 1.2

var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO  # screen point where the left button went down
var drag_now: Vector2 = Vector2.ZERO    # where the mouse is right now while dragging

# Two presses of the same number key closer together than this (in seconds)
# count as a "double tap". 0.3s is a comfortable, not-too-twitchy window.
const DOUBLE_TAP_TIME: float = 0.3
var last_tap_digit: int = -1            # which group number was tapped last (-1 = none)
var last_tap_time: float = 0.0          # when that tap happened, in seconds

func _unhandled_input(event: InputEvent) -> void:
	# --- Left button pressed: begin a (possible) box selection ---
	if event.is_action_pressed("select"):
		is_dragging = true
		drag_start = get_viewport().get_mouse_position()
		drag_now = drag_start
	# --- Left button released: decide click vs box, then select ---
	elif event.is_action_released("select") and is_dragging:
		_finish_selection()
		is_dragging = false
		queue_redraw()                  # wipe the drawn box off the screen
	# --- Mouse moved while dragging: grow the box ---
	elif event is InputEventMouseMotion and is_dragging:
		drag_now = get_viewport().get_mouse_position()
		queue_redraw()
	# --- Right button pressed: order the selected units to move ---
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_issue_move_order(event.position)
	# --- Number keys: save / recall control groups (see _handle_group_key) ---
	# Ignore "echo" events, which fire repeatedly while a key is held down.
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_group_key(event)

# --- Selection -------------------------------------------------------------

func _finish_selection() -> void:
	var box := _drag_rect()
	# A box smaller than the threshold in BOTH directions means the player
	# really just clicked. Otherwise treat it as a drag-box.
	if box.size.x < DRAG_THRESHOLD and box.size.y < DRAG_THRESHOLD:
		_select_single(drag_start)
	else:
		_select_in_box(box)

# Click select: pick the one unit directly under the cursor (if any).
func _select_single(screen_pos: Vector2) -> void:
	var hit := _raycast(screen_pos, 4)  # collision layer 4 = "Player" units
	var clicked_unit: Node = null
	if hit and hit.collider.is_in_group("units"):
		clicked_unit = hit.collider
	# Turn on only the clicked unit; everything else turns off. Clicking empty
	# space leaves clicked_unit as null, which clears the whole selection.
	for unit in get_tree().get_nodes_in_group("units"):
		unit.set_selected(unit == clicked_unit)

# Box select: select every unit whose on-screen position is inside the box.
func _select_in_box(box: Rect2) -> void:
	var camera := get_viewport().get_camera_3d()
	for unit in get_tree().get_nodes_in_group("units"):
		# unproject_position() asks the camera "where on the screen does this
		# 3D point appear?". We then just check if that screen point is in the box.
		var screen_pos := camera.unproject_position(unit.global_position)
		# Skip units behind the camera — their projected point is meaningless.
		var behind := camera.is_position_behind(unit.global_position)
		unit.set_selected(not behind and box.has_point(screen_pos))

# Build a rectangle from the two drag corners, no matter which way we dragged
# (min() = top-left corner, max() = bottom-right corner).
func _drag_rect() -> Rect2:
	var top_left := drag_start.min(drag_now)
	var bottom_right := drag_start.max(drag_now)
	return Rect2(top_left, bottom_right - top_left)

# --- Move orders -----------------------------------------------------------

func _issue_move_order(screen_pos: Vector2) -> void:
	var hit := _raycast(screen_pos, 1)  # collision layer 1 = "Ground"
	if not hit:
		return                          # right-clicked off the map — ignore
	var selected := _selected_units()
	var targets := _formation_points(hit.position, selected.size())
	for i in selected.size():
		# order_move_to (not move_to) so the unit drops any cover it had claimed
		# — a manual order should override the unit's own cover-seeking.
		selected[i].order_move_to(targets[i])

func _selected_units() -> Array:
	var result: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.is_selected:
			result.append(unit)
	return result

# Spread "count" units into a roughly square grid centered on "center", so a
# group doesn't all aim for one point. Example: 9 units -> a 3x3 grid.
func _formation_points(center: Vector3, count: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	# How many units per row. sqrt(9)=3, sqrt(10)≈3.16 -> ceil -> 4, etc.
	var columns := int(ceil(sqrt(count)))
	for i in count:
		var col := i % columns          # which column this unit sits in
		@warning_ignore("integer_division")
		var row := i / columns          # which row (integer division, on purpose)
		# Subtracting (columns-1)*0.5 shifts the grid so it's centered on the
		# target point rather than starting at one corner.
		var offset_x := (col - (columns - 1) * 0.5) * FORMATION_SPACING
		var offset_z := (row - (columns - 1) * 0.5) * FORMATION_SPACING
		points.append(center + Vector3(offset_x, 0.0, offset_z))
	return points

# --- Control groups --------------------------------------------------------
#
# A "control group" is a saved selection you can bring back later with one key.
# We store each group as a real Godot node-group named "control_group_<digit>".
# The nice side effect: if a unit is ever destroyed, Godot removes it from its
# node-groups automatically, so a control group can never point at a unit that
# no longer exists.
#
# A unit is ALLOWED to belong to several groups at once, but it only happens
# when the player asks for it (Ctrl+Shift). The plain Ctrl assignment instead
# MOVES units into a group (clearing their old ones), so you never get overlap
# by accident.

# The shared start of every control-group name, e.g. "control_group_2".
const GROUP_PREFIX := "control_group_"

func _handle_group_key(event: InputEventKey) -> void:
	# We only care about the top-row number keys 1-9 and 0. We read the
	# PHYSICAL key (its position on the keyboard) rather than the letter it
	# types, so this still works on keyboard layouts where that row isn't
	# digits. KEY_0..KEY_9 are consecutive codes, so subtracting KEY_0 turns
	# the key into the plain digit (0-9) it sits on.
	var key := event.physical_keycode
	if key < KEY_0 or key > KEY_9:
		return
	var digit := key - KEY_0
	if event.ctrl_pressed and event.shift_pressed:
		_add_to_group(digit)    # Ctrl+Shift -> add, allowed in several groups
	elif event.ctrl_pressed:
		_assign_group(digit)    # Ctrl       -> move into this group only
	else:
		_tap_group(digit)       # no Ctrl    -> select the group (or double-tap)

# Ctrl+Shift assignment: add the selected units to group "digit" WITHOUT
# removing them from any other group. This is the StarCraft-style behaviour
# where one unit can sit in several control groups at once. Because it only
# runs when the player deliberately holds Shift, the "splitting" overlap can
# never happen by accident.
func _add_to_group(digit: int) -> void:
	var group := _group_name(digit)
	for unit in _selected_units():
		unit.add_to_group(group)    # harmless if the unit is already a member

# Ctrl assignment: each selected unit MOVES into group "digit" (toggling out
# if it's already in it). "Move" means it leaves whatever group it was in.
func _assign_group(digit: int) -> void:
	var group := _group_name(digit)
	for unit in _selected_units():
		if unit.is_in_group(group):
			unit.remove_from_group(group)   # already in THIS group -> subtract
		else:
			# A unit can only be in one control group, so first take it out of
			# any group it was already in, then add it to this one. This is what
			# makes "splitting units off into a new group" leave the old group.
			_clear_control_groups(unit)
			unit.add_to_group(group)
	# Note: one selected unit is enough — that simply makes a group of one.

# Remove a unit from every control group it currently belongs to. We leave all
# its other node-groups (like "units") alone — only the control-group tags go.
func _clear_control_groups(unit: Node) -> void:
	for group_name in unit.get_groups():
		if String(group_name).begins_with(GROUP_PREFIX):
			unit.remove_from_group(group_name)

# Re-select every unit saved in group "digit" (and deselect everything else).
func _recall_group(digit: int) -> void:
	var group := _group_name(digit)
	# If nothing has been saved to this group yet, leave the current selection
	# untouched instead of clearing it (matches how most RTS games behave).
	if get_tree().get_nodes_in_group(group).is_empty():
		return
	for unit in get_tree().get_nodes_in_group("units"):
		unit.set_selected(unit.is_in_group(group))

# Handle a number key tapped WITHOUT Ctrl. A single tap recalls the group; a
# quick second tap of the same number can instead clear the whole selection,
# but only if the player has switched that option on in UserSettings.
func _tap_group(digit: int) -> void:
	# Time.get_ticks_msec() is the milliseconds since the game started; dividing
	# by 1000 turns it into seconds so it matches DOUBLE_TAP_TIME.
	var now := Time.get_ticks_msec() / 1000.0
	# A double tap = same number as last time, AND soon enough after it.
	var is_double_tap := digit == last_tap_digit and (now - last_tap_time) <= DOUBLE_TAP_TIME
	last_tap_digit = digit
	last_tap_time = now

	# This is the "feature flag" check — same idea as UserSettings.MousePanEnabled.
	if is_double_tap and UserSettings.DoubleTapDeselectEnabled:
		last_tap_digit = -1     # reset so a third tap isn't read as another double
		_deselect_all()
		return
	_recall_group(digit)

func _deselect_all() -> void:
	for unit in get_tree().get_nodes_in_group("units"):
		unit.set_selected(false)

func _group_name(digit: int) -> StringName:
	return GROUP_PREFIX + str(digit)

# --- Shared helpers --------------------------------------------------------

# Shoot a ray from the camera through a screen point and return what it hits.
# layer_mask picks WHICH things the ray can hit (which collision layers).
# Returns an empty Dictionary (which counts as "false") if nothing was hit.
func _raycast(screen_pos: Vector2, layer_mask: int) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = layer_mask
	return space.intersect_ray(query)

func _draw() -> void:
	if not is_dragging:
		return
	var box := _drag_rect()
	draw_rect(box, Color(0.3, 0.8, 0.3, 0.15))        # translucent green fill
	draw_rect(box, Color(0.4, 1.0, 0.4, 0.8), false)  # solid green outline
