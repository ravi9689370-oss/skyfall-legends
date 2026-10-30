# protocol.gd — wire protocol for Skyfall Legends (campaign: custom op codes over ENet).
#
# Design rules:
# - Every message is [u8 op][payload]. Ops are C2S_* (client->server) in 1..99
#   and S2C_* (server->client) in 101..199 so mistakes are loud.
# - Numbers are little-endian via StreamPeerBuffer (definitive and testable).
# - Strings are [u16 len][utf8 bytes]. Vectors are f32-serialized.
# - Clients NEVER send damage, hp, ammo or inventory state; the server
#   maintains all authoritative state (see docs/MULTIPLAYER_ARCHITECTURE.md).
class_name Protocol
extends RefCounted


enum Op {
	# --- client -> server ---
	HELLO          = 1, # {name, char_id}
	LOBBY_CREATE   = 2, # {mode, private}
	LOBBY_JOIN     = 3, # {code, mode, char_id}
	LOBBY_SET_READY= 4, # {ready, char_id}
	LOBBY_BACK     = 5, # leave queue/lobby
	INPUT          = 6, # {seq, pos, yaw, move, sprint, crouch, jump, deploy, ability}
	FIRE           = 7, # {yaw, dir}
	USE_ITEM       = 8, # {kind}
	PICKUP         = 9, # {}
	RELOAD         = 10, # {}
	SWITCH_WEAPON  = 11, # {slot}
	SPECTATE       = 12, # {pid}
	PING           = 13, # {t}

	# --- server -> client ---
	HELLO_OK       = 101, # {pid, server_name, motd}
	LOBBY_STATE    = 102, # {phase, code, mode, is_host, players[...], start_in}
	LOBBY_MSG      = 103, # {msg}
	MATCH_START    = 104, # {match_id, map, mode, zone, flight, players[...], loot[...]}
	SNAPSHOT       = 105, # {tick, zone, you, others[], events[]}
	MATCH_EVENT    = 106, # typed event
	MATCH_END      = 107, # {winner_team, rows[...]}
	SERVER_CLOSE   = 108, # {reason}
	KICKED         = 109, # {reason}
	PONG           = 110, # {t}
}


enum LobbyPhase {
	NONE = 0,
	QUEUE = 1,      # in public matchmaking queue
	LOBBY = 2,      # inside a lobby (private or auto-formed)
	RUNNING = 3,    # match running (client-side display only)
}


enum FireCause { WEAPON = 0, ABILITY_NONE = 1 }


# ----------------------------------------------------------------------- encode

static func _new_buf() -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	return b


static func put_str(b: StreamPeerBuffer, s: String) -> void:
	var enc := s.to_utf8_buffer()
	b.put_u16(enc.size())
	b.put_data(enc)


static func get_str(b: StreamPeerBuffer) -> String:
	var n: int = b.get_u16()
	if n <= 0:
		return ""
	return b.get_string(n)


static func put_v3(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_float(v.x)
	b.put_float(v.y)
	b.put_float(v.z)


static func get_v3(b: StreamPeerBuffer) -> Vector3:
	var v := Vector3.ZERO
	v.x = b.get_float()
	v.y = b.get_float()
	v.z = b.get_float()
	return v


static func put_v2(b: StreamPeerBuffer, v: Vector2) -> void:
	b.put_float(v.x)
	b.put_float(v.y)


static func get_v2(b: StreamPeerBuffer) -> Vector2:
	var v := Vector2.ZERO
	v.x = b.get_float()
	v.y = b.get_float()
	return v


# --------------------------------------------------------------- client sends

static func c_hello(name: String, char_id: String) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.HELLO)
	put_str(b, name)
	put_str(b, char_id)
	return b.data_array


static func c_lobby_create(mode: String, is_private: bool) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.LOBBY_CREATE)
	put_str(b, mode)
	b.put_u8(1 if is_private else 0)
	return b.data_array


static func c_lobby_join(code: String, mode: String, char_id: String) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.LOBBY_JOIN)
	put_str(b, code)
	put_str(b, mode)
	put_str(b, char_id)
	return b.data_array


static func c_set_ready(ready: bool, char_id: String) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.LOBBY_SET_READY)
	b.put_u8(1 if ready else 0)
	put_str(b, char_id)
	return b.data_array


