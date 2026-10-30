# match_sim.gd — ONE authoritative match: insertion, movement, combat, loot,
# safe zone, elimination, victory. Runs on the dedicated server (headless) and
# is fully usable headless in tests. Event delivery model:
#   evts entries carry "to": pid (specific) or 0 (broadcast). Snapshots filter
#   and rewrite per-viewer fields (e.g. LOOT_CLAIMED.yours).
class_name MatchSim
extends RefCounted


enum State { PLANE = 0, CHUTE = 1, GROUND = 2, DEAD = 3 }
const SLOT_NADE := 3
const GRAVITY := 20.0
const JUMP_V := 7.0
const PLANE_SPEED := 50.0
const DEPLOY_MIN_T := 0.08
const NADE_R := 7.0
const NADE_DMG := 95.0
const PICKUP_R := 2.4


var send: Callable = Callable()        # (pid:int, bytes:PackedByteArray) bots filtered by net layer
var players: Dictionary           # pid -> sp dict
var bots: Dictionary              # pid -> BotBrain (server-managed only)
var zone: Zone
var loot: LootField
var rng: RandomNumberGenerator
var t := 0.0
var match_id := ""
var mode: int = MatchRules.SOLO
var ended := false
var winner_team := -1
var flight: Dictionary = {}
var plane_len := 1.0
var plane_seconds := 30.0
var plane_t := 0.0
var evts: Array = []                   # event dicts (flushed to snapshots)
var grenades: Array = []               # {pid,pos,vel,born}
var next_snap := 0.0
var snap_hz := 8.0
var order: Array = []                  # elimination order (pid list)
var dead_at: Dictionary = {}
var rows_cache: Array = []             # filled at end
var send_cfg: Dictionary = {}


func _init(rows: Array, seed_v: int, send_in: Callable, cfg_in: Dictionary = {}) -> void:
	players = {}
	players = {}
	bots = {}
	send = send_in
	send_cfg = cfg_in
	mode = int(cfg_in.get("mode", MatchRules.SOLO))
	match_id = cfg_in.get("match_id", "m0")
	rng = RandomNumberGenerator.new()
	rng.seed = seed_v
	flight = MapData.flight_points(rng)
	plane_len = flight["from"].distance_to(flight["to"])
	plane_seconds = maxf(plane_len / PLANE_SPEED, 4.0)
	zone = Zone.new(
		float(cfg_in.get("zone_start", Zone.start_radius_default())),
		rng,
		cfg_in.get("phases", [])
	)
	loot = LootField.new(rng)
	if not bool(cfg_in.get("no_loot", false)):
		loot.spawn_map_loot()
	var team_i := 0
	for r in rows:
		var rec := _new_sp(r)
		players[int(r["pid"])] = rec
		if bool(r.get("bot", false)):
			bots[int(r["pid"])] = BotBrain.new(rec, rng)
	next_snap = 1.0 / snap_hz


func _new_sp(r: Dictionary) -> Dictionary:
	var team := int(r.get("team", 0))
	var inv := Inventory.new_inventory()
	var spawn_wid := ""
	# Boot loadout option (tests / practice): humans start with the Vanguard AR
	# fully loaded and a topped light-ammo reserve. Off by default; enabled via
	# server config ("spawn_weapons": true).
	if bool(send_cfg.get("spawn_weapons", false)) and not bool(r.get("bot", false)):
		spawn_wid = "ar_vanguard"
		inv["slots"][Inventory.SLOT_PRIMARY] = spawn_wid
		Inventory.set_slot(inv, Inventory.SLOT_PRIMARY)
		inv["ammo"][ItemsDB.AMMO_LIGHT] = int(ItemsDB.AMMO_CAP[ItemsDB.AMMO_LIGHT])
	var sp := {
		"pid": int(r["pid"]),
		"name": str(r.get("name", "?")),
		"char": str(r.get("char", "ranger")),
		"team": team,
		"bot": bool(r.get("bot", false)),
		"state": State.PLANE,
		"pos": flight["from"],
		"yaw": 0.0,
		"vy": 0.0,
		"hp": 100.0,
		"armor": 0.0,
		"dead": false,
		"alive_ms": int(0),
		"last_seq": int(-1),
		"last_input": {"move": Vector2.ZERO, "sprint": false, "crouch": false, "jump": false, "deploy": false, "ability": false},
		"mags": {},
		"inv": inv,
		"next_fire": 0.0,
		"reload_until": -1.0,
		"reload_wid": "",
		"abil_locked": false,
		"abil_cd_until": -1.0,
		"abil_until": -1.0,
		"abil_kind": "",
		"abil_active": false,
		"heal_until": -1.0,
		"heal_kind": "",
		"kills": 0,
		"dmg_done": 0.0,
		"spectate_pid": 0,
	}
	if spawn_wid != "":
		sp["mags"][spawn_wid] = int(WeaponsDB.get_weapon(spawn_wid)["mag"])  # arrives loaded
	return sp


