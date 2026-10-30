# look_pad.gd — full-screen drag surface for touch look (camera) input.
# Runs behind every HUD button; only consumes touches that start when no other
# control already grabbed the pointer.
class_name LookPad
extends Control


var hud: Hud = null
var _look_id := -1
var _last := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _look_id == -1:
			_look_id = event.index
			_last = event.position
		elif not event.pressed and event.index == _look_id:
			_look_id = -1
	if event is InputEventScreenDrag and event.index == _look_id:
		if hud != null:
			hud._look_delta += event.position - _last
		_last = event.position
	# Desktop look is handled by captured mouse in FpsController.
