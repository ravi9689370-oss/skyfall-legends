# game_root.gd — client app state machine. Owns the NetClient, the (optional)
# embedded practice server, all screens, and the live MatchWorld. Scene flow:
# MENU -> (connect) -> QUEUE/LOBBY -> MATCH -> RESULTS -> MENU.
class_name GameRoot
extends Node


const SETTINGS_PATH := "user://skyfall_settings.cfg"

var net: NetClient                       # active client-side networking
var practice_srv: NetServer = null       # only used in local practice
var match_world: MatchWorld = null
var hud: Hud = null

var settings := {
	"name": "Skyfarer",
	"char": "ranger",
	"server": "127.0.0.1:7777",
	"sensitivity": 1.0,
	"bots": 7,
	"volume": 0.8,
}
var self_pid := 0
var self_team := 0
var self_char := "ranger"
var slot_mirror := 2
var pending_mode := "solo"
var pending_join_code := ""
var pending_private := false
var spectate_pid := 0
var already_started := false

var menu: MenuScreen
var lobby: LobbyScreen
var results: ResultScreen
var toast_label: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_load_settings()
	net = NetClient.new()
	net.hello_ok.connect(_on_hello_ok)
	net.lobby_state.connect(_on_lobby_state)
	net.lobby_msg.connect(_on_lobby_msg)
	net.match_started.connect(_on_match_started)
	net.snapshot.connect(_on_snapshot)
	net.match_event.connect(_on_match_event)
	net.match_end.connect(_on_match_end)
	net.closed.connect(_on_closed)
	if not already_started:
		menu = MenuScreen.new(self)
		add_child(menu)
		lobby = LobbyScreen.new(self)
		lobby.visible = false
		add_child(lobby)
		results = ResultScreen.new(self)
		results.visible = false
		add_child(results)
		already_started = true
	toast_label = Label.new()
	toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.position = Vector2(0, -40)
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.modulate = Color(1, 0.9, 0.5)
	add_child(toast_label)


func _process(_delta: float) -> void:
	# practice mode drives a private multiplayer api; poll it manually here
	if practice_srv != null and practice_srv_api != null:
		practice_srv_api.poll()


func _toast(msg: String) -> void:
	toast_label.text = msg
	var tw := create_tween()
	tw.tween_property(toast_label, "modulate:a", 0.0, 2.0).set_delay(1.0)


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings.keys():
			settings[k] = cf.get_value("s", k, settings[k])


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("s", k, settings[k])
	cf.save(SETTINGS_PATH)


# ------------------------------------------------------------------ connect

func _host_port() -> Array:
	var raw := String(settings["server"]).strip_edges()
	if raw == "":
		return ["127.0.0.1", 7777]
	var parts := raw.split(":")
	var host: String = "127.0.0.1"
	var port := 7777
	if parts.size() >= 1 and parts[0] != "":
		host = parts[0]
	if parts.size() >= 2:
		port = int(parts[1])
	return [host, port]


func ensure_connection(kind: String, mode: String, code: String, priv: bool) -> void:
	pending_mode = mode
	pending_join_code = code
	pending_private = priv
	if net.connected and net.my_pid != 0:
		_dispatch_kind()
	else:
		var hp := _host_port()
		var err := net.connect_to(hp[0], int(hp[1]), str(settings["name"]), str(settings["char"]))
		if err != "":
			_toast("Connect error: %s" % err)


func practice_start(mode: String, bot_fill: bool) -> void:
	# Local sandbox: spin up this very process as the server, join via loopback.
	practice_cleanup()
	practice_srv = NetServer.new()
	add_child(practice_srv)
	var port := randi_range(27700, 27800)
	var err := practice_srv.start({
		"port": port,
		"bot_fill": bot_fill,
		"max_clients": 16,
	})
	if err != "":
		_toast("Practice server failed: " + err)
		practice_cleanup()
		return
	if net.connected:
		net.disconnect_now("switching to practice")
	net = NetClient.new()
	_bind_net_signals()
	net.connect_to("127.0.0.1", port, str(settings["name"]), str(settings["char"]))
	_toast("Local practice server on 127.0.0.1:%d" % port)


