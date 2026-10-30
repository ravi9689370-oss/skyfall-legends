# weapons_db.gd — data-driven, fully original weapon roster for Skyfall Legends.
# All naming, stats and identities here are original creations of this project.
class_name WeaponsDB
extends RefCounted


enum Cat { AR, SMG, SG, SNIPER, PISTOL, MELEE, GRENADE }

# Numeric sanity ranges used by tests to catch config drift.
const DMG_MIN := 5.0
const DMG_MAX := 120.0
const RPM_MIN := 30.0
const RPM_MAX := 1100.0

const CAT_NAMES := {
	Cat.AR: "Assault Rifle",
	Cat.SMG: "Submachine Gun",
	Cat.SG: "Shotgun",
	Cat.SNIPER: "Sniper Rifle",
	Cat.PISTOL: "Pistol",
	Cat.MELEE: "Melee",
	Cat.GRENADE: "Throwable",
}

const ammo_by_cat := {
	Cat.AR: "LIGHT",
	Cat.SMG: "LIGHT",
	Cat.SG: "SHELL",
	Cat.SNIPER: "HEAVY",
	Cat.PISTOL: "HEAVY",
	Cat.MELEE: "",
	Cat.GRENADE: "",
}

# Fields legend:
#  dmg      : per bullet/pellet body damage before armor
#  rpm      : rounds per minute (fire cadence)
#  mag / reserve : magazine + pickup reserve granted
#  reload_s : reload duration seconds
#  spread   : base cone half-angle in degrees
#  recoil   : 0..1 extra spread growth while buffing hip fire
#  range_m  : max effective hitscan length (server-validated)
#  pellets  : projectiles per trigger pull (shotguns)
#  hs       : headshot multiplier
#  tier     : loot rarity tier (1 common .. 3 scarce)
const DB := {
	"ar_vanguard": {
		"id": "ar_vanguard", "name": "Vanguard-7", "cat": Cat.AR,
		"dmg": 23.0, "rpm": 540.0, "mag": 30, "reserve": 90,
		"reload_s": 2.1, "spread": 2.4, "recoil": 0.55, "range_m": 140.0,
		"pellets": 1, "hs": 1.5, "tier": 2,
	},
	"ar_compass": {
		"id": "ar_compass", "name": "Compass AR-9", "cat": Cat.AR,
		"dmg": 19.0, "rpm": 460.0, "mag": 36, "reserve": 108,
		"reload_s": 1.8, "spread": 2.0, "recoil": 0.42, "range_m": 160.0,
		"pellets": 1, "hs": 1.5, "tier": 2,
	},
	"smg_raptor": {
		"id": "smg_raptor", "name": "Raptor SMG-X", "cat": Cat.SMG,
		"dmg": 15.0, "rpm": 820.0, "mag": 32, "reserve": 128,
		"reload_s": 1.7, "spread": 3.4, "recoil": 0.35, "range_m": 80.0,
		"pellets": 1, "hs": 1.4, "tier": 1,
	},
	"sg_thumper": {
		"id": "sg_thumper", "name": "Thumper SG-12", "cat": Cat.SG,
		"dmg": 9.0, "rpm": 65.0, "mag": 6, "reserve": 18,
		"reload_s": 2.6, "spread": 3.6, "recoil": 0.7, "range_m": 30.0,
		"pellets": 8, "hs": 1.2, "tier": 2,
	},
	"sg_gale": {
		"id": "sg_gale", "name": "Gale Breaker", "cat": Cat.SG,
		"dmg": 7.0, "rpm": 95.0, "mag": 8, "reserve": 24,
		"reload_s": 2.4, "spread": 4.4, "recoil": 0.6, "range_m": 24.0,
		"pellets": 10, "hs": 1.1, "tier": 1,
	},
	"sniper_longshot": {
		"id": "sniper_longshot", "name": "Longshot .408", "cat": Cat.SNIPER,
		"dmg": 92.0, "rpm": 38.0, "mag": 5, "reserve": 15,
		"reload_s": 3.2, "spread": 0.6, "recoil": 0.9, "range_m": 340.0,
		"pellets": 1, "hs": 2.0, "tier": 3,
	},
	"pistol_pocketman": {
		"id": "pistol_pocketman", "name": "Pocketman P45", "cat": Cat.PISTOL,
		"dmg": 18.0, "rpm": 280.0, "mag": 12, "reserve": 36,
		"reload_s": 1.4, "spread": 2.6, "recoil": 0.4, "range_m": 70.0,
		"pellets": 1, "hs": 1.5, "tier": 1,
	},
	"melee_tanto": {
		"id": "melee_tanto", "name": "Tanto Blade", "cat": Cat.MELEE,
		"dmg": 38.0, "rpm": 120.0, "mag": 0, "reserve": 0,
		"reload_s": 0.0, "spread": 0.0, "recoil": 0.0, "range_m": 2.4,
		"pellets": 1, "hs": 1.0, "tier": 1,
	},
	"grenade_skyring": {
		"id": "grenade_skyring", "name": "Skyring Grenade", "cat": Cat.GRENADE,
		"dmg": 95.0, "rpm": 45.0, "mag": 0, "reserve": 0,
		"reload_s": 0.0, "spread": 0.0, "recoil": 0.0, "range_m": 0.0,
		"pellets": 1, "hs": 1.0, "tier": 2,
	},
}


static func get_weapon(id: String) -> Dictionary:
	return DB.get(id, {})


static func cat(id: String) -> int:
	var w: Dictionary = DB.get(id, {})
	return int(w.get("cat", Cat.AR))


static func ammo_type(id: String) -> String:
	return ammo_by_cat[cat(id)]


static func category_fill() -> Dictionary:
	# coverage map used by tests to guarantee all spec-required categories exist.
	var cov := {}
	for k in DB:
		var c: int = int(DB[k].cat)
		cov[c] = cov.get(c, 0) + 1
	return cov


static func all_ids() -> Array:
	return DB.keys()
