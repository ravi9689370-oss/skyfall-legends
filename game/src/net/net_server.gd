# net_server.gd — the authoritative multiplayer server for Skyfall Legends.
# Owns sessions, matchmaking queues, lobbies (private + queue-formed) and match
# lifecycles. Runs standalone (headless dedicated) OR embedded for local
# practice. All wire ops are decoded here; gameplay commands are forwarded to
# the room's MatchSim, which owns all verdicts.
class_name NetServer
extends Node


enum SessionState { MENU, QUEUE, LOBBY, MATCH }

const SERVER_NAME := "Skyfall Legends"
const MOTD := "Self-hosted sandbox. Matches auto-start when readiness passes. Bots fill empty seats only when this server enables them."

const RATE_LIMIT := 70
const VIOLATIONS_TO_KICK := 3
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const MAX_ROOMS := 32
const QUEUE_MIN_WAIT := 10.0
const QUEUE_BOT_WAIT := 25.0
const AUTO_START_COUNTDOWN := 5.0
const BOT_PID_BASE := 1000000


var peer: ENetMultiplayerPeer
var cfg := {
	"port": 7777,
	"max_clients": 64,
	"bot_fill": true,
	"tick_hz": 30.0,
	"zone_start": Zone.start_radius_default(),
	"phases": [],
	"spawn_weapons": false,
}
var sessions: Dictionary = {}     # pid -> session dict
var rooms: Dictionary = {}        # code -> room dict
var queues: Dictionary = {MatchRules.SOLO: [], MatchRules.DUO: [], MatchRules.SQUAD: []}
var queue_since: Dictionary = {}  # pid -> msec joined queue
var match_counter := 0


func start(cfg_in: Dictionary = {}) -> String:
	for k in cfg_in:
		cfg[k] = cfg_in[k]
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(int(cfg["port"]), int(cfg["max_clients"]))
	if err != OK:
		return "ENet host failed (code %d)" % err
	peer.peer_connected.connect(_on_connected)
	peer.peer_disconnected.connect(_on_disconnected)
	GameLog.info("sv", "listening on udp/%d" % int(cfg["port"]))
	return ""


func stop() -> void:
	if peer != null:
		peer.close()
		peer = null
	sessions.clear()
	rooms.clear()
	for q in queues.values():
		q.clear()


func _process(delta: float) -> void:
	if peer == null:
		return
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var pid := peer.get_packet_peer()
		var bytes := peer.get_packet()
		_on_packet(pid, bytes)
	_tick_queues()
	_tick_lobbies(delta)
	var to_finish: Array = []
	for code in rooms.keys():
		var room: Dictionary = rooms[code]
		if room.get("sim", null) != null:
			var sim: MatchSim = room["sim"]
			sim.tick(delta)
			sim.broadcast_snapshots()
			if sim.ended:
					to_finish.append(code)
	for code in to_finish:
		_finish_room(code)


# ------------------------------------------------------------------ inputs

func _on_connected(pid: int) -> void:
	sessions[pid] = {
		"pid": pid, "name": "", "char": "ranger", "state": SessionState.MENU, "room": "",
		"rate_window": 0.0, "rate_count": 0, "violations": 0,
	}
	_server_send(pid, Protocol.s_hello_ok(pid, SERVER_NAME, MOTD), true)
	GameLog.info("sv", "peer %d connected" % pid)


func _on_disconnected(pid: int) -> void:
	var s: Dictionary = sessions.get(pid, {})
	if not s.is_empty():
		sessions.erase(pid)
	for q in queues.values():
		q.erase(pid)
	queue_since.erase(pid)
	var code := str(s.get("room", ""))
	if code != "" and rooms.has(code):
		var room: Dictionary = rooms[code]
		room["players"].erase(pid)
		room["ready"].erase(pid)
		if room.get("sim", null) != null:
			var sim: MatchSim = room["sim"]
			sim.on_peer_left(pid)
		else:
			if int(room["host"]) == pid and room["players"].size() > 0:
				room["host"] = int(room["players"][0])
			if room["players"].is_empty():
				rooms.erase(code)
			else:
				_broadcast_lobby(room)
		if room["players"].is_empty():
			rooms.erase(code)
	GameLog.info("sv", "peer %d disconnected" % pid)


