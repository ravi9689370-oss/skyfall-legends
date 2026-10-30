# inventory.gd — shared inventory model. Mutations only through these static
# functions so the authoritative server and the tests enforce identical rules.
# Shape (plain Dictionary, wire-friendly):
#   {
#     "slots": [wid_or_null, wid_or_null],      # 2 weapon slots
#     "slot": current active slot (0..2; 2 = melee),
#     "mags": {wid: int},                        # rounds loaded per weapon id instance? see sim
#     "ammo": {"LIGHT": int, "HEAVY": int, "SHELL": int},
#     "heals": {"medkit": n, "bandage": n},
#     "nades": n,
#   }
class_name Inventory
extends RefCounted


const MELEE_ID := "melee_tanto"
const SLOT_PRIMARY := 0
const SLOT_SECONDARY := 1
const SLOT_MELEE := 2


static func new_inventory() -> Dictionary:
	return {
		"slots": [null, null],
		"slot": SLOT_MELEE,
		"ammo": {ItemsDB.AMMO_LIGHT: 0, ItemsDB.AMMO_HEAVY: 0, ItemsDB.AMMO_SHELL: 0},
		"heals": {ItemsDB.KIND_MEDKIT: 0, ItemsDB.KIND_BANDAGE: 0},
		"nades": 0,
	}


static func weapon_in(inv: Dictionary, slot: int) -> String:
	if slot < 0 or slot > 1:
		return MELEE_ID
	return str(inv["slots"][slot]) if inv["slots"][slot] != null else MELEE_ID


static func active_weapon(inv: Dictionary) -> String:
	var slot := int(inv["slot"])
	if slot == 3:
		return "grenade_skyring"
	if slot <= 1:
		return weapon_in(inv, slot)
	return MELEE_ID


static func has_free_weapon_slot(inv: Dictionary) -> int:
	for i in 2:
		if inv["slots"][i] == null:
			return i
	return -1


# Returns {ok, reason} — never mutates unless ok.
static func add_pickup(inv: Dictionary, kind: String, wid: String = "") -> Dictionary:
	# wid is a weapon id when kind is a weapon drop, else "".
	if wid != "":
		return _add_weapon(inv, wid)
	match kind:
		ItemsDB.KIND_MEDKIT, ItemsDB.KIND_BANDAGE:
			var cap: int = ItemsDB.HEAL_CAPS[kind]
			var have := int(inv["heals"].get(kind, 0))
			if have >= cap:
				return {"ok": false, "reason": "full"}
			inv["heals"][kind] = have + 1
			return {"ok": true, "reason": ""}
		ItemsDB.KIND_GRENADE:
			if int(inv["nades"]) >= ItemsDB.NADE_CAP:
				return {"ok": false, "reason": "full"}
			inv["nades"] = int(inv["nades"]) + 1
			return {"ok": true, "reason": ""}
		ItemsDB.KIND_AMMO_LIGHT, ItemsDB.KIND_AMMO_HEAVY, ItemsDB.KIND_AMMO_SHELL:
			var code := ItemsDB.ammo_code_for_kind(kind)
			var box: Dictionary = ItemsDB.get_item(kind)
			var n := int(box.get("n", 30))
			var cap: int = ItemsDB.AMMO_CAP[code]
			var have := int(inv["ammo"].get(code, 0))
			if have >= cap:
				return {"ok": false, "reason": "full"}
			inv["ammo"][code] = minf(cap, have + n)
			return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "unknown_kind"}


static func _add_weapon(inv: Dictionary, wid: String) -> Dictionary:
	if WeaponsDB.get_weapon(wid).is_empty() or WeaponsDB.cat(wid) >= WeaponsDB.Cat.MELEE:
		return {"ok": false, "reason": "not_a_weapon"}
	var free := has_free_weapon_slot(inv)
	if free < 0:
		return {"ok": false, "reason": "slots_full"}
	inv["slots"][free] = wid
	if int(inv["slot"]) == SLOT_MELEE and free == SLOT_PRIMARY:
		inv["slot"] = SLOT_PRIMARY
	return {"ok": true, "reason": ""}


static func set_slot(inv: Dictionary, slot: int) -> void:
	inv["slot"] = clampi(slot, 0, SLOT_MELEE)


static func consume_ammo(inv: Dictionary, code: String, n: int) -> bool:
	if n <= 0:
		return true
	if int(inv["ammo"].get(code, 0)) < n:
		return false
	inv["ammo"][code] = int(inv["ammo"][code]) - n
	return true


static func consume_heal(inv: Dictionary, kind: String) -> bool:
	if not inv["heals"].has(kind) or int(inv["heals"][kind]) <= 0:
		return false
	inv["heals"][kind] = int(inv["heals"][kind]) - 1
	return true


static func consume_grenade(inv: Dictionary) -> bool:
	if int(inv["nades"]) <= 0:
		return false
	inv["nades"] = int(inv["nades"]) - 1
	return true


# Invariants for tests.
static func is_valid(inv: Dictionary) -> Dictionary:
	if inv["slots"].size() != 2:
		return {"ok": false, "reason": "slots_len"}
	var total := 0
	for code in ItemsDB.AMMO_CAP:
		var amt := int(inv["ammo"].get(code, 0))
		if amt < 0 or amt > int(ItemsDB.AMMO_CAP[code]):
			return {"ok": false, "reason": "ammo_cap:%s" % code}
		total += amt
	for kind in ItemsDB.HEAL_CAPS:
		var amt := int(inv["heals"].get(kind, 0))
		if amt < 0 or amt > int(ItemsDB.HEAL_CAPS[kind]):
			return {"ok": false, "reason": "heal_cap:%s" % kind}
	if int(inv["nades"]) < 0 or int(inv["nades"]) > ItemsDB.NADE_CAP:
		return {"ok": false, "reason": "nade_cap"}
	if int(inv["slot"]) < 0 or int(inv["slot"]) > SLOT_MELEE:
		return {"ok": false, "reason": "slot_range"}
	for s in inv["slots"]:
		if s != null and WeaponsDB.get_weapon(str(s)).is_empty():
			return {"ok": false, "reason": "unknown_weapon"}
	return {"ok": true, "reason": ""}