# ------------------------------------------------------------ access helpers

func get_sp(pid: int) -> Dictionary:
	return players.get(pid, {})


func same_team(a: Dictionary, b: Dictionary) -> bool:
	return int(a["team"]) == int(b["team"])


func push_event(ev: Dictionary) -> void:
	if evts.size() < 512:
		evts.append(ev)


func send_msg_event(to_pid: int, msg: String) -> void:
	push_event({"t": MatchEvents.MSG, "to": to_pid, "msg": msg})


# -------------------------------------------------------------- command dispatch

# d: already-decoded command {op:int, ...fields} — bots bypass raw wire.
func handle_packet(pid: int, d: Dictionary) -> void:
	if ended:
		return
	var op: int = int(d["op"])
	var sp: Dictionary = get_sp(pid)
	if op != Protocol.Op.PING and sp.is_empty():
		return
	match op:
		Protocol.Op.INPUT:
			_cmd_input(sp, d)
		Protocol.Op.FIRE:
			Combat.try_fire(self, pid, Vector3(d["dir"].x, d["dir"].y, d["dir"].z))
			var spf: Dictionary = get_sp(pid)
			spf["yaw"] = float(d["yaw"])
		Protocol.Op.USE_ITEM:
			_cmd_use(sp, str(d["kind"]))
		Protocol.Op.PICKUP:
			_cmd_pickup(sp)
		Protocol.Op.RELOAD:
			Combat.try_reload(self, sp)
		Protocol.Op.SWITCH_WEAPON:
			_cmd_switch(sp, int(d["slot"]))
		Protocol.Op.PING:
			_send(pid, Protocol.s_pong(float(d["t"])))
		Protocol.Op.SPECTATE:
			sp["spectate_pid"] = int(d["pid"])
		_:
			pass


func _cmd_input(sp: Dictionary, d: Dictionary) -> void:
	var seq := int(d["seq"])
	if seq <= int(sp["last_seq"]):
		return
	sp["last_seq"] = seq
	var move: Vector2 = d["move"]
	if move.length_squared() > 1.0:
		move = move.normalized()
	var prev_deploy := bool(sp["last_input"]["deploy"])
	var prev_jump := bool(sp["last_input"]["jump"])
	sp["last_input"] = {
		"move": move,
		"sprint": bool(d["sprint"]),
		"crouch": bool(d["crouch"]),
		"jump": bool(d["jump"]),
		"deploy": bool(d["deploy"]),
		"ability": bool(d["ability"]),
	}
	sp["yaw"] = float(d["yaw"])
	# landing correction hint (prediction reconcile is done client-side)
	var hint: Vector3 = d["pos"]
	if float(hint.y) < float(sp["pos"].y) - 40.0:
		# Impossible fall: trust server's own state
		pass
	if bool(d["deploy"]) and not prev_deploy:
		_try_deploy(sp)
	if bool(d["jump"]) and not prev_jump:
		_try_jump(sp)
	if bool(d["ability"]):
		if not bool(sp.get("abil_locked", false)):
			sp["abil_locked"] = true
			_try_ability(sp)
	else:
		sp["abil_locked"] = false


func _try_deploy(sp: Dictionary) -> void:
	if int(sp["state"]) != State.PLANE:
		return
	if plane_t <= DEPLOY_MIN_T:
		send_msg_event(int(sp["pid"]), "Too early to deploy.")
		return
	sp["state"] = State.CHUTE


