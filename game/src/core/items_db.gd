# items_db.gd — healables / grenades / armor / ammo for the loot economy.
# Loot tables weight these together with weapon ids (see map/loot_field.gd).
class_name ItemsDB
extends RefCounted


# kind strings (wire-safe): "medkit","bandage","grenade","armor_plate",
# "ammo_light","ammo_heavy","ammo_shell"
const KIND_MEDKIT := "medkit"
const KIND_BANDAGE := "bandage"
const KIND_GRENADE := "grenade"
const KIND_PLATE := "plate"
const KIND_AMMO_LIGHT := "ammo_light"
const KIND_AMMO_HEAVY := "ammo_heavy"
const KIND_AMMO_SHELL := "ammo_shell"

const AMMO_LIGHT := "LIGHT"
const AMMO_HEAVY := "HEAVY"
const AMMO_SHELL := "SHELL"

const DB := {
	KIND_MEDKIT: {"name": "Field Medkit", "heal": 75.0, "use_s": 3.5, "tier": 3},
	KIND_BANDAGE: {"name": "Bandage", "heal": 25.0, "use_s": 1.6, "tier": 1},
	KIND_GRENADE: {"name": "Skyring Grenade", "tier": 2},
	KIND_PLATE: {"name": "Armor Plate", "armor": 50.0, "use_s": 2.5, "tier": 2},
	KIND_AMMO_LIGHT: {"name": "Light Ammo Box", "n": 60.0, "tier": 1},
	KIND_AMMO_HEAVY: {"name": "Heavy Ammo Box", "n": 40.0, "tier": 1},
	KIND_AMMO_SHELL: {"name": "Shell Box", "n": 16.0, "tier": 1},
}

# stash capacity rules (server-invalidated).
const HEAL_CAPS := { KIND_MEDKIT: 3, KIND_BANDAGE: 8, KIND_PLATE: 0, KIND_GRENADE: 0 }
const AMMO_CAP := { AMMO_LIGHT: 240, AMMO_HEAVY: 120, AMMO_SHELL: 40 }
const NADE_CAP := 3


static func get_item(kind: String) -> Dictionary:
	return DB.get(kind, {})


static func is_ammo(kind: String) -> bool:
	return kind in [KIND_AMMO_LIGHT, KIND_AMMO_HEAVY, KIND_AMMO_SHELL]


static func is_heal(kind: String) -> bool:
	return kind in [KIND_MEDKIT, KIND_BANDAGE, KIND_PLATE]


static func ammo_code_for_kind(kind: String) -> String:
	match kind:
		KIND_AMMO_LIGHT: return AMMO_LIGHT
		KIND_AMMO_HEAVY: return AMMO_HEAVY
		KIND_AMMO_SHELL: return AMMO_SHELL
	return ""