static func c_back() -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.LOBBY_BACK)
	return b.data_array


# seq: increasing client tick id. move: unit-ish joystick vector (x,z).
# pos/yaw are the client's *prediction* used only to reconcile; never authority.
static func c_input(seq: int, pos: Vector3, yaw: float, move: Vector2, flags: Dictionary) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.INPUT)
	b.put_u32(seq)
	put_v3(b, pos)
	b.put_float(yaw)
	put_v2(b, move)
	b.put_u8(int(flags.get("sprint", false)))
	b.put_u8(int(flags.get("crouch", false)))
	b.put_u8(int(flags.get("jump", false)))
	b.put_u8(int(flags.get("deploy", false)))
	b.put_u8(int(flags.get("ability", false)))
	return b.data_array


static func c_fire(yaw: float, dir: Vector3) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.FIRE)
	b.put_float(yaw)
	put_v3(b, dir.normalized())
	return b.data_array


static func c_use_item(kind: String) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.USE_ITEM)
	put_str(b, kind)
	return b.data_array


static func c_pickup() -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.PICKUP)
	return b.data_array


static func c_reload() -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.RELOAD)
	return b.data_array


static func c_switch(slot: int) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.SWITCH_WEAPON)
	b.put_u8(slot)
	return b.data_array


static func c_spectate(pid: int) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.SPECTATE)
	b.put_u32(pid)
	return b.data_array


static func c_ping(t: float) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.PING)
	b.put_double(t)
	return b.data_array


# ------------------------------------------------------------- server's writes

static func s_hello_ok(pid: int, server_name: String, motd: String) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.HELLO_OK)
	b.put_u32(pid)
	put_str(b, server_name)
	put_str(b, motd)
	return b.data_array


# players: Array of Dictionary {pid, name, char, ready, team, bot}
static func s_lobby_state(phase: int, code: String, mode: String, is_host: bool, players: Array, start_in: float) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.LOBBY_STATE)
	b.put_u8(phase)
	put_str(b, code)
	put_str(b, mode)
	b.put_u8(1 if is_host else 0)
	b.put_u16(players.size())
	for p in players:
		b.put_u32(p.pid)
		put_str(b, p.name)
		put_str(b, p.get("char", "ranger"))
		b.put_u8(1 if p.get("ready", false) else 0)
		b.put_u8(p.get("team", 0))
		b.put_u8(1 if p.get("bot", false) else 0)
	b.put_float(start_in)
	return b.data_array


static func s_lobby_msg(msg: String) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.LOBBY_MSG)
	put_str(b, msg)
	return b.data_array


# Session/mut match creation. players: {pid, name, char, team, bot}
# loot: {id, item, pos}
static func s_match_start(match_id: String, map: String, mode: String, zone: Dictionary,
		flight: Dictionary, players: Array, loot: Array) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.MATCH_START)
	b.put_u8(match_id.length())
	b.put_data(match_id.to_utf8_buffer())
	put_str(b, map)
	put_str(b, mode)
	put_v3(b, zone.get("cur_center", Vector3.ZERO))
	b.put_float(float(zone.get("cur_radius", 0.0)))
	put_v3(b, flight.get("from", Vector3.ZERO))
	put_v3(b, flight.get("to", Vector3.ZERO))
	b.put_u16(players.size())
	for p in players:
		b.put_u32(p.pid)
		put_str(b, p.name)
		put_str(b, p.get("char", "ranger"))
		b.put_u8(p.get("team", 0))
		b.put_u8(1 if p.get("bot", false) else 0)
		put_v3(b, p.get("pos", Vector3.ZERO))
	b.put_u16(loot.size())
	for l in loot:
		b.put_u32(l.id)
		put_str(b, l.item)
		put_v3(b, l.pos)
	return b.data_array


# ---------------------------------------------------- snapshot (server -> all)

