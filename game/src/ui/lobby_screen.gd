# lobby_screen.gd — pre-match lobby: code, roster (ready/team/bots), countdown
# and readiness actions.
class_name LobbyScreen
extends Control


var game                                 # GameRoot
var _code_l: Label
var _mode_l: Label
var _players_l: Label
var _timer_l: Label
var _ready_state := false
var _info := {}


func _init(g) -> void:
	game = g
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.1, 0.15)
	add_child(bg)
	var title := Label.new()
	title.text = "LOBBY"
	title.add_theme_font_size_override("font_size", 40)
	title.position = Vector2(64, 56)
	add_child(title)
	_code_l = _label(Vector2(64, 112), "CODE —")
	_mode_l = _label(Vector2(64, 142), "MODE —")
	_players_l = _label(Vector2(64, 176), "PLAYERS")
	_players_l.add_theme_font_size_override("font_size", 24)
	_timer_l = _label(Vector2(64, 470), "starting soon")
	var readyBtn := Button.new()
	readyBtn.text = "READY / UNREADY"
	readyBtn.position = Vector2(64, 512)
	readyBtn.size = Vector2(220, 48)
	readyBtn.pressed.connect(func():
		_ready_state = not _ready_state
		game.net.set_ready(_ready_state, str(game.settings["char"]))
	)
	add_child(readyBtn)
	var leave := Button.new()
	leave.text = "LEAVE"
	leave.position = Vector2(300, 512)
	leave.size = Vector2(150, 48)
	leave.pressed.connect(func():
		_ready_state = false
		game.net.back()
		game.return_to_menu()
	)
	add_child(leave)


func _label(pos: Vector2, text: String) -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	add_child(l)
	return l


func apply(info: Dictionary) -> void:
	_info = info
	_code_l.text = "CODE  " + str(info.get("code", ""))
	_mode_l.text = "MODE  " + str(info.get("mode", ""))
	if float(info.get("start_in", 0.0)) > 0.0:
		_timer_l.text = "start in %.0f s" % float(info["start_in"])
	else:
		_timer_l.text = "waiting for everyone to be READY"
	var rows: Array = info.get("players", [])
	var parts := ["ROSTER (%d)" % rows.size()]
	for p in rows:
		var s := "  %s — %s%s | team %d %s" % [
			str(p["name"]),
			str(p["char"]),
			" [BOT]" if bool(p.get("bot", false)) else "",
			int(p.get("team", 0)),
			"✔ ready" if bool(p.get("ready", false)) else "✗ not ready",
		]
		parts.append(s)
	_players_l.text = "\n".join(parts)
