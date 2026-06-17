extends Node

var MousePanEnabled: bool
# When true, double-tapping a control-group number key clears the whole
# selection. When false, a second tap just re-selects the group again.
var DoubleTapDeselectEnabled: bool

func _ready() -> void:
	MousePanEnabled = false
	DoubleTapDeselectEnabled = true