# you: authoritative self state. others: remote players. events: inline events
# piggyback snapshots for delivery simplicity (v1 uses a single reliable channel).
static func s_snapshot(tick: int, zone: Dictionary, sp: Dictionary, others: Array, events: Array) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.SNAPSHOT)
	b.put_u32(tick)

	# zone
	b.put_u8(zone.get("phase_idx", 0))
	b.put_u8(zone.get("state", 0)) # 0 wait, 1 shrinking
	b.put_float(zone.get("cur_radius", 0.0))
	put_v3(b, zone.get("cur_center", Vector3.ZERO))
	b.put_float(zone.get("next_radius", 0.0))
	put_v3(b, zone.get("next_center", Vector3.ZERO))
	b.put_float(zone.get("time_left", 0.0))
	b.put_float(zone.get("dps", 0.0))

	# self
	put_v3(b, sp.get("pos", Vector3.ZERO))
	b.put_u8(sp.get("state", 0)) # AirState.GROUND etc
	b.put_float(sp.get("hp", 0.0))
	b.put_float(sp.get("armor", 0.0))
	put_str(b, sp.get("weapon", ""))
	b.put_u16(sp.get("mag", 0))
	b.put_u16(sp.get("reserve", 0))
	b.put_u8(sp.get("slot", 0))
	b.put_u8(sp.get("nades", 0))
	b.put_u16(sp.get("heals_a", 0))
	b.put_u16(sp.get("heals_b", 0))
	b.put_float(sp.get("reload_left", 0.0))
	b.put_float(sp.get("ability_left", 0.0))
	b.put_u8(sp.get("alive", 0))

	# others: [{pid, pos, yaw, state, char, name, team, alive, nades, slot_cat, nade_target}]
	b.put_u16(others.size())
	for o in others:
		b.put_u32(o.get("pid", 0))
		put_v3(b, o.get("pos", Vector3.ZERO))
		b.put_float(o.get("yaw", 0.0))
		b.put_u8(o.get("state", 0))
		put_str(b, o.get("char", "ranger"))
		put_str(b, o.get("name", ""))
		b.put_u8(o.get("team", 0))
		b.put_u8(o.get("alive", 0))
		put_str(b, o.get("held", ""))

	# events: [{t (op within EvtCategory), fields...}] packed switch below
	b.put_u16(events.size())
	for ev in events:
		_write_event(b, ev)

	return b.data_array


static func _write_event(b: StreamPeerBuffer, ev: Dictionary) -> void:
	var t: int = ev.get("t", 0)
	b.put_u8(t)
	match t:
		MatchEvents.HIT_TAKEN:
			b.put_float(ev.get("dmg", 0.0))
			b.put_float(ev.get("hp", 0.0))
			b.put_float(ev.get("armor", 0.0))
			b.put_u8(ev.get("head", 0))
		MatchEvents.HIT_DEALT:
			b.put_float(ev.get("dmg", 0.0))
			b.put_u8(ev.get("kill", 0))
		MatchEvents.HEALED:
			b.put_float(ev.get("heal", 0.0))
		MatchEvents.LOOT_CLAIMED:
			b.put_u32(ev.get("lid", 0))
			b.put_u32(ev.get("by", 0))
			put_str(b, ev.get("item", ""))
			b.put_u8(ev.get("yours", 0))
		MatchEvents.DROPPED_LOOT:
			b.put_u32(ev.get("lid", 0))
			put_str(b, ev.get("item", ""))
			put_v3(b, ev.get("pos", Vector3.ZERO))
		MatchEvents.GRENADE_THROWN:
			b.put_u32(ev.get("by", 0))
			put_v3(b, ev.get("pos", Vector3.ZERO))
			put_v3(b, ev.get("vel", Vector3.ZERO))
		MatchEvents.GRENADE_EXPLODED:
			put_v3(b, ev.get("pos", Vector3.ZERO))
		MatchEvents.ABILITY:
			b.put_u32(ev.get("pid", 0))
			put_str(b, ev.get("kind", ""))
		MatchEvents.ELIMINATION:
			b.put_u32(ev.get("killer", 0))
			b.put_u32(ev.get("victim", 0))
			put_str(b, ev.get("weapon", ""))
			put_str(b, ev.get("cause", ""))
		MatchEvents.PLAYER_LEFT_MATCH:
			b.put_u32(ev.get("pid", 0))
		MatchEvents.ZONE_ANNOUNCE:
			b.put_u8(ev.get("phase_idx", 0))
			b.put_float(ev.get("radius", 0.0))
			put_v3(b, ev.get("center", Vector3.ZERO))
		MatchEvents.SPECTATE_OFFER:
			b.put_u32(ev.get("pid", 0))
			put_str(b, ev.get("name", ""))
		MatchEvents.SHOT:
			# audio/visual info only; authoritative result came as HIT_* events
			b.put_u32(ev.get("pid", 0))
			put_v3(b, ev.get("muzzle", Vector3.ZERO))
			put_v3(b, ev.get("impact", Vector3.ZERO))
			put_str(b, ev.get("weapon", ""))
		MatchEvents.MSG:
			put_str(b, ev.get("msg", ""))
		_:
			pass


