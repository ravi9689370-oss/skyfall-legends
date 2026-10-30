# damage.gd — pure server-side damage/armor math. No client may call this.
class_name Damage
extends RefCounted


# Range falloff: full damage to 60% of weapon range, then linear to 55% at max.
static func falloff(weapon: Dictionary, dist: float) -> float:
	var rng := float(weapon.get("range_m", 100.0))
	if dist >= rng:
		return 0.0
	var full := rng * 0.6
	if dist <= full:
		return 1.0
	var t := (dist - full) / maxf(rng - full, 0.001)
	return lerpf(1.0, 0.55, clampf(t, 0.0, 1.0))


# Armor model: plates absorb half of incoming damage until depleted.
static func apply(raw: float, hp: float, armor: float) -> Dictionary:
	var incoming := maxf(raw, 0.0)
	var hp_damage := 0.0
	var soaked := 0.0
	if armor > 0.0 and incoming > 0.0:
		# plates blunt half the hit; hp damage is clamped by remaining plate
		# value, so over-penetrating hits cannot one-shot through full plates.
		hp_damage = minf(incoming * 0.5, armor * 0.5)
		soaked = hp_damage
	else:
		hp_damage = incoming * 0.5
	var new_hp := maxf(hp - hp_damage, 0.0)
	return {
		"raw": raw,
		"soaked": soaked,
		"hp": new_hp,
		"armor": armor - soaked,
		"dealt": raw,
	}