func _on_packet(pid: int, bytes: PackedByteArray) -> void:
	var s: Dictionary = sessions.get(pid, {})
	if s.is_empty():
		return
	if not _rate_ok(pid, s):
		return
	var d := _decode(bytes)
	if d.is_empty():
		return
	_dispatch(pid, s, d)


func _rate_ok(pid: int, s: Dictionary) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if float(s["rate_window"]) < now - 1.0:
		s["rate_window"] = now
		s["rate_count"] = 0
	s["rate_count"] = int(s["rate_count"]) + 1
	if int(s["rate_count"]) <= RATE_LIMIT:
		return true
	s["violations"] = int(s["violations"]) + 1
	if int(s["violations"]) >= VIOLATIONS_TO_KICK:
		_server_send(pid, Protocol.s_kicked("Message rate exceeded repeatedly."), true)
		peer.disconnect_peer(pid, true)
		GameLog.warn("sv", "kicked rate violator %d" % pid)
	return false


func _decode(bytes: PackedByteArray) -> Dictionary:
	var dec := Protocol.decode(bytes)
	if dec.is_empty():
		return {}
	var op: int = dec["op"]
	var b: StreamPeerBuffer = dec["b"]
	match op:
		Protocol.Op.HELLO:
			return {"op": op, "name": str(Protocol.get_str(b)), "char": str(Protocol.get_str(b))}
		Protocol.Op.LOBBY_CREATE:
			return {"op": op, "mode": str(Protocol.get_str(b)), "priv": bool(b.get_u8())}
		Protocol.Op.LOBBY_JOIN:
			return {"op": op, "code": str(Protocol.get_str(b)), "mode": str(Protocol.get_str(b)), "char": str(Protocol.get_str(b))}
		Protocol.Op.LOBBY_SET_READY:
			return {"op": op, "ready": bool(b.get_u8()), "char": str(Protocol.get_str(b))}
		Protocol.Op.LOBBY_BACK:
			return {"op": op}
		Protocol.Op.INPUT:
			return {
				"op": op, "seq": int(b.get_u32()),
				"pos": Protocol.get_v3(b), "yaw": float(b.get_float()),
				"move": Protocol.get_v2(b),
				"sprint": bool(b.get_u8()), "crouch": bool(b.get_u8()),
				"jump": bool(b.get_u8()), "deploy": bool(b.get_u8()), "ability": bool(b.get_u8()),
			}
		Protocol.Op.FIRE:
			return {"op": op, "yaw": float(b.get_float()), "dir": Protocol.get_v3(b)}
		Protocol.Op.USE_ITEM:
			return {"op": op, "kind": str(Protocol.get_str(b))}
		Protocol.Op.PICKUP, Protocol.Op.RELOAD:
			return {"op": op}
		Protocol.Op.SWITCH_WEAPON:
			return {"op": op, "slot": int(b.get_u8())}
		Protocol.Op.SPECTATE:
			return {"op": op, "pid": int(b.get_u32())}
		Protocol.Op.PING:
			return {"op": op, "t": float(b.get_double())}
	return {}


