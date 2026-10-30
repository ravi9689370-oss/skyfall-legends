# loot_field.gd — server-authoritative loot instances for one match.
# Every spawned item has a unique id. Claiming is double-submission-proof:
# a claim records the pid atomically; second claims of the same id fail.
class_name LootField
extends RefCounted


var items: Array = []           # {id, item, wid, pos, claimed_by}
var next_id := 1
var _rng: RandomNumberGenerator


func _init(rng_in: RandomNumberGenerator) -> void:
	_rng = rng_in


# Weighted random pick of the loot table at a point of a given tier.
func roll_for_point(tier: int) -> Dictionary:
	var t_mult := 1.0 + 0.6 * (clampi(tier, 1, 3) - 1)
	var w := [
		{"k": "weapon", "w": 40.0 * t_mult},
		{"k": ItemsDB.KIND_BANDAGE, "w": 22.0},
		{"k": ItemsDB.KIND_MEDKIT, "w": 8.0 * t_mult},
		{"k": ItemsDB.KIND_PLATE, "w": 9.0 * t_mult},
		{"k": ItemsDB.KIND_AMMO_LIGHT, "w": 10.0},
		{"k": ItemsDB.KIND_AMMO_HEAVY, "w": 8.0},
		{"k": ItemsDB.KIND_AMMO_SHELL, "w": 6.0},
		{"k": ItemsDB.KIND_GRENADE, "w": 9.0},
	]
	var total := 0.0
	for e in w:
		total += e["w"]
	var r := _rng.randf_range(0.0, total)
	for e in w:
		r -= e["w"]
		if r <= 0.0:
			if e["k"] == "weapon":
				return {"item": "", "wid": _roll_weapon(tier)}
			return {"item": str(e["k"]), "wid": ""}
	return {"item": "", "wid": _roll_weapon(tier)}


func _roll_weapon(tier: int) -> String:
	var pool: Array = []
	for wid in WeaponsDB.all_ids():
		var cat := WeaponsDB.cat(wid)
		if cat == WeaponsDB.Cat.MELEE:
			continue
		var t := int(WeaponsDB.get_weapon(wid)["tier"])
		var weight := 3 - absi(t - clampi(tier, 1, 3))
		for i in weight:
			pool.append(wid)
	return pool[_rng.randi() % pool.size()]


func spawn_map_loot() -> void:
	for p in MapData.LOOT_POINTS:
		var pos_xz := Vector2(p[0], p[1])
		var tier := int(p[2])
		var roll := roll_for_point(tier)
		add_item(roll["item"], roll["wid"],
			Vector3(pos_xz.x, MapData.height(pos_xz.x, pos_xz.y), pos_xz.y))


func add_item(item: String, wid: String, pos: Vector3) -> int:
	var rec := {
		"id": next_id,
		"item": item,
		"wid": wid,
		"pos": pos,
		"claimed_by": 0,
	}
	next_id += 1
	items.append(rec)
	return rec["id"]


# Drop a player's carried items at their death position.
func drops_from_inventory(inv: Dictionary, pos: Vector3) -> void:
	for wid in inv["slots"]:
		if wid != null:
			add_item("", str(wid), pos)
	for kind in inv["heals"]:
		for i in int(inv["heals"][kind]):
			add_item(str(kind), "", pos)
	for i in int(inv["nades"]):
		add_item(ItemsDB.KIND_GRENADE, "", pos)


func claimable_id_near(xz: Vector2, radius: float) -> int:
	var best_id := 0
	var best_d := radius * radius
	for i in items.size():
		var rec: Dictionary = items[i]
		if rec["claimed_by"] != 0:
			continue
		var d := Vector2(rec["pos"].x, rec["pos"].z).distance_squared_to(xz)
		if d < best_d:
			best_d = d
			best_id = rec["id"]
	return best_id


# Atomic claim. Returns {} when already taken / unknown.
func claim(lid: int, pid: int) -> Dictionary:
	for rec in items:
		if rec["id"] == lid:
			if rec["claimed_by"] != 0:
				return {}
			rec["claimed_by"] = pid
			return {"id": rec["id"], "item": rec["item"], "wid": rec["wid"], "pos": rec["pos"]}
	return {}


func unclaimed_wire() -> Array:
	var out := []
	for rec in items:
		if rec["claimed_by"] == 0:
			out.append({"id": rec["id"], "item": rec["item"], "wid": rec["wid"], "pos": rec["pos"]})
	return out