# ------------------------------------------------------------------ match end

static func s_match_end(winner_team: int, rows: Array) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.MATCH_END)
	b.put_u8(winner_team)
	b.put_u16(rows.size())
	for r in rows:
		b.put_u32(r.get("pid", 0))
		put_str(b, r.get("name", ""))
		b.put_u8(r.get("placement", 0))
		b.put_u8(r.get("kills", 0))
		b.put_float(r.get("hp", 0.0) * 0.0 + r.get("dmg", 0.0))
		b.put_u32(r.get("alive_ms", 0))
		b.put_u8(1 if r.get("alive", false) else 0)
	return b.data_array


static func s_match_event(ev: Dictionary) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.MATCH_EVENT)
	_write_event(b, ev)
	return b.data_array


static func s_server_close(reason: String) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.SERVER_CLOSE)
	put_str(b, reason)
	return b.data_array


static func s_kicked(reason: String) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.KICKED)
	put_str(b, reason)
	return b.data_array


static func s_pong(t: float) -> PackedByteArray:
	var b := _new_buf()
	b.put_u8(Op.PONG)
	b.put_double(t)
	return b.data_array


# ---------------------------------------------------------------------- decode

# Returns {op:int, b:StreamPeerBuffer} or empty Dictionary on malformed input.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 1:
		return {}
	var b := _new_buf()
	b.data_array = bytes
	b.big_endian = false
	var op: int = b.get_u8()
	return {"op": op, "b": b}


# ---------------------------------------------------------- client-side parse

static func parse_lobby_state(b: StreamPeerBuffer) -> Dictionary:
	var phase: int = b.get_u8()
	var code := get_str(b)
	var mode := get_str(b)
	var is_host := bool(b.get_u8())
	var n := int(b.get_u16())
	var players := []
	for i in n:
		players.append({
			"pid": int(b.get_u32()),
			"name": get_str(b),
			"char": get_str(b),
			"ready": bool(b.get_u8()),
			"team": int(b.get_u8()),
			"bot": bool(b.get_u8()),
		})
	var start_in := float(b.get_float())
	return {"phase": phase, "code": code, "mode": mode, "is_host": is_host, "players": players, "start_in": start_in}


static func parse_match_start(b: StreamPeerBuffer) -> Dictionary:
	var id_len := int(b.get_u8())
	var match_id := b.get_string(id_len)
	var map := get_str(b)
	var mode := get_str(b)
	var zone := {}
	zone["center"] = get_v3(b)
	zone["radius"] = float(b.get_float())
	var flight := {"from": get_v3(b), "to": get_v3(b)}
	var n := int(b.get_u16())
	var players := []
	for i in n:
		var pid := int(b.get_u32())
		var name := get_str(b)
		var char := get_str(b)
		var team := int(b.get_u8())
		var bot := bool(b.get_u8())
		var pos := get_v3(b)
		players.append({"pid": pid, "name": name, "char": char, "team": team, "bot": bot, "pos": pos})
	var loot_n := int(b.get_u16())
	var loot := []
	for i in loot_n:
		loot.append({"id": int(b.get_u32()), "item": get_str(b), "pos": get_v3(b)})
	return {"match_id": match_id, "map": map, "mode": mode, "zone": zone, "flight": flight, "players": players, "loot": loot}


