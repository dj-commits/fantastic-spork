extends Node3D

var m_delta: Vector2 # mouse delta
var m_pos: Vector2 # mouse position
var w_size: Vector2i # window size

var pan_edge_offset: int  = 100 # amount off of edge before panning action happens
var pan_speed: int = 6
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func _unhandled_input(event: InputEvent) -> void:

	if(event is InputEventMouseMotion): # no point in capturing if mouse isn't moving
		m_delta = event.relative
		m_pos = get_viewport().get_mouse_position()
		w_size = get_viewport().get_visible_rect().size
		


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	var mouse_pan := UserSettings.MousePanEnabled
	var m_pos := get_viewport().get_mouse_position()
	var w_size := get_viewport().get_visible_rect().size

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
		pan(dir.normalized() * pan_speed * delta)
	
func pan(direction: Vector3):
	global_position += direction
	#print(m_delta)
	#print(m_pos)
	#print(w_size)
		