func _try_jump(sp: Dictionary) -> void:
	if int(sp["state"]) != State.GROUND or bool(sp["dead"]):
		return
	if float(sp["vy"]) == 0.0:
		sp["vy"] = JUMP_V


func _try_ability(sp: Dictionary) -> void:
	if int(sp["state"]) != State.GROUND or bool(sp["dead"]):
		return
	if float(sp["abil_until"]) >= 0.0 and t <= float(sp["abil_until"]):
		return
	if t < float(sp["abil_cd_until"]):
		send_msg_event(int(sp["pid"]), "Ability cooling down.")
		return
	var ch: Dictionary = CharactersDB.get_character(str(sp["char"]))
	if ch.is_empty():
		return
	var kind := str(ch["ability"])
	sp["abil_kind"] = kind
	sp["abil_power"] = float(ch["ability_power"])
	sp["abil_active"] = true
	sp["abil_until"] = t + float(ch["ability_for_s"])
	sp["abil_cd_until"] = t + float(ch["ability_cd_s"])
	if kind == "bulwark":
		sp["armor"] = minf(sp["armor"] + float(ch["ability_power"]), 100.0)
		sp["abil_until"] = -1.0
		sp["abil_active"] = false
	push_event({"t": MatchEvents.ABILITY, "to": 0, "pid": int(sp["pid"]), "kind": kind})


func _cmd_use(sp: Dictionary, kind: String) -> void:
	if int(sp["state"]) != State.GROUND or bool(sp["dead"]):
		return
	var inv: Dictionary = sp["inv"]
	if not ItemsDB.is_heal(kind):
		return
	var n := int(inv["heals"].get(kind, 0))
	if n <= 0:
		send_msg_event(int(sp["pid"]), "No %s left." % str(ItemsDB.get_item(kind).get("name", kind)))
		return
	if float(sp["hp"]) >= 100.0:
		send_msg_event(int(sp["pid"]), "Health is already full.")
		return
	if float(sp["heal_until"]) >= 0.0 and t < float(sp["heal_until"]):
		return
	sp["heal_kind"] = kind
	sp["heal_until"] = t + float(ItemsDB.get_item(kind).get("use_s", 2.0))


func _cmd_pickup(sp: Dictionary) -> void:
	if int(sp["state"]) != State.GROUND or bool(sp["dead"]):
		send_msg_event(int(sp["pid"]), "Cannot loot while airborne.")
		return
	var xz := Vector2(sp["pos"].x, sp["pos"].z)
	var lid := loot.claimable_id_near(xz, PICKUP_R)
	if lid == 0:
		send_msg_event(int(sp["pid"]), "Nothing within reach.")
		return
	var rec := loot.claim(lid, int(sp["pid"]))
	if rec.is_empty():
		send_msg_event(int(sp["pid"]), "Already claimed by someone else.")
		return
	var kind := str(rec["item"])
	var wid := str(rec["wid"])
	if wid == "plate_res" or kind == ItemsDB.KIND_PLATE:
		sp["armor"] = minf(sp["armor"] + 50.0, 100.0)
		push_event({"t": MatchEvents.LOOT_CLAIMED, "to": 0, "lid": lid, "by": int(sp["pid"]), "item": ItemsDB.KIND_PLATE})
		return
	var res := Inventory.add_pickup(sp["inv"], kind, wid)
	if not res["ok"]:
		# un-claim so the item stays in the world
		for i in loot.items.size():
			if int(loot.items[i]["id"]) == lid:
				loot.items[i]["claimed_by"] = 0
		send_msg_event(int(sp["pid"]), "Inventory %s: %s." % ["full slots (2 weapons max)" if res["reason"] == "slots_full" else "full", res["reason"]])
		return
	if wid != "":
		var w := WeaponsDB.get_weapon(wid)
		sp["mags"][wid] = int(w["mag"])  # comes loaded
	var label: String = WeaponsDB.get_weapon(wid).get("name", kind) if wid != "" else str(ItemsDB.get_item(kind).get("name", kind))
	push_event({"t": MatchEvents.LOOT_CLAIMED, "to": 0, "lid": lid, "by": int(sp["pid"]), "item": label})