func _dispatch(pid: int, s: Dictionary, d: Dictionary) -> void:
	match int(d["op"]):
		Protocol.Op.HELLO:
			s["name"] = Names.sanitize(str(d["name"]))
			if CharactersDB.get_character(str(d["char"])).size() > 0:
				s["char"] = str(d["char"])
			_server_send(pid, Protocol.s_hello_ok(pid, SERVER_NAME, MOTD), true)
			GameLog.info("sv", "hello from %s (%d)" % [s["name"], pid])
		Protocol.Op.PING:
			_server_send(pid, Protocol.s_pong(float(d["t"])))
		Protocol.Op.LOBBY_CREATE:
			_cmd_create(pid, s, str(d["mode"]), bool(d["priv"]))
		Protocol.Op.LOBBY_JOIN:
			_cmd_join(pid, s, str(d["code"]), str(d["mode"]), str(d["char"]))
		Protocol.Op.LOBBY_SET_READY:
			_cmd_set_ready(pid, s, bool(d["ready"]), str(d["char"]))
		Protocol.Op.LOBBY_BACK:
			_cmd_back(s)
		Protocol.Op.INPUT, Protocol.Op.FIRE, Protocol.Op.USE_ITEM, Protocol.Op.PICKUP, \
		Protocol.Op.RELOAD, Protocol.Op.SWITCH_WEAPON, Protocol.Op.SPECTATE:
			_forward_to_room(pid, s, d)
		_:
			GameLog.warn("sv", "unknown op %d from %d" % [int(d["op"]), pid])


# ------------------------------------------------------------------- rooms

func _human_rows(room: Dictionary) -> Array:
	var out := []
	var tsize := int(MatchRules.MODE_TEAM_SIZE[int(room["mode"])])
	for i in room["players"].size():
		var pid: int = room["players"][i]
		var sp: Dictionary = sessions.get(pid, {})
		out.append({
			"pid": pid,
			"name": str(sp.get("name", "?")),
			"char": str(sp.get("char", "ranger")),
			"ready": bool(room["ready"].get(pid, false)),
			"team": i / tsize,
			"bot": false,
		})
	return out


func _cmd_create(pid: int, s: Dictionary, mode: String, priv: bool) -> int:
	var m := MatchRules.mode_id(mode)
	var code := _gen_code()
	rooms[code] = {
		"code": code, "mode": m, "private": priv, "auto": false,
		"players": [pid], "ready": {}, "host": pid, "countdown": 0.0, "sim": null,
	}
	s["state"] = SessionState.LOBBY
	s["room"] = code
	_broadcast_lobby(rooms[code])
	return m


func _cmd_join(pid: int, s: Dictionary, code: String, mode: String, char_in: String) -> void:
	if CharactersDB.get_character(char_in).size() > 0:
		s["char"] = char_in
	var clean := code.strip_edges().to_upper()
	if clean != "":
		if rooms.size() >= MAX_ROOMS:
			_server_send(pid, Protocol.s_lobby_msg("Server is full right now."), true)
			return
		if not rooms.has(clean):
			_server_send(pid, Protocol.s_lobby_msg("Room %s not found." % clean), true)
			return
		var room: Dictionary = rooms[clean]
		if room.get("sim", null) != null:
			_server_send(pid, Protocol.s_lobby_msg("Match already running in that room."), true)
			return
		if room["players"].size() >= int(MatchRules.MODE_PLAYERS[int(room["mode"])]):
			_server_send(pid, Protocol.s_lobby_msg("Room full."), true)
			return
		room["players"].append(pid)
		s["state"] = SessionState.LOBBY
		s["room"] = clean
		_broadcast_lobby(room)
	else:
		var m := MatchRules.mode_id(mode)
		if not queues[m].has(pid):
			queues[m].append(pid)
		queue_since[pid] = Time.get_ticks_msec()
		s["state"] = SessionState.QUEUE
		s["room"] = ""
		_server_send(pid, Protocol.s_lobby_state(Protocol.LobbyPhase.QUEUE, "", MatchRules.mode_name(m), false, [], 0.0), true)


func _cmd_set_ready(pid: int, s: Dictionary, ready: bool, char_in: String) -> void:
	var code := str(s.get("room", ""))
	if code == "":
		return
	var room: Dictionary = rooms.get(code, {})
	if room.is_empty():
		return
	if CharactersDB.get_character(char_in).size() > 0:
		s["char"] = char_in
	room["ready"][pid] = ready
	var all_ready := true
	for p in room["players"]:
		if not bool(room["ready"].get(p, false)):
			all_ready = false
			break
	if room.get("auto", false) == false and all_ready and room["players"].size() >= 2:
		# private lobbies start as soon as everyone readies up
		room["countdown"] = AUTO_START_COUNTDOWN
	_broadcast_lobby(room)


