# server_main.gd — entry scene for the headless dedicated server.
# Usage:
#   godot --headless --path <project> game/scenes/dedicated_server.tscn -- --port 7777
#   godot --headless --path <project> game/scenes/dedicated_server.tscn -- --cfg server.json
# The JSON config may set: port, bot_fill, zone_start, spawn_weapons, phases
# (array of {wait_s, shrink_s, dps, r_mult}). CLI flags privilege-override the
# file. Exits nonzero on bind failure so CI and service managers can alert.
extends Node


var srv: NetServer


func _ready() -> void:
	var port := 7777
	var bot_fill := true
	var zone_start := Zone.start_radius_default()
	var cfg_path := ""
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := str(args[i])
		if a == "--cfg" and i + 1 < args.size():
			cfg_path = str(args[i + 1])
			i += 1
		elif a.begins_with("--cfg="):
			cfg_path = a.substr(6)
		elif a == "--port" and i + 1 < args.size():
			port = int(str(args[i + 1]))
			i += 1
		elif a.begins_with("--port="):
			port = int(a.substr(7))
		elif a == "--bots":
			bot_fill = true
		elif a == "--no-bots":
			bot_fill = false
		else:
			GameLog.warn("srv-main", "ignored arg %s" % a)
		i += 1

	var file_cfg := {}
	if cfg_path != "":
		var f := FileAccess.open(cfg_path, FileAccess.READ)
		if f == null:
			push_error("Server config file not found: %s" % cfg_path)
			get_tree().quit(1)
			return
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Server config is not a JSON object: %s" % cfg_path)
			get_tree().quit(1)
			return
		file_cfg = parsed

	file_cfg["port"] = int(file_cfg.get("port", port))
	file_cfg["bot_fill"] = bool(file_cfg.get("bot_fill", bot_fill))
	file_cfg["zone_start"] = float(file_cfg.get("zone_start", zone_start))
	file_cfg["spawn_weapons"] = bool(file_cfg.get("spawn_weapons", false))
	file_cfg["phases"] = _shape_phases(file_cfg.get("phases", []))

	srv = NetServer.new()
	add_child(srv)
	var err := srv.start(file_cfg)
	if err != "":
		push_error("Server failed to start: " + err)
		get_tree().quit(1)
		return
	print("=== SKYFALL LEGENDS dedicated server listening on udp/%d (bots: %s, boot weps: %s) ===" % [
		int(file_cfg["port"]), str(file_cfg["bot_fill"]), str(file_cfg["spawn_weapons"])])


# JSON gives loose numbers; the Zone state machine wants float-typed phase rows.
func _shape_phases(raw: Variant) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		return []
	var out := []
	for p in raw:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		out.append({
			"wait_s": float(p.get("wait_s", 0.0)),
			"shrink_s": float(p.get("shrink_s", 0.0)),
			"dps": float(p.get("dps", 0.0)),
			"r_mult": float(p.get("r_mult", 1.0)),
		})
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and srv != null:
		srv.stop()
		get_tree().quit(0)