func _cmd_switch(sp: Dictionary, slot: int) -> void:
	if bool(sp["dead"]):
		return
	if slot < MatchSim.SLOT_NADE:
		Inventory.set_slot(sp["inv"], slot)
	elif slot == MatchSim.SLOT_NADE:
		if int(sp["inv"].get("nades", 0)) <= 0:
			send_msg_event(int(sp["pid"]), "No grenades.")
			return
		Inventory.set_slot(sp["inv"], SLOT_NADE)
	sp["reload_until"] = -1.0
	sp["reload_wid"] = ""


# ------------------------------------------------------------------- tick

func tick(dt: float) -> void:
	if ended:
		return
	t += dt
	plane_t = minf(plane_t + dt / plane_seconds, 1.0)

	# spawn/boarding + plane motion
	for sp in players.values():
		if bool(sp["dead"]):
			continue
		match int(sp["state"]):
			State.PLANE:
				sp["pos"] = flight["from"].lerp(flight["to"], plane_t)
				if plane_t >= 1.0:
					sp["state"] = State.CHUTE
				sp["alive_ms"] += int(dt * 1000.0)
			State.CHUTE:
				_step_chute(sp, dt)
				sp["alive_ms"] += int(dt * 1000.0)
			State.GROUND:
				_step_ground(sp, dt)
				sp["alive_ms"] += int(dt * 1000.0)

	# bots think & send commands through the same dispatch as human clients
	for bpid in bots:
		var brain: BotBrain = bots[bpid]
		var cmds: Array = brain.think(self, dt)
		for cmd in cmds:
			handle_packet(int(bpid), cmd)

	# grenades
	_step_grenades(dt)

	# heals
	for sp in players.values():
		if bool(sp["dead"]):
			continue
		if float(sp["heal_until"]) >= 0.0 and t >= float(sp["heal_until"]):
			var it := ItemsDB.get_item(str(sp["heal_kind"]))
			var inv: Dictionary = sp["inv"]
			if int(inv["heals"].get(str(sp["heal_kind"]), 0)) > 0:
				inv["heals"][str(sp["heal_kind"])] = int(inv["heals"][str(sp["heal_kind"])]) - 1
				sp["hp"] = minf(sp["hp"] + float(it.get("heal", 0.0)), 100.0)
				push_event({"t": MatchEvents.HEALED, "to": int(sp["pid"]), "heal": float(it.get("heal", 0.0))})
			sp["heal_until"] = -1.0

	# reload completions
	for sp in players.values():
		if bool(sp["dead"]):
			continue
		if float(sp["reload_until"]) >= 0.0 and t >= float(sp["reload_until"]):
			Combat.finish_reload(sp)

	# ability expiry
	for sp in players.values():
		if bool(sp["abil_active"]) and t >= float(sp["abil_until"]):
			sp["abil_active"] = false
			sp["abil_until"] = -1.0

	# zone
	if zone.step(dt):
		push_event({
			"t": MatchEvents.ZONE_ANNOUNCE, "to": 0,
			"phase_idx": int(zone.phase_idx),
			"radius": float(zone.next_radius),
			"center": Vector3(zone.next_center.x, 0, zone.next_center.z),
		})
	_zone_damage(dt)

	_check_victory()


func _step_chute(sp: Dictionary, dt: float) -> void:
	var pos: Vector3 = sp["pos"]
	var move: Vector2 = sp["last_input"]["move"]
	var fall := dt * MatchRules.SPEED_CHUTE_FALL
	var drift := move.limit_length(1.0) * (dt * MatchRules.SPEED_CHUTE_DRIFT)
	var nx := clampf(pos.x + drift.x, -MapData.HARD_R, MapData.HARD_R)
	var nz := clampf(pos.z + drift.y, -MapData.HARD_R, MapData.HARD_R)
	var ny := pos.y - fall
	var g := float(MapData.height(nx, nz))
	if ny <= g:
		ny = g
		sp["vy"] = 0.0
		sp["state"] = State.GROUND
	sp["pos"] = Vector3(nx, ny, nz)