func _cmd_back(s: Dictionary) -> void:
	var pid := int(s.get("pid", 0))
	for q in queues.values():
		q.erase(pid)
	queue_since.erase(pid)
	var code := str(s.get("room", ""))
	if code != "" and rooms.has(code):
		var room: Dictionary = rooms[code]
		room["players"].erase(pid)
		room["ready"].erase(pid)
		if int(room["host"]) == pid and room["players"].size() > 0:
			room["host"] = int(room["players"][0])
		if room["players"].is_empty():
			rooms.erase(code)
		else:
			_broadcast_lobby(room)
	s["room"] = ""
	s["state"] = SessionState.MENU
	_server_send(pid, Protocol.s_lobby_state(Protocol.LobbyPhase.NONE, "", "", false, [], 0.0), true)


# --------------------------------------------------------- queues + starts

func _tick_queues() -> void:
	var now := Time.get_ticks_msec()
	for m in queues:
		var q: Array = queues[m]
		if q.is_empty() or rooms.size() >= MAX_ROOMS:
			continue
		var seats := int(MatchRules.MODE_PLAYERS[int(m)])
		var waited := 99999.0
		for pid in q:
			var jt := int(queue_since.get(pid, now))
			waited = minf(waited, (now - jt) / 1000.0)
		var can_form := q.size() >= seats
		if not can_form and q.size() >= 2 and waited >= QUEUE_MIN_WAIT:
			can_form = true
		if not can_form and q.size() >= 1 and waited >= QUEUE_BOT_WAIT and bool(cfg["bot_fill"]):
			can_form = true
		if not can_form:
			continue
		var party := q.slice(0, mini(q.size(), seats))
		for pid in party:
			q.erase(pid)
			queue_since.erase(pid)
		var code := _gen_code()
		var room := {
			"code": code, "mode": int(m), "private": false, "auto": true,
			"players": party.duplicate(), "ready": {}, "host": int(party[0]),
			"countdown": AUTO_START_COUNTDOWN, "sim": null,
		}
		for pid in party:
			room["ready"][pid] = true   # queued players readied when they hit PLAY
			var s: Dictionary = sessions.get(pid, {})
			s["state"] = SessionState.LOBBY
			s["room"] = code
		rooms[code] = room
		for pid in party:
			_server_send(int(pid), Protocol.s_lobby_msg("Matchmaking: match found! Starting in %d s…" % int(AUTO_START_COUNTDOWN)), true)
		_broadcast_lobby(room)


func _tick_lobbies(delta: float) -> void:
	for code in rooms.keys():
		var room: Dictionary = rooms[code]
		if room.get("sim", null) != null:
			continue
		var humans: int = room["players"].size()
		if humans < 1:
			rooms.erase(code)
			continue
		var all_ready := true
		for p in room["players"]:
			if not bool(room["ready"].get(p, false)):
				all_ready = false
				break
		var cd := float(room["countdown"])
		if not all_ready:
			continue
		if bool(room.get("auto", false)):
			if cd <= 0.0:
				_start_match(code)
		elif humans >= 2:
			if cd <= 0.0:
				room["countdown"] = 3.0
			else:
				room["countdown"] = cd - delta
				if room["countdown"] <= 0.0:
					_start_match(code)
		elif humans == 1 and bool(cfg["bot_fill"]):
			if cd >= 6.0:
				_start_match(code)
			else:
				room["countdown"] = cd + delta


