# menu_screen.gd — original main menu. Everything is code-built; typography is
# the default Godot UI font with a storm-dark palette (see BRAND_GUIDELINES.md).
class_name MenuScreen
extends Control


var game                                # GameRoot
var _queue_panel: Control
var _status: Label


func _init(g) -> void:
	game = g
	name = "MenuScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.09, 0.14)
	add_child(bg)

	var title := Label.new()
	title.text = "SKYFALL LEGENDS"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	title.position = Vector2(48, 44)
	add_child(title)

	var sub := Label.new()
	sub.text = "Online multiplayer battle royale — self-hosted sandbox"
	sub.add_theme_font_size_override("font_size", 18)
	sub.modulate = Color(0.75, 0.8, 0.86)
	sub.position = Vector2(52, 104)
	add_child(sub)

	# ---- left column: identity & roster
	var panel := Panel.new()
	panel.position = Vector2(48, 160)
	panel.size = Vector2(360, 380)
	add_child(panel)
	var name_l := _mk_label(Vector2(66, 178), "Callsign")
	var name_f := _mk_field(Vector2(66, 202), str(game.settings["name"]))
	name_f.text_changed.connect(func(t: String):
		game.update_settings_field("name", t)
	)
	var serv_l := _mk_label(Vector2(66, 244), "Server (host:port)")
	var serv_f := _mk_field(Vector2(66, 268), str(game.settings["server"]))
	serv_f.text_changed.connect(func(t: String):
		game.update_settings_field("server", t)
	)
	_mk_label(Vector2(66, 310), "Character")
	var cids := CharactersDB.all_ids()
	for i in cids.size():
		var b := Button.new()
		var ch: Dictionary = CharactersDB.get_character(cids[i])
		b.text = str(ch["name"])
		b.position = Vector2(66, 340 + i * 40)
		b.size = Vector2(320, 34)
		var cid: String = cids[i]
		b.pressed.connect(func():
			game.update_settings_field("char", cid)
			_status.text = "Character set to " + cid
		)
		add_child(b)

	# ---- right column: play modes
	var modes := [
		["PLAY SOLO", "solo", "queue"],
		["PLAY DUO (teams of 2)", "duo", "queue"],
		["PLAY SQUAD (teams of 3)", "squad", "queue"],
	]
	for i in modes.size():
		var b := Button.new()
		b.text = modes[i][0]
		b.position = Vector2(452, 170 + i * 54)
		b.size = Vector2(330, 44)
		var m: String = modes[i][1]
		b.pressed.connect(func(): game.ensure_connection("queue", m, "", false))
		add_child(b)
	var priv := Button.new()
	priv.text = "CREATE PRIVATE ROOM (solo/duo/squad)"
	priv.position = Vector2(452, 342)
	priv.size = Vector2(330, 44)
	priv.pressed.connect(func(): game.ensure_connection("private", "solo", "", true))
	add_child(priv)
	var code_l := _mk_label(Vector2(452, 396), "Room code")
	var code_f := _mk_field(Vector2(452, 420), "")
	var join := Button.new()
	join.text = "JOIN ROOM"
	join.position = Vector2(452, 456)
	join.size = Vector2(150, 40)
	join.pressed.connect(func(): game.ensure_connection("join", "solo", code_f.text, false))
	add_child(join)
	var practice := Button.new()
	practice.text = "LOCAL PRACTICE (bots, no server)"
	practice.position = Vector2(452, 524)
	practice.size = Vector2(330, 44)
	practice.pressed.connect(func(): game.practice_start("solo", true))
	add_child(practice)

	# sensitivity slider
	var sens := HSlider.new()
	sens.min_value = 0.3
	sens.max_value = 3.0
	sens.step = 0.05
	sens.value = float(game.settings["sensitivity"])
	sens.position = Vector2(452, 586)
	sens.size = Vector2(330, 24)
	sens.value_changed.connect(func(v: float): game.update_settings_field("sensitivity", v))
	add_child(sens)
	var sens_l := _mk_label(Vector2(452, 562), "Look sensitivity")
	add_child(sens_l)

	_status = Label.new()
	_status.position = Vector2(452, 624)
	_status.size = Vector2(400, 60)
	add_child(_status)

	# ---- connecting overlay
	_queue_panel = Panel.new()
	_queue_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_queue_panel.visible = false
	add_child(_queue_panel)
	var q := Label.new()
	q.text = "SEARCHING FOR PLAYERS…"
	q.add_theme_font_size_override("font_size", 30)
	q.position = Vector2(240, 300)
	_queue_panel.add_child(q)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.position = Vector2(430, 360)
	cancel.size = Vector2(180, 44)
	cancel.pressed.connect(func():
		game.net.back()
		_queue_panel.visible = false
	)
	_queue_panel.add_child(cancel)


func _mk_label(pos: Vector2, text: String) -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	add_child(l)
	return l


func _mk_field(pos: Vector2, text: String) -> LineEdit:
	var f := LineEdit.new()
	f.position = pos
	f.text = text
	f.size = Vector2(320, 34)
	add_child(f)
	return f


func refresh() -> void:
	_status.text = "Connected. PID %d" % game.self_pid
	_queue_panel.visible = false


func show_queue() -> void:
	_queue_panel.visible = true
