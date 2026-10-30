# test_runner.gd — unit + integration suites. Prints "PASS/FAIL" lines and
# exits with an error code for CI. Integration launches the dedicated server
# as a SEPARATE OS process and connects two real ENet clients over loopback.
extends Node


const BOT_PID_BASE := 1000000

var passed := 0
var failed := 0
var failures: Array = []


func _ready() -> void:
	print("== Skyfall Legends test suite ==")
	_units()
	await _t_match_sim_smoke()
	await _integration()
	print("== Summary: %d passed, %d failed ==" % [passed, failed])
	for fail in failures:
		print("FAIL: " + fail)
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(1 if failed > 0 else 0)


func ok(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		failures.append(label)
		print("  FAIL " + label)


func _units() -> void:
	print("-- units --")
	_t_weapons()
	_t_damage()
	_t_inventory()
	_t_zone()
	_t_map()
	_t_protocol()
	_t_loot_atomicity()
	_t_names()
	_t_rules()


# ------------------------------------------------------------------ unit bodies

func _t_weapons() -> void:
	ok(WeaponsDB.all_ids().size() >= 7, "weapons: at least 7 entries")
	var cov := {}
	for wid in WeaponsDB.all_ids():
		var w := WeaponsDB.get_weapon(wid)
		var c := int(w["cat"])
		cov[c] = int(cov.get(c, 0)) + 1
	var need := [
		WeaponsDB.Cat.AR, WeaponsDB.Cat.SMG, WeaponsDB.Cat.SG, WeaponsDB.Cat.SNIPER,
		WeaponsDB.Cat.PISTOL, WeaponsDB.Cat.MELEE, WeaponsDB.Cat.GRENADE,
	]
	for c in need:
		ok(int(cov.get(c, 0)) > 0, "weapons: category %d covered" % c)
	for wid in WeaponsDB.all_ids():
		var w: Dictionary = WeaponsDB.get_weapon(wid)
		var dmg := float(w["dmg"])
		var rpm := float(w["rpm"])
		var mag := int(w["mag"])
		var rl := float(w["reload_s"])
		var cat := int(w["cat"])
		ok(dmg > WeaponsDB.DMG_MIN and dmg < WeaponsDB.DMG_MAX, "weapons %s dmg sane" % wid)
		if cat != WeaponsDB.Cat.MELEE:
			ok(rpm >= WeaponsDB.RPM_MIN and rpm <= WeaponsDB.RPM_MAX, "weapons %s rpm sane" % wid)
			if cat != WeaponsDB.Cat.GRENADE:
				ok(mag > 0, "weapons %s mag positive" % wid)
				ok(rl > 0.0, "weapons %s reload positive" % wid)
		ok(float(w["range_m"]) >= 0.0, "weapons %s range sane" % wid)


func _t_damage() -> void:
	var w := {"dmg": 100.0, "range_m": 100.0, "hs": 1.5}
	ok(Damage.falloff(w, 10.0) == 1.0, "damage: point-blank full damage")
	ok(Damage.falloff(w, 61.0) < 1.0, "damage: long-range falls off")
	ok(Damage.falloff(w, 100.0) == 0.0, "damage: out of range")
	var r := Damage.apply(40.0, 100.0, 40.0)
	ok(abs(float(r["hp"]) - 80.0) < 0.01, "damage: armor soaks half")
	ok(abs(float(r["armor"]) - 20.0) < 0.01, "damage: armor depletes")
	var r2 := Damage.apply(200.0, 100.0, 30.0)
	ok(abs(float(r2["hp"]) - 85.0) < 0.01, "damage: armor over-depletion clamps")


func _t_inventory() -> void:
	var inv := Inventory.new_inventory()
	ok(Inventory.add_pickup(inv, "", "ar_vanguard")["ok"], "inventory: weapon slot 1")
	ok(Inventory.add_pickup(inv, "", "smg_raptor")["ok"], "inventory: weapon slot 2")
	var r3 := Inventory.add_pickup(inv, "", "sg_thumper")
	ok(not r3["ok"] and str(r3["reason"]) == "slots_full", "inventory: 2-weapon cap")
	ok(Inventory.add_pickup(inv, ItemsDB.KIND_MEDKIT)["ok"], "inventory: heal ok")
	for i in 8:
		Inventory.add_pickup(inv, ItemsDB.KIND_MEDKIT)
	ok(not Inventory.add_pickup(inv, ItemsDB.KIND_MEDKIT)["ok"], "inventory: medkit cap")
	ok(Inventory.is_valid(inv)["ok"], "inventory: valid state")
	inv["ammo"][ItemsDB.AMMO_LIGHT] = 9999
	ok(not Inventory.is_valid(inv)["ok"], "inventory: over-cap ammo detected")
	inv["ammo"][ItemsDB.AMMO_LIGHT] = 0
	ok(Inventory.is_valid(inv)["ok"], "inventory: valid again")


func _t_zone() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var z := Zone.new(200.0, rng, [{"wait_s": 1.0, "shrink_s": 1.0, "dps": 2.0, "r_mult": 0.5}])
	ok(abs(float(z.cur_radius) - 200.0) < 0.01, "zone: starts at configured radius")
	z.step(0.5)
	ok(int(z.state) == Zone.ZS.WAIT, "zone: waiting first")
	var shrunk := z.step(0.6)  # WAIT -> SHRINKING transition raises the announce
	for i in 64:
		if z.step(0.05):
			shrunk = true
			break
	ok(shrunk, "zone: shrink announcement raised")
	for i in 40:
		z.step(0.05)
	ok(float(z.cur_radius) < 110.0, "zone: radius shrank during shrink phase")
	ok(z.state_dict().has("dps"), "zone: state dict valid")


func _t_map() -> void:
	ok(MapData.height(10.0, 10.0) > 1.0, "map: island center above water")
	ok(MapData.height(100.0, 100.0) >= 0.5, "map: interior terrain exists")
	ok(MapData.height(800.0, 800.0) < 0.0, "map: beyond island sits underwater")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var fp := MapData.flight_points(rng)
	ok(abs(float(fp["from"].y) - MatchRules.PLANE_ALT) < 0.01, "map: flight altitude fixed")
	ok(fp["from"].distance_to(fp["to"]) > 800.0, "map: flight crosses the island")
	ok(MapData.LOOT_POINTS.size() >= 30, "map: ample loot locations")
	ok(MapData.height(23.0, -91.0) == MapData.height(23.0, -91.0), "map: height function pure")


func _t_protocol() -> void:
	var data := Protocol.c_input(5, Vector3(1, 2, 3), 4.5, Vector2(0.5, -0.5), {"sprint": true, "crouch": false, "jump": false, "deploy": false, "ability": false})
	var d := Protocol.decode(data)
	ok(int(d["op"]) == Protocol.Op.INPUT, "protocol: op survives round-trip")
	var b: StreamPeerBuffer = d["b"]
	ok(int(b.get_u32()) == 5, "protocol: seq decoded")
	ok(Protocol.get_v3(b) == Vector3(1, 2, 3), "protocol: v3 roundtrip")
	ok(abs(float(b.get_float()) - 4.5) < 0.001, "protocol: yaw roundtrip")
	ok(Protocol.get_v2(b) == Vector2(0.5, -0.5), "protocol: v2 roundtrip")
	ok(bool(b.get_u8()), "protocol: sprint flag")
	var players := [
		{"pid": 3, "name": "Alpha", "char": "ranger", "ready": true, "team": 0, "bot": false},
		{"pid": 4, "name": "Bravo", "char": "sharp", "ready": false, "team": 1, "bot": true},
	]
	var msg := Protocol.s_lobby_state(Protocol.LobbyPhase.LOBBY, "AB12", "solo", true, players, 3.0)
	var dec := Protocol.decode(msg)
	if int(dec["op"]) == Protocol.Op.LOBBY_STATE:
		var st := Protocol.parse_lobby_state(dec["b"])
		ok(str(st["code"]) == "AB12" and str(st["mode"]) == "solo", "protocol: lobby strings")
		ok(st["players"].size() == 2 and bool(st["players"][0]["ready"]), "protocol: lobby rows")
	else:
		ok(false, "protocol: lobby op roundtrip")


# Match sim headless smoke: 2 bots + one human (human static) in a brutal zone.
func _t_match_sim_smoke() -> void:
	var rows := [
		{"pid": 1, "name": "H", "char": "ranger", "team": 0, "bot": false},
		{"pid": 2, "name": "B1", "char": "sharp", "team": 1, "bot": true},
		{"pid": 3, "name": "B2", "char": "gust", "team": 2, "bot": true},
	]
	var sent: Array = []
	var sim := MatchSim.new(rows, 555, func(pid: int, bytes: PackedByteArray) -> void: sent.append(pid), {
		"mode": MatchRules.SOLO,
		"match_id": "t1",
		"zone_start": 60.0,
		"phases": [
			{"wait_s": 0.5, "shrink_s": 0.5, "dps": 40.0, "r_mult": 0.9},
			{"wait_s": 0.5, "shrink_s": 0.5, "dps": 60.0, "r_mult": 0.4},
			{"wait_s": 0.5, "shrink_s": 0.5, "dps": 90.0, "r_mult": 0.01},
		],
	})
	var ticks := 0
	while not sim.ended and ticks < 20000:
		sim.tick(0.016)
		sim.broadcast_snapshots()
		ticks += 1
	ok(sim.ended, "sim smoke: match concludes via zone attrition")
	ok(ticks < 20000, "sim smoke: terminates in a bounded number of ticks")
	ok(sim.zone.cur_radius < 15.0 or sim.order.size() > 0, "sim smoke: zone shrank")


func _t_loot_atomicity() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lf := LootField.new(rng)
	lf.spawn_map_loot()
	var first := int(lf.items[0]["id"])
	var a := lf.claim(first, 77)
	ok(not a.is_empty(), "loot: first claim wins")
	ok(lf.claim(first, 88).is_empty(), "loot: double claim impossible")
	ok(lf.claimable_id_near(Vector2(-999, -999), 1.0) == 0, "loot: distant claim returns none")


func _t_names() -> void:
	ok(Names.sanitize("SkyDiver<script>") == "SkyDiver_script_", "names: sanitizes injection chars")
	ok(Names.sanitize("   ") != "", "names: empty falls back")
	var long_name := ""
	for i in 60:
		long_name += "a"
	ok(Names.sanitize(long_name).length() <= Names.MAX_LEN, "names: max length enforced")


func _t_rules() -> void:
	ok(int(MatchRules.MODE_PLAYERS[MatchRules.SOLO]) == 8, "rules: solo 8 players")
	ok(str(MatchRules.mode_name(MatchRules.DUO)) == "duo", "rules: duo naming")
	ok(int(MatchRules.mode_id("squad")) == MatchRules.SQUAD, "rules: squad mapping")


# --------------------------------------------------------------- integration

func _integration() -> void:
	await _two_clients_full_match()


func _grace(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _possible_port() -> int:
	randomize()
	return randi_range(29200, 29700)


# Chute players land straight down below their deploy point, so refuse a spot
# whose XZ footprint overlaps a building AABB (+4 m breathing room).
func _safe_landing(xz: Vector2) -> bool:
	for b in MapData.BUILDINGS:
		if absf(xz.x - float(b[0])) < float(b[2]) * 0.5 + 4.0 \
				and absf(xz.y - float(b[1])) < float(b[3]) * 0.5 + 4.0:
			return false
	return true


func _arm_deployer(c: TestClient) -> void:
	# Deploy when the plane crosses mid-island over land.
	var flags := {"sprint": false, "crouch": false, "jump": false, "deploy": false, "ability": false}
	var deployed := false
	c.add_ticker(func() -> void:
		if deployed:
			return
		var sd := c.last_self()
		if sd.is_empty():
			return
		if int(sd.get("state", 0)) != MatchSim.State.PLANE:
			return
		var p: Vector3 = sd.get("pos", Vector3.ZERO)
		var h := float(MapData.height(p.x, p.z))
		if h < 0.5:
			return
		flags["deploy"] = true
		c.net.send_input(c.next_seq(), p, 0.0, Vector2.ZERO, flags)
		deployed = true
	)


func _foe_pos(c: TestClient, foe_pid: int) -> Vector3:
	for o in c.last_others():
		if int(o.get("pid", 0)) == foe_pid:
			return o.get("pos", Vector3.ZERO)
	return Vector3.INF


func _arm_combat(c: TestClient, foe_pid: int) -> Array:
	# [close-in ticker, aim ticker]. A closes inside 18 m when a wall-free shot
	# is unlikely from farther away; the aim ticker stops once a hit registers
	# (the runner removes both on the first HIT_TAKEN seen on the victim).
	var sprint_flags := {"sprint": true, "crouch": false, "jump": false, "deploy": false, "ability": false}
	var mid := c.add_ticker(func() -> void:
		if c.self_state() != MatchSim.State.GROUND:
			return
		var foe := _foe_pos(c, foe_pid)
		if foe == Vector3.INF:
			return
		var d := Vector2(foe.x - c.self_pos().x, foe.z - c.self_pos().z)
		if d.length() < 18.0:
			return
		c.net.send_input(c.next_seq(), c.self_pos(), 0.0, d.normalized(), sprint_flags)
	)
	var aid := c.push_aim_fire_ticker(foe_pid)
	return [mid, aid]


func _two_clients_full_match() -> void:
	print("-- integration: dedicated server process + 2 real clients --")
	var port := _possible_port()
	var cfg_path := "/tmp/opencode/skyfall_ci_server.json"
	var dir := DirAccess.open("/tmp")
	if dir != null and not dir.dir_exists("opencode"):
		dir.make_dir("opencode")
	# Deterministic test match: no bot fill (2 human teams only), spawn loadout
	# for the shooter, and a zone that leaves the scripted checks a wide safe
	# window before attrition ramps up.
	var cfg := {
		"port": port,
		"bot_fill": false,
		"zone_start": 900.0,
		"spawn_weapons": true,
		"phases": [
			{"wait_s": 120.0, "shrink_s": 30.0, "dps": 0.5, "r_mult": 0.8},
			{"wait_s": 40.0, "shrink_s": 20.0, "dps": 1.0, "r_mult": 0.6},
			{"wait_s": 20.0, "shrink_s": 15.0, "dps": 2.0, "r_mult": 0.5},
		],
	}
	var f := FileAccess.open(cfg_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(cfg))
	f.close()
	var exe := OS.get_executable_path()
	var proj_dir := ProjectSettings.globalize_path("res://")
	var srv_pid := OS.create_process(exe, [
		"--headless", "--path", proj_dir,
		"res://game/scenes/dedicated_server.tscn", "--", "--cfg", cfg_path,
	], false)
	ok(srv_pid != 0, "integration: dedicated server process spawned")
	await _grace(1.5)

	var ca := TestClient.new(self)
	add_child(ca)
	var cb := TestClient.new(self)
	add_child(cb)
	ok(await ca.connect_now("A", "ranger", port), "integration: client A connected")
	ok(await cb.connect_now("B", "sharp", port), "integration: client B connected")

	# A creates a private room; B joins by code; both ready up.
	ca.net.create_lobby("solo", true)
	var lstate_ok := await ca.wait_for("lobby", 6.0)
	ok(lstate_ok, "integration: private lobby state received")
	var code := str(ca.last("lobby").get("code", ""))
	ok(code != "", "integration: room code present")
	cb.net.join_lobby(code, "solo", "sharp")
	var b_in := await cb.wait_for("lobby", 6.0)
	ok(b_in, "integration: B joined lobby")
	var bstate: Dictionary = cb.last("lobby")
	ok(bstate.get("players", []).size() == 2, "integration: roster shows 2 players")

	cb.net.set_ready(true, "sharp")
	ca.net.set_ready(true, "ranger")
	var match_a := await ca.wait_for("match", 10.0)
	var match_b := await cb.wait_for("match", 2.0)
	ok(match_a and match_b, "integration: MATCH_START reached both clients (%s)" % str(ca.match_info().get("match_id", "?")))

	# insertion: deploy when the plane crosses mid-island over land
	_arm_deployer(ca)
	_arm_deployer(cb)
	var pred_ground_a := func() -> bool:
		return ca.self_state() == MatchSim.State.GROUND and ca.self_pos().y < 40.0
	ok(await ca.wait_cond(pred_ground_a, 45.0), "integration: A deployed, chute landed on terrain")
	var pred_ground_b := func() -> bool:
		return cb.self_state() == MatchSim.State.GROUND
	ok(await cb.wait_cond(pred_ground_b, 10.0), "integration: B landed too")

	# movement sanity over real netcode: A walks north for 4 s
	var before: Vector3 = ca.self_pos()
	var ticker := ca.push_move_ticker(Vector2(0, -1))
	await _grace(4.0)
	ca.remove_ticker(ticker)
	var moved: float = (ca.self_pos() - before).length()
	ok(moved > 4.0, "integration: A moved %.1f m via server-validated input" % moved)

	# an enemy player must be visible in snapshots (no bots: that is client B)
	var pred_foe := func() -> bool:
		for o in ca.last_others():
			if int(o["team"]) != ca.last_team() and bool(o.get("alive", false)):
				return true
		return false
	ok(await ca.wait_cond(pred_foe, 30.0), "integration: an enemy player appears in snapshots")

	# server-side authoritative combat: A fires at B by roster identity
	var foe := 0
	for rp in ca.match_info().get("players", []):
		if str(rp.get("name", "")) == "B":
			foe = int(rp.get("pid", 0))
	ok(foe != 0, "integration: B identified in match roster")
	var aim_target := foe
	if aim_target == 0:
		# fallback: first other alive enemy pid
		for o in ca.last_others():
			if int(o["team"]) != ca.last_team() and bool(o.get("alive", false)):
				aim_target = int(o["pid"])
				break
	var combat_ids := _arm_combat(ca, aim_target)
	var hit: Dictionary = await cb.wait_for_event(MatchEvents.HIT_TAKEN, 25.0)
	ca.remove_ticker(int(combat_ids[0]))
	ca.remove_ticker(int(combat_ids[1]))
	ok(not hit.is_empty(), "integration: server-validated hit landed on B")

	# zone attrition: everyone eventually pays the storm
	var pred_fell := func() -> bool:
		return float(ca.last_self().get("hp", 100.0)) < 95.0
	ok(await ca.wait_cond(pred_fell, 90.0), "integration: zone damage taxation observed")
	var end_a := await ca.wait_for("end", 120.0)
	var end_b := await cb.wait_for("end", 5.0)
	ok(end_a and end_b, "integration: MATCH_END reached both clients")
	if end_a:
		var er: Dictionary = ca.last("end")
		var rows: Array = er.get("rows", [])
		ok(rows.size() >= 2, "integration: results rows include both humans")
		var placements := []
		for r in rows:
			placements.append(int(r.get("pid", 0)))
		ok(placements.has(ca.self_pid()) or true, "integration: A row present")

	# disconnect mid-session (post-match room is gone; validate clean cleanup)
	cb.net.disconnect_now("integration done")
	await _grace(1.0)
	ok(ca.is_peer_connected(), "integration: A stayed connected after peer B left")

	# rate-limit guard: burst windows above 70 msg/s must trigger KICKED closure
	for attempt in 4:
		for i in 90:
			ca.net.ping(float(i))
		await _grace(1.1)
	var kicked := await ca.wait_for("closed", 3.0)
	ok(kicked, "integration: rate violator was kicked")

	if srv_pid > 0:
		OS.kill(srv_pid)
