# zone.gd — server-authoritative safe-zone state machine for a match.
class_name Zone
extends RefCounted


enum ZS { WAIT = 0, SHRINKING = 1, ENDED = 2 }


var phase_idx := 0
var state: int = ZS.WAIT
var cur_radius := 480.0
var cur_center := Vector3.ZERO
var from_radius := 480.0
var from_center := Vector3.ZERO
var next_radius := 298.0
var next_center := Vector3.ZERO
var timer := 0.0
var dps := 0.0
var shrink_t := 0.0
var phases: Array = MatchRules.ZONE_PHASES.duplicate(true)
var _rng: RandomNumberGenerator


func _init(start_radius: float, rng_in: RandomNumberGenerator, phases_override: Array = []) -> void:
	_rng = rng_in
	if phases_override.size() > 0:
		phases = phases_override.duplicate(true)
	cur_radius = start_radius
	from_radius = start_radius
	next_radius = start_radius
	_dps_reload()
	_pick_next()


static func start_radius_default() -> float:
	return 476.0


func _dps_reload() -> void:
	var ph: Dictionary = phases[clampi(phase_idx, 0, phases.size() - 1)]
	dps = float(ph["dps"])


func _pick_next() -> void:
	var ph: Dictionary = phases[clampi(phase_idx, 0, phases.size() - 1)]
	next_radius = maxf(cur_radius * float(ph["r_mult"]), 9.0)
	var drift := maxf(cur_radius - next_radius, 0.0) * 0.6
	var ang := _rng.randf_range(0.0, TAU)
	var offs := Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(0.0, drift)
	var c := cur_center + offs
	# keep the next circle inside the island bounds next to its parent center
	var xz := Vector2(c.x, c.z).limit_length(MapData.HARD_R * 0.8)
	next_center = Vector3(xz.x, 0.0, xz.y)
	timer = float(ph["wait_s"])


func step(dt: float) -> bool:  # returns true if a zone event should raise
	var fired := false
	match state:
		ZS.WAIT:
			timer -= dt
			if timer <= 0.0:
				state = ZS.SHRINKING
				shrink_t = float(phases[clampi(phase_idx, 0, phases.size() - 1)]["shrink_s"])
				timer = shrink_t
				from_radius = cur_radius
				from_center = cur_center
				fired = true  # callers raise ZONE_ANNOUNCE (shrink has begun)
		ZS.SHRINKING:
			timer -= dt
			var k := clampf(1.0 - timer / maxf(shrink_t, 0.0001), 0.0, 1.0)
			cur_radius = lerpf(from_radius, next_radius, k)
			cur_center = from_center.lerp(next_center, k)
			if timer <= 0.0:
				cur_radius = next_radius
				cur_center = next_center
				if phase_idx + 1 >= phases.size():
					state = ZS.ENDED
				else:
					phase_idx += 1
					_dps_reload()
					_pick_next()
					state = ZS.WAIT
	return fired


func state_dict() -> Dictionary:
	return {
		"phase_idx": phase_idx,
		"state": state,
		"cur_radius": cur_radius,
		"cur_center": cur_center,
		"next_radius": next_radius,
		"next_center": next_center,
		"time_left": maxf(timer, 0.0),
		"dps": dps,
	}