func _step_ground(sp: Dictionary, dt: float) -> void:
	var inv: Dictionary = sp["inv"]
	var li: Dictionary = sp["last_input"]
	var move: Vector2 = li["move"]
	var crouch := bool(li["crouch"])
	var sprint := bool(li["sprint"]) and not crouch
	var speed := MatchRules.SPEED_CROUCH if crouch else (MatchRules.SPEED_SPRINT if sprint else MatchRules.SPEED_WALK)
	if bool(sp["abil_active"]) and sp["abil_kind"] == "dash":
		speed *= maxf(float(sp["abil_power"]), 1.0)
	var pos: Vector3 = sp["pos"]
	# vertical (jump arc)
	var vy := float(sp["vy"])
	if vy != 0.0:
		vy -= GRAVITY * dt
		var newy := pos.y + vy * dt
		if newy <= MapData.height(pos.x, pos.z) - 0.001:
			newy = MapData.height(pos.x, pos.z)
			vy = 0.0
		pos.y = newy
		sp["vy"] = vy
	# walk
	if move.length_squared() > 0.0001:
		var dir := move.limit_length(1.0)
		var nx := pos.x + dir.x * speed * dt
		var nz := pos.z + dir.y * speed * dt
		var clampv := MapData.clamped_to_bounds(nx, nz)
		var y := pos.y if float(sp["vy"]) != 0.0 else MapData.height(clampv.x, clampv.y)
		var res := MapData.resolve_circle_xz(clampv.x, clampv.y, 0.45, y)
		pos.x = res.x
		pos.z = res.z
		if float(sp["vy"]) == 0.0:
			pos.y = MapData.height(res.x, res.z)
	sp["pos"] = pos


func _step_grenades(dt: float) -> void:
	var keep := []
	for g in grenades:
		var pos: Vector3 = g["pos"]
		var vel: Vector3 = g["vel"]
		vel.y -= GRAVITY * dt
		pos += vel * dt
		g["vel"] = vel
		var ground := float(MapData.height(pos.x, pos.z))
		if bool(pos.y <= ground + 0.2 or t - float(g["born"]) > 3.0):
			if pos.y < ground:
				pos.y = ground
			_explode_grenade(g, pos)
		else:
			g["pos"] = pos
			keep.append(g)
	grenades = keep


func _explode_grenade(g: Dictionary, pos: Vector3) -> void:
	push_event({"t": MatchEvents.GRENADE_EXPLODED, "to": 0, "pos": pos, "by": int(g["pid"])})
	var shooter: Dictionary = get_sp(int(g["pid"]))
	for sp in players.values():
		if bool(sp["dead"]) or int(sp["state"]) != State.GROUND:
			continue
		var d := float(Vector3(sp["pos"].x - pos.x, sp["pos"].y - pos.y, sp["pos"].z - pos.z).length())
		if d > NADE_R:
			continue
		var raw := maxf(NADE_DMG * (1.0 - d / NADE_R), 5.0)
		if not shooter.is_empty() and same_team(shooter, sp) and int(sp["pid"]) != int(shooter["pid"]):
			continue
		var res := Damage.apply(raw, float(sp["hp"]), float(sp["armor"]))
		sp["hp"] = res["hp"]
		sp["armor"] = res["armor"]
		sp["heal_until"] = -1.0
		push_event({"t": MatchEvents.HIT_TAKEN, "to": int(sp["pid"]), "dmg": res["dealt"], "hp": res["hp"], "armor": res["armor"], "head": 0})
		if int(sp["pid"]) != int(g["pid"]) and not shooter.is_empty():
			var ksp: Dictionary = shooter
			ksp["dmg_done"] += res["dealt"]
		if float(sp["hp"]) <= 0.0:
			eliminate(int(sp["pid"]), int(g["pid"]), "grenade_skyring", "grenade")


func _zone_damage(dt: float) -> void:
	var cc := zone.cur_center
	var cr := zone.cur_radius
	for sp in players.values():
		if bool(sp["dead"]) or int(sp["state"]) != State.GROUND:
			continue
		var d := Vector2(sp["pos"].x - cc.x, sp["pos"].z - cc.z).length()
		if d > cr and zone.dps > 0.0:
			var dmg := zone.dps * dt
			sp["hp"] = maxf(sp["hp"] - dmg, 0.0)
			sp["heal_until"] = -1.0
			if float(sp["hp"]) <= 0.0:
					eliminate(int(sp["pid"]), 0, "", "zone")
