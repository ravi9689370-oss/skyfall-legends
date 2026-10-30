# characters_db.gd — original playable roster. Visual identities are color
# palettes + procedurally styled avatars (see client/mannequin.gd). Abilities
# are server-validated utility effects; never raw damage multipliers.
class_name CharactersDB
extends RefCounted


# ability kinds the server understands:
#  "dash"      : short burst of +speed
#  "bulwark"   : temporary +armor pool
#  "steadfast" : temporary spread reduction
#  "gutshot"   : temporary reload speed boost
const DB := {
	"ranger": {
		"id": "ranger", "name": "Ranger Vasco",
		"desc": "Trail aviator. Dashes hard off the line.",
		"ability": "dash", "ability_cd_s": 7.0, "ability_power": 2.2, "ability_for_s": 0.6,
		"palette": {"suit": Color(0.13, 0.42, 0.51), "trim": Color(0.85, 0.72, 0.25), "visor": Color(0.9, 0.95, 1.0)},
		"style": "visor",
	},
	"bulwark": {
		"id": "bulwark", "name": "Brick Marlow",
		"desc": "Docks brawler. Slaps on extra plating mid-fight.",
		"ability": "bulwark", "ability_cd_s": 22.0, "ability_power": 40.0, "ability_for_s": 8.0,
		"palette": {"suit": Color(0.35, 0.27, 0.22), "trim": Color(0.78, 0.38, 0.16), "visor": Color(0.95, 0.85, 0.5)},
		"style": "helm",
	},
	"sharp": {
		"id": "sharp", "name": "Sela Nyx",
		"desc": "Range scout. Steadies aim under fire.",
		"ability": "steadfast", "ability_cd_s": 14.0, "ability_power": 0.5, "ability_for_s": 4.0,
		"palette": {"suit": Color(0.16, 0.2, 0.33), "trim": Color(0.4, 0.68, 0.72), "visor": Color(0.7, 0.85, 0.95)},
		"style": "cap",
	},
	"gust": {
		"id": "gust", "name": "Gust Okafor",
		"desc": "Guncraft mechanic. Reloads like a drill sergeant.",
		"ability": "gutshot", "ability_cd_s": 12.0, "ability_power": 0.55, "ability_for_s": 3.0,
		"palette": {"suit": Color(0.24, 0.3, 0.24), "trim": Color(0.72, 0.78, 0.3), "visor": Color(0.85, 0.9, 0.9)},
		"style": "cap",
	},
}


static func get_character(id: String) -> Dictionary:
	return DB.get(id, {});


static func all_ids() -> Array:
	return DB.keys()


static func default_id() -> String:
	return "ranger"
