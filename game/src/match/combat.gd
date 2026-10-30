# combat.gd — server-authoritative fire/reload validation. The client only ever
# supplies an aim direction; rate-of-fire, ammo, LOS, falloff and damage are
# decided here, on the server, deterministically.
class_name Combat
extends RefCounted


const EYE_STAND := 1.55
const EYE_CROUCH := 1.05
const BODY_R := 0.45
const BODY_TOP := 1.65
const BODY_BOT := 0.35
const HEAD_MIN := 1.38
const HEAD_MAX := 1.72
const MUZZLE_FWD := 0.5
const NADE_SPEED := 14.0
const NADE_UP := 4.0


# ------------------------------------------------------------------- firing

# Attempts one trigger pull. Appends authoritative events to m.evts.
static func try_fire(m: MatchSim, pid: int, dir_in: Vector3) -> void:
	var sp: Dictionary = m.get_sp(pid)
	if sp.is_empty() or bool(sp["dead"]):
		return
	if int(sp["state"]) != MatchSim.State.GROUND:
		return
	if m.t < float(sp["next_fire"]):
		return
	var inv: Dictionary = sp["inv"]
	var slot := int(inv["slot"])

	if slot == MatchSim.SLOT_NADE:
		if not Inventory.consume_grenade(inv):
			return
		sp["next_fire"] = m.t + 1.0
		var ndir := dir_in.normalized() if dir_in.length_squared() > 0.0001 else Vector3.FORWARD
		var muzzle := Vector3(sp["pos"].x, sp["pos"].y + 1.3, sp["pos"].z) + ndir * 0.6
		m.launch_grenade(pid, muzzle, ndir * NADE_SPEED + Vector3.UP * NADE_UP)
		return

	var wid := Inventory.active_weapon(inv)
	var w := WeaponsDB.get_weapon(wid)
	if w.is_empty():
		return
	var cat := int(w["cat"])
	var interval := 60.0 / maxf(float(w["rpm"]), 1.0)
	if bool(sp["abil_active"]) and sp["abil_kind"] == "gutshot":
		interval *= float(sp["abil_power"])  # ability value < 1.0 -> faster

	if cat == WeaponsDB.Cat.MELEE:
		sp["next_fire"] = m.t + interval
		_melee_hit(m, sp, wid, w, dir_in)
		return

	# ranged: server-only ammo gate
	var mags: Dictionary = sp["mags"]
	var have := int(mags.get(wid, 0))
	if have <= 0:
		try_reload(m, sp)
		return
	mags[wid] = have - 1
	sp["next_fire"] = m.t + interval

	_ranged_hit(m, sp, wid, w, dir_in)


static func _ranged_hit(m: MatchSim, sp: Dictionary, wid: String, w: Dictionary, dir_in: Vector3) -> void:
	var dir := dir_in.normalized() if dir_in.length_squared() > 0.0001 else Vector3.FORWARD
	var eye_h := EYE_CROUCH if bool(sp["crouch"]) else EYE_STAND
	var origin := Vector3(sp["pos"].x, sp["pos"].y + eye_h, sp["pos"].z)
	var range_m := float(w["range_m"])
	var pellets := maxi(int(w["pellets"]), 1)

	var first_impact := origin + dir * (range_m * 0.5)
	for p in pellets:
		var a := _aim_dir(m, sp, dir, float(w["spread"]))
		var ray_end := origin + a * range_m
		var wall_t := MapData.seg_blocked_t(origin, ray_end)  # -1 none, else 0..1
		var found := false
		var victim := 0
		var best_s := range_m
		var head := false
		var best_q := origin + a * range_m * 0.5
		for v in m.players.values():
			if v == sp or bool(v["dead"]):
				continue
			if int(v["state"]) != MatchSim.State.GROUND:
				continue
			if m.same_team(sp, v):
				continue
			var top_scale := 0.78 if bool(v["crouch"]) else 1.0
			var axis_a := Vector3(v["pos"].x, v["pos"].y + BODY_BOT, v["pos"].z)
			var axis_b := Vector3(v["pos"].x, v["pos"].y + BODY_TOP * top_scale, v["pos"].z)
			var d2 := MapData.dist2_seg_seg(origin, ray_end, axis_a, axis_b)
			if d2 > BODY_R * BODY_R:
				continue
			var axis_mid := (axis_a + axis_b) * 0.5
			var s := clampf((axis_mid - origin).dot(a), 0.0, range_m)
			if wall_t >= 0.0 and s > wall_t * range_m + 0.1:
				continue
			if not found or s < best_s:
				found = true
				victim = int(v["pid"])
				best_s = s
				best_q = origin + a * s
				var qy := best_q.y
				var hs_min := float(v["pos"].y) + HEAD_MIN * (0.75 if bool(v["crouch"]) else 1.0)
				var hs_max := float(v["pos"].y) + HEAD_MAX
				head = qy >= hs_min and qy <= hs_max
		if found:
			if p == 0:
				first_impact = best_q
			m.register_hit(sp, victim, wid, w, best_s, head)
		elif p == 0:
			if wall_t >= 0.0 and wall_t <= 1.0:
				first_impact = origin + a * (wall_t * range_m)
			else:
				first_impact = ray_end

	var muzzle := origin + dir * MUZZLE_FWD
	m.push_event({
		"t": MatchEvents.SHOT,
		"pid": int(sp["pid"]),
		"muzzle": muzzle,
		"impact": first_impact,
		"weapon": wid,
	})