func practice_cleanup() -> void:
	if practice_srv != null:
		practice_srv.stop()
		practice_srv.queue_free()
		practice_srv = null


func _bind_net_signals() -> void:
	net.hello_ok.connect(_on_hello_ok)
	net.lobby_state.connect(_on_lobby_state)
	net.lobby_msg.connect(_on_lobby_msg)
	net.match_started.connect(_on_match_started)
	net.snapshot.connect(_on_snapshot)
	net.match_event.connect(_on_match_event)
	net.match_end.connect(_on_match_end)
	net.closed.connect(_on_closed)


# ------------------------------------------------------------- network sinks

func _on_hello_ok(info: Dictionary) -> void:
	self_pid = int(info["pid"])
	self_char = str(settings["char"])
	menu.refresh()
	_dispatch_kind()


func _dispatch_kind() -> void:
	if pending_join_code != "":
		net.join_lobby(pending_join_code, pending_mode, str(settings["char"]))
	elif pending_private:
		net.create_lobby(pending_mode, true)
	else:
		net.join_lobby("", pending_mode, str(settings["char"]))


func _on_lobby_state(info: Dictionary) -> void:
	var phase := int(info["phase"])
	match phase:
		Protocol.LobbyPhase.QUEUE:
			menu.visible = true
			lobby.visible = false
			menu.show_queue()
		Protocol.LobbyPhase.LOBBY:
			menu.visible = false
			lobby.visible = true
			lobby.apply(info)
		_:
			menu.visible = true
			lobby.visible = false


func _on_lobby_msg(msg: String) -> void:
	_toast(msg)


func _on_match_started(info: Dictionary) -> void:
	menu.visible = false
	lobby.visible = false
	spectate_pid = 0
	slot_mirror = 2
	for p in info["players"]:
		if int(p["pid"]) == self_pid:
			self_team = int(p["team"])
	leave_old_match()
	match_world = MatchWorld.new()
	match_world.game = self
	match_world.self_pid = self_pid
	add_child(match_world)
	match_world.build(info)
	_create_hud()
	net.ping(Time.get_ticks_msec())


func leave_old_match() -> void:
	if hud != null:
		hud.queue_free()
		hud = null
	if match_world != null:
		match_world.queue_free()
		match_world = null


func _create_hud() -> void:
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 5
	add_child(menu_layer)
	# note: CanvasLayer stores reference; hud added directly for simplicity
	var h := Hud.new()
	add_child(h)
	hud = h
	hud.joystick_vec = Vector2.ZERO


func _on_snapshot(snap: Dictionary) -> void:
	if match_world == null or hud == null:
		return
	match_world.apply_snapshot(snap)
	var you: Dictionary = snap["you"]
	if not bool(you["alive"]) and spectate_pid == 0:
		# pick a spectate target from snapshot of others
		for o in snap["others"]:
			if bool(o.get("alive", false)):
				spectate_pid = int(o["pid"])
				break
	if spectate_pid != 0 and not bool(you["alive"]):
		var spec: RemotePlayer = match_world.entities.get(spectate_pid)
		if spec != null:
			follow_spectator(spec)


func follow_spectator(spec: RemotePlayer) -> void:
	var cam: Camera3D = match_world.fps.camera
	cam.global_position = spec.global_position + Vector3(0, 6.0, 9.0)
	cam.look_at(spec.global_position)


func _on_match_event(ev: Dictionary) -> void:
	if match_world != null:
		match_world.notify_event(ev)


func _on_match_end(rows: Dictionary) -> void:
	results.visible = true
	results.apply(rows)
	leave_old_match()
	if practice_srv != null:
		practice_cleanup()
	_toast("Match finished.")


func _on_closed(reason: String) -> void:
	practice_cleanup()
	results.visible = false
	lobby.visible = false
	menu.visible = true
	leave_old_match()
	_toast(reason)


func return_to_menu() -> void:
	if practice_srv != null:
		practice_cleanup()
	net.disconnect_now("")
	menu.visible = true
	lobby.visible = false
	leave_old_match()


# ---------------------------------------------------------- profile updates


func update_settings_field(key: String, value) -> void:
	settings[key] = value
	save_settings()