func _start_match(code: String) -> void:
	var room: Dictionary = rooms[code]
	var m := int(room["mode"])
	var seats := int(MatchRules.MODE_PLAYERS[m])
	var tsize := int(MatchRules.MODE_TEAM_SIZE[m])
	var rows := []
	var i := 0
	for pid in room["players"]:
		var sp: Dictionary = sessions.get(int(pid), {})
		rows.append({
			"pid": int(pid), "name": str(sp.get("name", "?")),
			"char": str(sp.get("char", "ranger")), "team": i / tsize, "bot": false,
		})
		i += 1
	if bool(cfg["bot_fill"]) and rows.size() < seats:
		var bs := rows.size()
		for b in range(seats - bs):
			var bteam := (bs + b) / tsize
			rows.append({
				"pid": BOT_PID_BASE + b,
				"name": "AI_%03d" % (b + 1),
				"char": "ranger",
				"team": bteam, "bot": true,
			})
	match_counter += 1
	var sim := MatchSim.new(rows, randi(), Callable(self, "_sim_send"), {
		"mode": m,
		"match_id": "m%06d" % match_counter,
		"zone_start": float(cfg["zone_start"]),
		"phases": cfg["phases"],
		"spawn_weapons": bool(cfg.get("spawn_weapons", false)),
	})
	room["sim"] = sim
	room["countdown"] = 0.0
	var loot_list := sim.loot.unclaimed_wire()
	var zone_state := sim.zone.state_dict()
	for r in rows:
		if bool(r["bot"]):
			continue
		r["pos"] = sim.flight["from"]
	for pid in room["players"]:
		var sp: Dictionary = sessions.get(int(pid), {})
		sp["state"] = SessionState.MATCH
		_server_send(int(pid), Protocol.s_match_start(sim.match_id, "kestrel_atoll",
			MatchRules.mode_name(m), zone_state, sim.flight, rows, loot_list), true)
	GameLog.info("sv", "match %s started in room %s (%d humans, %d bots)" % [sim.match_id, code, room["players"].size(), sim.players.size() - room["players"].size()])


func _sim_send(pid: int, bytes: PackedByteArray) -> void:
	if pid >= BOT_PID_BASE:
		return
	# Snapshots ride the unreliable channel; the one-shot MATCH_END is reliable.
	_server_send(pid, bytes, bytes.size() > 0 and int(bytes[0]) == Protocol.Op.MATCH_END)


func _forward_to_room(pid: int, s: Dictionary, d: Dictionary) -> void:
	var code := str(s.get("room", ""))
	if code == "":
		return
	var room: Dictionary = rooms.get(code, {})
	if room.is_empty() or room.get("sim", null) == null:
		return
	var sim: MatchSim = room["sim"]
	sim.handle_packet(pid, d)


func _finish_room(code: String) -> void:
	var room: Dictionary = rooms.get(code, {})
	if room.is_empty():
		return
	for pid in room["players"]:
		var sp: Dictionary = sessions.get(int(pid), {})
		sp["state"] = SessionState.MENU
		sp["room"] = ""
	rooms.erase(code)
	GameLog.info("sv", "room %s closed" % code)


# -------------------------------------------------------------- lobby wire

func _broadcast_lobby(room: Dictionary) -> void:
	var humans := _human_rows(room)
	var is_code := str(room["code"])
	var mode_name := MatchRules.mode_name(int(room["mode"]))
	for pid in room["players"]:
		_server_send(int(pid), Protocol.s_lobby_state(Protocol.LobbyPhase.LOBBY, is_code,
			mode_name, int(room["host"]) == int(pid), humans, float(room["countdown"])), true)


func _gen_code() -> String:
	while true:
		var c := ""
		for i in 4:
			c += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
		if not rooms.has(c):
			return c
	return "ZZZZ"


func _server_send(pid: int, bytes: PackedByteArray, rel := false) -> void:
	if peer == null:
		return
	peer.set_transfer_channel(0)
	peer.set_transfer_mode(
		MultiplayerPeer.TRANSFER_MODE_RELIABLE if rel else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	peer.set_target_peer(pid)
	peer.put_packet(bytes)
