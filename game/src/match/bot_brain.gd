# bot_brain.gd — server-side AI for practice/testing matches. Bots produce the
# same command dicts as network clients, so everything a bot does goes through
# the identical server validation path (movement clamps, fire-rate gates,
# inventory rules). Bots are clearly marked as bots everywhere in the UI.
class_name BotBrain
extends RefCounted


const PICK_R := 2.0
const LOOT_SEEK_R := 90.0
const ENGAGE_R := 70.0


var sp: Dictionary            # live reference into MatchSim.players
var rng: RandomNumberGenerator
var drop_t := 0.3
var poi := Vector3.ZERO
var loot_lid := 0
var enemy_pid := 0
var next_scan := 0.0
var yaw := 0.0
var seq := 0
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var wander_ang := 0.0


func _init(rec: Dictionary, rng_in: RandomNumberGenerator) -> void:
	sp = rec
	rng = rng_in
	drop_t = rng.randf_range(0.2, 0.65)
	_pick_poi()
	last_pos = sp["pos"]


func _pick_poi() -> void:
	var s: Dictionary = MapData.SITES[rng.randi() % MapData.SITES.size()]
	poi = Vector3(s["cx"] + rng.randf_range(-18.0, 18.0), 0.0, s["cz"] + rng.randf_range(-18.0, 18.0))


func think(m: MatchSim, dt: float) -> Array:
	var cmds := []
	if m.ended or bool(sp["dead"]):
		return cmds
	match int(sp["state"]):
		MatchSim.State.PLANE:
			if m.plane_t >= drop_t:
				cmds.append(_input_cmd(Vector2.ZERO, 0.0, false, false, false, true))
		MatchSim.State.CHUTE:
			drop_t = 1.0
			cmds.append(_move_toward(poi))
		MatchSim.State.GROUND:
			cmds.append_array(_ground_think(m, dt))
	return cmds


func _ground_think(m: MatchSim, dt: float) -> Array:
	var cmds := []
	var posv: Vector3 = sp["pos"]
	var moved := (posv - last_pos).length()
	last_pos = posv
	if moved < 0.05:
		stuck_t += dt
	else:
		stuck_t = 0.0

	if m.t >= next_scan:
		next_scan = m.t + 0.4
		enemy_pid = _scan_enemy(m, ENGAGE_R)

	var inv: Dictionary = sp["inv"]
	var wid := Inventory.active_weapon(inv)
	var w := WeaponsDB.get_weapon(wid)

	var out_zone := Vector2(posv.x - m.zone.cur_center.x, posv.z - m.zone.cur_center.z).length() > m.zone.cur_radius * 0.85
	var zone_center := Vector3(m.zone.cur_center.x, 0.0, m.zone.cur_center.z)

	# 1) combat behavior
	if enemy_pid != 0:
		var foe: Dictionary = m.get_sp(enemy_pid)
		if foe.is_empty() or bool(foe["dead"]) or int(foe["state"]) != MatchSim.State.GROUND:
			enemy_pid = 0
		else:
			var foe_pos: Vector3 = foe["pos"]
			var dist := (foe_pos - posv).length()
			var have_gun := w.size() > 0 and int(w["cat"]) not in [WeaponsDB.Cat.MELEE, WeaponsDB.Cat.GRENADE]
			if not have_gun and dist > 2.0:
				# unarmed: sprint toward nearest lootable item instead of the enemy
				var nl := _find_loot_worldpos(m)
				if nl != Vector3.ZERO:
					cmds.append(_move_toward(nl))
				else:
					cmds.append(_input_cmd(Vector2.ZERO, yaw, false, false, false, false))
				return cmds
			var want_close := have_gun and (dist > float(w.get("range_m", 40.0)) * 0.7)
			var too_close := dist < 5.0 and have_gun
			var move := Vector2.ZERO
			if not have_gun or want_close:
				if not too_close:
					var d := Vector2(foe_pos.x - posv.x, foe_pos.z - posv.z)
					move = d.normalized() * 0.8
			elif too_close:
				move = Vector2(posv.x - foe_pos.x, posv.z - foe_pos.z).normalized() * 0.7
			yaw = atan2(foe_pos.x - posv.x, foe_pos.z - posv.z)
			cmds.append(_input_cmd(move, yaw, true, false, false, false))
			if m.t >= float(sp["next_fire"]):
				var cat := int(w.get("cat", 6))
				if cat == WeaponsDB.Cat.MELEE and dist < 2.2:
					cmds.append(_fire_cmd(_dir_to(foe_pos, 1.1)))
				elif cat != WeaponsDB.Cat.MELEE and int(sp["mags"].get(wid, 0)) > 0:
					cmds.append(_fire_cmd(_dir_with_error(foe_pos, 4.0 + dist * 0.12)))
				elif cat != WeaponsDB.Cat.MELEE:
					cmds.append({"op": Protocol.Op.RELOAD})
			if out_zone:
				cmds.clear()
				cmds.append(_input_cmd(move, yaw, true, false, false, false))
			return cmds

	# 2) outside zone? rotate toward center
	if out_zone:
		cmds.append(_move_toward(zone_center))
		return cmds

	# 3) loot seek if close loot exists, else wander
	var loot_pos := _find_loot_worldpos(m)
	if loot_pos != Vector3.ZERO:
		if (loot_pos - posv).length() < PICK_R:
			cmds.append(_input_cmd(Vector2.ZERO, yaw, false, false, false, false))
			cmds.append({"op": Protocol.Op.PICKUP})
		else:
			cmds.append(_move_toward(loot_pos))
		return cmds

	if stuck_t > 1.2:
		wander_ang = rng.randf_range(0.0, TAU)
		stuck_t = 0.0
	wander_ang += rng.randf_range(-0.4, 0.4)
	var wander := Vector2(cos(wander_ang), sin(wander_ang))
	yaw = atan2(wander.x, wander.y)
	cmds.append(_input_cmd(wander, yaw, false, false, false, false))
	return cmds


