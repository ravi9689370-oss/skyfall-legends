# joystick_pad.gd — virtual movement stick. Touch-first; mouse drag works on
# desktop for quick testing. Reports a clamped, normalized vector on the HUD.
class_name JoystickPad
extends Control


var hud: Hud = null
var _touch_id := -1
var _start := Vector2.ZERO


func _ready() -> void:
	var area := Rect2(0, 0, 260, 260)
	custom_minimum_size = area.size
	position = Vector2(0, 0)
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	# leave generous thumb area
	offset_left = 0.0
	offset_top = -280.0
	offset_right = 280.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			_touch_id = event.index
			_start = event.position
		elif not event.pressed and event.index == _touch_id:
			_touch_id = -1
			if hud != null:
				hud.joystick_vec = Vector2.ZERO
	if event is InputEventScreenDrag and event.index == _touch_id:
		_apply(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_touch_id = 0
			_start = event.position
		elif _touch_id == 0:
			_touch_id = -1
			if hud != null:
				hud.joystick_vec = Vector2.ZERO
	elif event is InputEventMouseMotion and _touch_id == 0:
		_apply(event.position)


func _apply(at: Vector2) -> void:
	var v := at - _start
	var max_r := 64.0
	if v.length() > max_r:
		# recenter to follow the thumb
		_start = at - v.normalized() * max_r
		v = v.normalized() * max_r
	if hud != null:
		hud.joystick_vec = v / max_r