func register_hit(shooter: Dictionary, victim_pid: int, wid: String, w: Dictionary, dist: float, head: bool) -> void:
	if ended:
		return
	var victim: Dictionary = get_sp(victim_pid)
	if victim.is_empty() or bool(victim["dead"]):
		return
	if same_team(shooter, victim) and int(shooter["pid"]) != victim_pid:
		return
	var raw := float(w.get("dmg", 10.0)) * (float(w.get("hs", 1.0)) if head else 1.0)
	var fall := Damage.falloff(w, dist)
	raw *= fall
	var res := Damage.apply(raw, float(victim["hp"]), float(victim["armor"]))
	victim["armor"] = res["armor"]
	victim["hp"] = res["hp"]
	victim["heal_until"] = -1.0
	var dealt: float = res["dealt"]
	shooter["dmg_done"] += dealt
	push_event({"t": MatchEvents.HIT_TAKEN, "to": victim_pid, "dmg": dealt, "hp": res["hp"], "armor": res["armor"], "head": 1 if head else 0})
	push_event({"t": MatchEvents.HIT_DEALT, "to": int(shooter["pid"]), "dmg": dealt, "kill": 0})
	if float(victim["hp"]) <= 0.0:
		eliminate(victim_pid, int(shooter["pid"]), wid, "weapon")


func eliminate(victim_pid: int, killer_pid: int, wid: String, cause: String) -> void:
	var victim: Dictionary = get_sp(victim_pid)
	if victim.is_empty() or bool(victim["dead"]):
		return
	victim["dead"] = true
	victim["state"] = State.DEAD
	dead_at[victim_pid] = t
	order.append(victim_pid)
	loot.drops_from_inventory(victim["inv"], victim["pos"])
	push_event({"t": MatchEvents.ELIMINATION, "to": 0, "killer": killer_pid, "victim": victim_pid, "weapon": wid, "cause": cause})
	if killer_pid >= 0:
		var ksp: Dictionary = get_sp(killer_pid)
		if not ksp.is_empty():
			ksp["kills"] = int(ksp["kills"]) + 1
			push_event({"t": MatchEvents.HIT_DEALT, "to": killer_pid, "dmg": 0.0, "kill": 1})
	# spectate suggestion for a dead human
	if not bool(victim["bot"]):
		var alive := []
		for sp in players.values():
			if not bool(sp["dead"]):
				alive.append(sp)
		if alive.size() > 0:
			var pick: Dictionary = alive[rng.randi() % alive.size()]
			push_event({"t": MatchEvents.SPECTATE_OFFER, "to": victim_pid, "pid": int(pick["pid"]), "name": str(pick["name"])})


func _check_victory() -> void:
	var alive_teams := {}
	for sp in players.values():
		if not bool(sp["dead"]):
			alive_teams[int(sp["team"])] = 1
	if alive_teams.size() > 1:
		return
	GameLog.info("sv", "victory: alive_teams=%d players=%d" % [alive_teams.size(), players.size()])
	winner_team = -1
	for k in alive_teams:
		winner_team = int(k)
	ended = true
	var alive := []
	for sp in players.values():
		if not bool(sp["dead"]):
			alive.append(sp)
	# placements: winner team 1; remaining by reverse elimination order
	var place := 2
	for i in range(order.size() - 1, -1, -1):
		var pid := int(order[i])
		rows_cache.append({"pid": pid, "place": place})
		place += 1
	# finish event will be sent by net layer after the last snapshot.
	push_event({"t": MatchEvents.ZONE_ANNOUNCE, "to": 0, "phase_idx": 99, "radius": zone.cur_radius, "center": zone.cur_center})


func on_peer_left(pid: int) -> void:
	var sp: Dictionary = get_sp(pid)
	if sp.is_empty() or bool(sp["dead"]):
		return
	eliminate(pid, pid, "", "left")


# ------------------------------------------------------------- snapshots

func broadcast_snapshots() -> bool:
	# returns true if match just ended (last snapshot sent)
	if next_snap > t:
		return false
	next_snap = t + 1.0 / snap_hz
	for pid in players:
		var sp: Dictionary = players[pid]
		if bool(sp["bot"]):
			continue
		_send_pid_snapshot(int(pid), sp)
	var was_end := ended
	if was_end:
		_send_match_end()
	evts.clear()
	return was_end


