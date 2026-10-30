# results_screen.gd — match results table (placement, kills, damage) locally
# augmenting server rows with your own saved stats.
class_name ResultScreen
extends Control


var game                                  # GameRoot
var _rows_l: Label
var _win_l: Label


func _init(g) -> void:
	game = g
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.08, 0.13)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	_win_l = Label.new()
	_win_l.add_theme_font_size_override("font_size", 46)
	_win_l.position = Vector2(64, 64)
	add_child(_win_l)
	_rows_l = Label.new()
	_rows_l.add_theme_font_size_override("font_size", 20)
	_rows_l.position = Vector2(64, 140)
	_rows_l.size = Vector2(700, 420)
	add_child(_rows_l)
	var menu := Button.new()
	menu.text = "BACK TO MENU"
	menu.position = Vector2(64, 580)
	menu.size = Vector2(240, 48)
	menu.pressed.connect(func():
		visible = false
		game.return_to_menu()
	)
	add_child(menu)


func apply(rows: Dictionary) -> void:
	var winner := int(rows.get("winner_team", -1))
	if winner >= 0 and int(rows.get("winner_team", -1)) != 255:
		_win_l.text = "TEAM VICTORY"
	else:
		_win_l.text = "MATCH ENDED"
	var lines := ["PLACEMENT  KILLS   DAMAGE   PLAYER"]
	for r in rows.get("rows", []):
		lines.append("#%d   %d      %d      %s%s" % [
			int(r.get("placement", 99)),
			int(r.get("kills", 0)),
			int(r.get("dmg", 0)),
			str(r.get("name", "?")),
			" (you)" if int(r.get("pid", 0)) == game.self_pid else "",
		])
	_rows_l.text = "\n".join(lines)