static func parse_snapshot(b: StreamPeerBuffer) -> Dictionary:
	var tick := int(b.get_u32())
	var zone := {
		"phase_idx": int(b.get_u8()), "state": int(b.get_u8()),
		"cur_radius": float(b.get_float()), "cur_center": get_v3(b),
		"next_radius": float(b.get_float()), "next_center": get_v3(b),
		"time_left": float(b.get_float()), "dps": float(b.get_float()),
	}
	var you := {
		"pos": get_v3(b), "state": int(b.get_u8()),
		"hp": float(b.get_float()), "armor": float(b.get_float()),
		"weapon": get_str(b), "mag": int(b.get_u16()), "reserve": int(b.get_u16()),
		"slot": int(b.get_u8()), "nades": int(b.get_u8()),
		"heals_a": int(b.get_u16()), "heals_b": int(b.get_u16()),
		"reload_left": float(b.get_float()), "ability_left": float(b.get_float()),
		"alive": bool(b.get_u8()),
	}
	var n := int(b.get_u16())
	var others := []
	for i in n:
		others.append({
			"pid": int(b.get_u32()), "pos": get_v3(b), "yaw": float(b.get_float()),
			"state": int(b.get_u8()), "char": get_str(b), "name": get_str(b),
			"team": int(b.get_u8()), "alive": bool(b.get_u8()), "held": get_str(b),
		})
	var e_n := int(b.get_u16())
	var events := []
	for i in e_n:
		events.append(_read_event(b))
	return {"tick": tick, "zone": zone, "you": you, "others": others, "events": events}


static func _read_event(b: StreamPeerBuffer) -> Dictionary:
	var t := int(b.get_u8())
	match t:
		MatchEvents.HIT_TAKEN:
			return {"t": t, "dmg": float(b.get_float()), "hp": float(b.get_float()), "armor": float(b.get_float()), "head": bool(b.get_u8())}
		MatchEvents.HIT_DEALT:
			return {"t": t, "dmg": float(b.get_float()), "kill": bool(b.get_u8())}
		MatchEvents.HEALED:
			return {"t": t, "heal": float(b.get_float())}
		MatchEvents.LOOT_CLAIMED:
			return {"t": t, "lid": int(b.get_u32()), "by": int(b.get_u32()), "item": get_str(b), "yours": bool(b.get_u8())}
		MatchEvents.DROPPED_LOOT:
			return {"t": t, "lid": int(b.get_u32()), "item": get_str(b), "pos": get_v3(b)}
		MatchEvents.GRENADE_THROWN:
			return {"t": t, "by": int(b.get_u32()), "pos": get_v3(b), "vel": get_v3(b)}
		MatchEvents.GRENADE_EXPLODED:
			return {"t": t, "pos": get_v3(b)}
		MatchEvents.ABILITY:
			return {"t": t, "pid": int(b.get_u32()), "kind": get_str(b)}
		MatchEvents.ELIMINATION:
			return {"t": t, "killer": int(b.get_u32()), "victim": int(b.get_u32()), "weapon": get_str(b), "cause": get_str(b)}
		MatchEvents.PLAYER_LEFT_MATCH:
			return {"t": t, "pid": int(b.get_u32())}
		MatchEvents.ZONE_ANNOUNCE:
			return {"t": t, "phase_idx": int(b.get_u8()), "radius": float(b.get_float()), "center": get_v3(b)}
		MatchEvents.SPECTATE_OFFER:
			return {"t": t, "pid": int(b.get_u32()), "name": get_str(b)}
		MatchEvents.SHOT:
			return {"t": t, "pid": int(b.get_u32()), "muzzle": get_v3(b), "impact": get_v3(b), "weapon": get_str(b)}
		MatchEvents.MSG:
			return {"t": t, "msg": get_str(b)}
	return {"t": t, "pid": int(b.get_u32()), "name": get_str(b), "kind": get_str(b)}


static func parse_match_end(b: StreamPeerBuffer) -> Dictionary:
	var winner_team := int(b.get_u8())
	var n := int(b.get_u16())
	var rows := []
	for i in n:
		rows.append({
			"pid": int(b.get_u32()),
			"name": get_str(b),
			"placement": int(b.get_u8()),
			"kills": int(b.get_u8()),
			"dmg": float(b.get_float()),
			"alive_ms": int(b.get_u32()),
			"alive": bool(b.get_u8()),
		})
	return {"winner_team": winner_team, "rows": rows}


static func parse_simple(b: StreamPeerBuffer) -> Dictionary:
	# HELLO_OK / LOBBY_MSG / KICKED / SERVER_CLOSE
	return {"msg": get_str(b)}


# this helper belongs on the server only: (kept for completeness)
# static func _pid_of_session(...)