func _find_loot_worldpos(m: MatchSim) -> Vector3:
	var lid := m.claimable_near(sp, LOOT_SEEK_R)
	if lid == 0:
		return Vector3.ZERO
	for item in m.loot.items:
		if int(item["id"]) == lid and int(item["claimed_by"]) == 0:
			return item["pos"]
	return Vector3.ZERO


func _scan_enemy(m: MatchSim, max_d: float) -> int:
	var best := 0
	var best_d := max_d
	var my_pos: Vector3 = sp["pos"]
	for p in m.players.values():
		if int(p["pid"]) == int(sp["pid"]) or bool(p["dead"]):
			continue
		if int(p["team"]) == int(sp["team"]):
			continue
		if int(p["state"]) != MatchSim.State.GROUND:
			continue
		var pv: Vector3 = p["pos"]
		var d := (pv - my_pos).length()
		if d < best_d and m.enemy_visible(my_pos, 1.5, p):
			best_d = d
			best = int(p["pid"])
	return best


# -------------------------------------------------------------- command makers

func _input_cmd(move: Vector2, yawv: float, sprint: bool, crouch: bool, jump: bool, deploy: bool) -> Dictionary:
	seq += 1
	return {
		"op": Protocol.Op.INPUT,
		"seq": seq,
		"pos": sp["pos"],
		"yaw": yawv,
		"move": move,
		"sprint": sprint,
		"crouch": crouch,
		"jump": jump,
		"deploy": deploy,
		"ability": false,
	}


func _move_toward(target: Vector3) -> Dictionary:
	var my_pos: Vector3 = sp["pos"]
	var dx := target.x - my_pos.x
	var dz := target.z - my_pos.z
	var move := Vector2(dx, dz).limit_length(1.0)
	yaw = atan2(dx, dz)
	return _input_cmd(move, yaw, true, false, false, false)


func _fire_cmd(dir: Vector3) -> Dictionary:
	return {"op": Protocol.Op.FIRE, "yaw": yaw, "dir": dir}


func _dir_to(target: Vector3, eye_off: float) -> Vector3:
	var my_pos: Vector3 = sp["pos"]
	var to := Vector3(
		target.x - my_pos.x,
		(target.y + eye_off) - (my_pos.y + 1.55),
		target.z - my_pos.z
	)
	return to.normalized() if to.length_squared() > 0.001 else Vector3.FORWARD


func _dir_with_error(target: Vector3, err_deg: float) -> Vector3:
	var base := _dir_to(target, 1.25)
	var ang := rng.randf_range(-1.0, 1.0) * deg_to_rad(err_deg)
	var right := Vector3.UP.cross(base)
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT
	var upn := right.cross(base).normalized()
	return (base + right * sin(ang) + upn * (cos(ang) * 0.3)).normalized()
