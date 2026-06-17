extends Node3D
@onready var camera: Camera3D = $Camera3D
var m_delta: Vector2 = Vector2.ZERO   # mouse delta — accumulated, consumed per frame
var m_pos: Vector2                    # mouse position
var w_size: Vector2i                  # window size
var pan_edge_offset: int = 100        # px from edge before panning kicks in
var pan_speed: int = 6
# --- Orbit state ---
var cam_yaw: float = 0.0              # degrees, unclamped (full 360 spin)
var cam_pitch: float = 50.0          # degrees, clamped
const PITCH_MIN: float = 30.0
const PITCH_MAX: float = 80.0
var rotate_speed: float = 0.3        # degrees per pixel of mouse movement
# --- Zoom state ---
var orbit_distance: float = 12.0     # R — camera's current distance from focus point F
const ZOOM_MIN: float = 4.0          # closest to F
const ZOOM_MAX: float = 30.0         # farthest from F
const ZOOM_STEP: float = 1.5         # distance change per wheel notch
func _ready() -> void:
	# Rig owns all rotation — apply starting angles once so the opening
	# view matches cam_pitch/cam_yaw instead of snapping on first drag.
	rotation = Vector3(deg_to_rad(-cam_pitch), deg_to_rad(cam_yaw), 0.0)
	camera.position.z = orbit_distance   # script owns R; overrides inspector Z
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		m_delta += event.relative      # accumulate — several motion events can fire per frame
		m_pos = get_viewport().get_mouse_position()
		w_size = get_viewport().get_visible_rect().size
	if event.is_action_pressed("cam_zoom_in"):
		_zoom(-ZOOM_STEP)
	elif event.is_action_pressed("cam_zoom_out"):
		_zoom(ZOOM_STEP)
func _process(delta: float) -> void:
	_process_pan(delta)
	_process_rotation(delta)
func _process_pan(delta: float) -> void:
	var dir := Vector3.ZERO
	var mouse_pan: bool = UserSettings.MousePanEnabled
	# Vertical
	if Input.is_action_pressed("cam_pan_up") or (mouse_pan and m_pos.y <= pan_edge_offset):
		dir.z -= 1
	elif Input.is_action_pressed("cam_pan_down") or (mouse_pan and m_pos.y >= w_size.y - pan_edge_offset):
		dir.z += 1
	# Horizontal
	if Input.is_action_pressed("cam_pan_left") or (mouse_pan and m_pos.x <= pan_edge_offset):
		dir.x -= 1
	elif Input.is_action_pressed("cam_pan_right") or (mouse_pan and m_pos.x >= w_size.x - pan_edge_offset):
		dir.x += 1
	if dir != Vector3.ZERO:
		dir = dir.rotated(Vector3.UP, deg_to_rad(cam_yaw))
		pan(dir.normalized() * pan_speed * delta)
func _process_rotation(_delta: float) -> void:
	if Input.is_action_pressed("rotate_cam"):
		cam_yaw -= m_delta.x * rotate_speed
		cam_pitch = clampf(cam_pitch + m_delta.y * rotate_speed, PITCH_MIN, PITCH_MAX)
	# Absolute set every frame; default YXZ Euler order = clean turntable orbit
	rotation = Vector3(deg_to_rad(-cam_pitch), deg_to_rad(cam_yaw), 0.0)
	m_delta = Vector2.ZERO             # consume accumulated delta, every frame
func pan(direction: Vector3) -> void:
	global_position += direction
func _zoom(amount: float) -> void:
	orbit_distance = clampf(orbit_distance + amount, ZOOM_MIN, ZOOM_MAX)
	camera.position.z = orbit_distance