static func _aim_dir(m: MatchSim, sp: Dictionary, base: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.0:
		return base
	var eff := spread_deg
	if bool(sp["abil_active"]) and sp["abil_kind"] == "steadfast":
		eff *= float(sp["abil_power"])  # <1.0 -> tighter cone
	var ang := m.rng.randf_range(0.0, TAU)
	var mag := sqrt(m.rng.randf()) * deg_to_rad(eff)
	var right := base.cross(Vector3.UP)
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT
	var upn := right.cross(base).normalized()
	return (base + right * (cos(ang) * tan(mag)) + upn * (sin(ang) * tan(mag))).normalized()


static func _melee_hit(m: MatchSim, sp: Dictionary, wid: String, w: Dictionary, dir_in: Vector3) -> void:
	var dir := Vector2(dir_in.x, dir_in.z).normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2(0, -1)
	var range_m := float(w["range_m"])
	var found := false
	var victim := 0
	var best_d := range_m * range_m
	for v in m.players.values():
		if v == sp or bool(v["dead"]) or int(v["state"]) != MatchSim.State.GROUND:
			continue
		if m.same_team(sp, v):
			continue
		var off: Vector3 = v["pos"] - sp["pos"]
		var d2 := off.x * off.x + off.z * off.z
		if d2 > best_d:
			continue
		var nd := Vector2(off.x, off.z).normalized()
		if nd.dot(dir) < 0.4:
			continue
		best_d = d2
		found = true
		victim = int(v["pid"])
	var hit_point := Vector3(sp["pos"].x, sp["pos"].y + 1.2, sp["pos"].z)
	if found:
		m.register_hit(sp, victim, wid, w, sqrt(best_d), false)
		var vsp: Dictionary = m.get_sp(victim)
		hit_point = Vector3(vsp["pos"].x, vsp["pos"].y + 1.2, vsp["pos"].z)
	m.push_event({
		"t": MatchEvents.SHOT,
		"pid": int(sp["pid"]),
		"muzzle": Vector3(sp["pos"].x, sp["pos"].y + 1.3, sp["pos"].z),
		"impact": hit_point,
		"weapon": wid,
	})


# ------------------------------------------------------------------ reload

static func try_reload(m: MatchSim, sp: Dictionary) -> void:
	if bool(sp["dead"]):
		return
	if float(sp["reload_until"]) >= 0.0 and m.t < float(sp["reload_until"]):
		return
	var inv: Dictionary = sp["inv"]
	var wid := Inventory.active_weapon(inv)
	var w := WeaponsDB.get_weapon(wid)
	if w.is_empty() or int(w["cat"]) == WeaponsDB.Cat.MELEE:
		return
	var cap := int(w["mag"])
	var mags: Dictionary = sp["mags"]
	if int(mags.get(wid, 0)) >= cap:
		return
	if int(inv["ammo"].get(WeaponsDB.ammo_type(wid), 0)) <= 0:
		m.send_msg_event(int(sp["pid"]), "No ammo for %s." % str(w["name"]))
		return
	var dur := float(w["reload_s"])
	if bool(sp["abil_active"]) and sp["abil_kind"] == "gutshot":
		dur *= float(sp["abil_power"])
	sp["reload_until"] = m.t + dur
	sp["reload_wid"] = wid


static func finish_reload(sp: Dictionary) -> void:
	var inv: Dictionary = sp["inv"]
	var wid := str(sp["reload_wid"])
	sp["reload_until"] = -1.0
	sp["reload_wid"] = ""
	if wid == "":
		return
	var w := WeaponsDB.get_weapon(wid)
	if w.is_empty():
		return
	var cap := int(w["mag"])
	var mags: Dictionary = sp["mags"]
	var cur := int(mags.get(wid, 0))
	var need := cap - cur
	var code := WeaponsDB.ammo_type(wid)
	var pool_obj: Dictionary = inv["ammo"]
	var pool := int(pool_obj.get(code, 0))
	var take := mini(need, pool)
	pool_obj[code] = pool - take
	mags[wid] = cur + take