func _send(pid: int, bytes: PackedByteArray) -> void:
	if send.is_valid():
		send.call(pid, bytes)


func _send_pid_snapshot(pid: int, sp: Dictionary) -> void:
	var others := []
	for p in players.values():
		if int(p["pid"]) == pid:
			continue
		if bool(p["dead"]):
			continue
		others.append({
			"pid": int(p["pid"]), "pos": p["pos"], "yaw": float(p["yaw"]),
			"state": int(p["state"]), "char": str(p["char"]), "name": str(p["name"]),
			"team": int(p["team"]), "alive": 1,
			"held": Inventory.active_weapon(p["inv"]),
		})
	var view_evts := []
	for ev in evts:
		var eto: int = int(ev.get("to", 0))
		if eto != 0 and eto != pid:
			continue
		var copy: Dictionary = ev.duplicate()
		if copy.get("t", 0) == MatchEvents.LOOT_CLAIMED:
			copy["yours"] = int(int(copy.get("by", 0)) == pid)
		view_evts.append(copy)
	var wid := Inventory.active_weapon(sp["inv"])
	var w := WeaponsDB.get_weapon(wid)
	var you := {
		"pos": sp["pos"], "state": int(sp["state"]),
		"hp": float(sp["hp"]), "armor": float(sp["armor"]),
		"weapon": wid,
		"mag": int(sp["mags"].get(wid, 0)) if w.size() > 0 else 0,
		"reserve": int(sp["inv"]["ammo"].get(WeaponsDB.ammo_type(wid), 0)) if w.size() > 0 else 0,
		"slot": int(sp["inv"]["slot"]),
		"nades": int(sp["inv"]["nades"]),
		"heals_a": int(sp["inv"]["heals"].get(ItemsDB.KIND_MEDKIT, 0)),
		"heals_b": int(sp["inv"]["heals"].get(ItemsDB.KIND_BANDAGE, 0)),
		"reload_left": maxf(float(sp["reload_until"]) - t, 0.0) if float(sp["reload_until"]) >= 0.0 else 0.0,
		"ability_left": maxf(float(sp["abil_cd_until"]) - t, 0.0),
		"alive": 0 if bool(sp["dead"]) else 1,
	}
	_send(pid, Protocol.s_snapshot(int(t * 1000.0), zone.state_dict(), you, others, view_evts))


func _send_match_end() -> void:
	var teams_of := {}
	for pid in players:
		teams_of[pid] = int(players[pid]["team"])
	var ranked := []  # place, pid
	for alive_row in players.values():
		if not bool(alive_row["dead"]):
			ranked.append({"pid": int(alive_row["pid"]), "place": 1})
	var next_place := 2
	for i in range(order.size() - 1, -1, -1):
		var pid := int(order[i])
		ranked.append({"pid": pid, "place": next_place})
		next_place += 1
	var place_of := {}
	for r in ranked:
		place_of[int(r["pid"])] = int(r["place"])
	var rows := []
	for pid in players:
		var sp: Dictionary = players[pid]
		if bool(sp["bot"]):
			continue
		rows.append({
			"pid": int(pid),
			"name": str(sp["name"]),
			"placement": int(place_of.get(pid, 99)),
			"kills": int(sp["kills"]),
			"dmg": float(sp["dmg_done"]),
			"alive_ms": int(sp["alive_ms"]),
			"alive": false if bool(sp["dead"]) else true,
		})
	for pid in players:
		var sp: Dictionary = players[pid]
		if bool(sp["bot"]):
			continue
		_send(int(pid), Protocol.s_match_end(winner_team, rows))


# helpers used by bots
func claimable_near(sp_ref: Dictionary, radius: float) -> int:
	var lid := loot.claimable_id_near(Vector2(sp_ref["pos"].x, sp_ref["pos"].z), radius)
	return lid


func enemy_visible(from_pos: Vector3, eye_h: float, to_sp: Dictionary) -> bool:
	var origin := Vector3(from_pos.x, from_pos.y + eye_h, from_pos.z)
	var target := Vector3(to_sp["pos"].x, to_sp["pos"].y + 1.1, to_sp["pos"].z)
	var wt := MapData.seg_blocked_t(origin, target)
	return wt < 0.0 or wt > 0.99
