# map_data.gd — "Kestrel Atoll": the original match island. Pure math shared by
# the dedicated server (headless) and the client renderer so both derive the
# exact same terrain, structures, loot points and cover from the same constants.
#
# The terrain is analytic (no external assets): a radial island mask over
# deterministic trig-noise ridges, terraced around six settlements. All names
# and layouts are original to this project.
class_name MapData
extends RefCounted


const ISLAND_R := 470.0
const HARD_R := 520.0          # hard movement clamp radius
const WATER_Y := 0.0
const TERRAIN_AMP := 9.0

const SITES := [
	{"name": "Cormorant Docks", "cx": -185.0, "cz": 205.0, "h": 3.0, "r": 46.0},
	{"name": "Tin Gull Cannery", "cx": 165.0, "cz": 240.0, "h": 4.0, "r": 42.0},
	{"name": "Twin Hill Homestead", "cx": -45.0, "cz": -165.0, "h": 8.0, "r": 40.0},
	{"name": "Lookout Ridge Camp", "cx": 225.0, "cz": -150.0, "h": 12.0, "r": 38.0},
	{"name": "Marshline Outpost", "cx": -275.0, "cz": -70.0, "h": 2.0, "r": 34.0},
	{"name": "Ferryman's Court", "cx": 55.0, "cz": 25.0, "h": 5.0, "r": 40.0},
]

# Buildings: [x, z, size_x, size_z, wall_h, roof_h]. Axis-aligned boxes.
const BUILDINGS := [
	[-206.0, 185.0, 9.0, 12.0, 4.2, 1.2],
	[-190.0, 212.0, 12.0, 9.0, 5.0, 1.0],
	[-166.0, 196.0, 9.0, 9.0, 3.8, 1.0],
	[-172.0, 224.0, 10.0, 7.0, 4.4, 1.0],
	[150.0, 228.0, 18.0, 11.0, 6.4, 1.4],
	[174.0, 218.0, 8.0, 8.0, 4.0, 1.0],
	[170.0, 248.0, 9.0, 7.0, 4.2, 1.0],
	[-66.0, -146.0, 9.0, 8.0, 4.6, 1.2],
	[-40.0, -186.0, 10.0, 9.0, 4.6, 1.2],
	[-16.0, -152.0, 8.0, 7.0, 4.2, 1.0],
	[-70.0, -178.0, 8.0, 7.0, 4.0, 1.0],
	[-20.0, -182.0, 7.0, 7.0, 4.0, 1.0],
	[210.0, -132.0, 9.0, 8.0, 4.4, 1.2],
	[232.0, -158.0, 8.0, 7.0, 4.0, 1.0],
	[246.0, -130.0, 8.0, 8.0, 4.2, 1.0],
	[222.0, -166.0, 5.0, 5.0, 13.0, 2.0],
	[-288.0, -56.0, 10.0, 8.0, 4.0, 1.0],
	[-266.0, -84.0, 9.0, 9.0, 4.4, 1.0],
	[-252.0, -56.0, 8.0, 7.0, 3.8, 1.0],
	[38.0, 10.0, 11.0, 9.0, 4.8, 1.2],
	[62.0, 14.0, 9.0, 8.0, 4.4, 1.0],
	[52.0, 42.0, 12.0, 8.0, 4.6, 1.2],
	[-120.0, 60.0, 8.0, 7.0, 4.0, 1.0],
	[120.0, -40.0, 8.0, 7.0, 4.0, 1.0],
	[-30.0, 140.0, 9.0, 8.0, 4.2, 1.0],
	[300.0, 60.0, 8.0, 7.0, 4.0, 1.0],
]

# Loot points: [x, z, tier] — 1 common .. 3 scarce.
const LOOT_POINTS := [
	[-202.0, 178.0, 1], [-186.0, 222.0, 2], [-162.0, 204.0, 1],
	[-144.0, 236.0, 1], [-230.0, 240.0, 1],

	[146.0, 216.0, 2], [160.0, 240.0, 3], [178.0, 230.0, 1],
	[196.0, 258.0, 1], [186.0, 200.0, 2],

	[-70.0, -152.0, 2], [-46.0, -190.0, 1], [-12.0, -158.0, 1],
	[-44.0, -164.0, 3], [-84.0, -170.0, 1],

	[206.0, -126.0, 1], [238.0, -148.0, 2], [250.0, -122.0, 1],
	[236.0, -180.0, 2], [228.0, -150.0, 3],

	[-290.0, -50.0, 1], [-262.0, -92.0, 1], [-248.0, -50.0, 2],
	[-314.0, -78.0, 1],

	[34.0, 16.0, 2], [68.0, 20.0, 1], [46.0, 48.0, 1],
	[52.0, -6.0, 2], [78.0, 34.0, 1],

	[-124.0, 56.0, 1], [126.0, -44.0, 1], [-34.0, 148.0, 2],
	[306.0, 64.0, 1], [0.0, 320.0, 1], [-330.0, 30.0, 1],
]

# Roads (visual + navigation hint): [x1,z1, x2,z2]
const ROADS := [
	[-185.0, 205.0, 55.0, 25.0],
	[55.0, 25.0, 165.0, 240.0],
	[55.0, 25.0, -45.0, -165.0],
	[-45.0, -165.0, 225.0, -150.0],
	[-45.0, -165.0, -275.0, -70.0],
	[-185.0, 205.0, -275.0, -70.0],
]


static func height(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	if r > ISLAND_R * 1.06:
		return WATER_Y - 6.0
	var t := clampf(r / ISLAND_R, 0.0, 1.0)
	var shore := 1.0 - smoothstep(0.88, 1.0, t)
	var base := 2.2 + shore * (2.2 + TERRAIN_AMP * (0.55 + 0.45 * _ridge(x, z)))
	base = maxf(base, WATER_Y + 0.15)
	for s in SITES:
		var scx: float = s.cx
		var scz: float = s.cz
		var sr: float = s.r
		var sh: float = s.h
		var dsq: float = (x - scx) * (x - scx) + (z - scz) * (z - scz)
		var dr: float = sqrt(dsq)
		if dr < sr * 1.35:
			var k := 1.0 - smoothstep(sr * 0.92, sr * 1.35, dr)
			base = lerpf(base, sh, clampf(k, 0.0, 1.0))
	return base


static func ground_from_xz(x: float, z: float) -> float:
	return height(x, z)


static func _ridge(x: float, z: float) -> float:
	return (
		sin(x * 0.012 + 1.7) * cos(z * 0.010 - 0.4)
		+ sin(x * 0.027 - 0.6) * cos(z * 0.023 + 2.1) * 0.55
		+ sin(x * 0.051 + 3.2) * cos(z * 0.047 + 1.1) * 0.22
	)


# AABB list for structures (server math + client blocks).
static func building_boxes() -> Array:
	var out := []
	for b in BUILDINGS:
		var y0 := height(b[0], b[1])
		var min_v := Vector3(b[0] - b[2] * 0.5, y0 - 2.0, b[1] - b[3] * 0.5)
		var max_v := Vector3(b[0] + b[2] * 0.5, y0 + b[4] + b[5], b[1] + b[3] * 0.5)
		out.append({"min": min_v, "max": max_v})
	return out


# --------------------------------------------------------------- ray cover

# Segment vs AABB (slab method). Returns entry t in (0..1], or -1.0 if none.
static func seg_aabb_t(a: Vector3, b: Vector3, vmin: Vector3, vmax: Vector3) -> float:
	var d := b - a
	var mn := 0.0
	var mx := 1.0
	for i in 3:
		var o: float = a[i]
		var dir: float = d[i]
		var lo: float = vmin[i]
		var hi: float = vmax[i]
		if absf(dir) < 0.0001:
			if o < lo or o > hi:
				return -1.0
		else:
			var t1 := (lo - o) / dir
			var t2 := (hi - o) / dir
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			mn = maxf(mn, t1)
			mx = minf(mx, t2)
			if mn > mx:
				return -1.0
	if mn <= 0.0 and mx >= 0.0:
		return -1.0
	return mn


# Nearest structure blocking the segment. Returns t or -1.0.
static func seg_blocked_t(a: Vector3, b: Vector3) -> float:
	var best := 9999.0
	for box in building_boxes():
		var t := seg_aabb_t(a, b, box["min"], box["max"])
		if t >= 0.0 and t < best:
			best = t
	return best if best <= 1.0 else -1.0


# ---------------------------------------------- movement vs structures (XZ)

# Push a circle (player) out of structure boxes. Returns corrected x,z.
static func resolve_circle_xz(x: float, z: float, r: float, y: float) -> Vector3:
	for box in building_boxes():
		var bmin: Vector3 = box["min"]
		var bmax: Vector3 = box["max"]
		var ymin: float = bmin.y
		var ymax: float = bmax.y
		if y < ymin - 1.2 or y > ymax + 0.4:
			continue
		var cx: float = clampf(x, bmin.x, bmax.x)
		var cz: float = clampf(z, bmin.z, bmax.z)
		var dx: float = x - cx
		var dz: float = z - cz
		var dsq: float = dx * dx + dz * dz
		if dsq > r * r:
			continue
		if dsq > 0.000001:
			var d: float = sqrt(dsq)
			var push := r - d
			x += dx / d * push
			z += dz / d * push
		else:
			# inside the box on XZ: eject along smallest penetration axis
			var px1: float = (bmax.x - x) + r
			var px2: float = (x - bmin.x) + r
			var pz1: float = (bmax.z - z) + r
			var pz2: float = (z - bmin.z) + r
			var pm := minf(minf(px1, px2), minf(pz1, pz2))
			if pm == px1:
				x = bmax.x + r
			elif pm == px2:
				x = bmin.x - r
			elif pm == pz1:
				z = bmax.z + r
			else:
				z = bmin.z - r
	return Vector3(x, y, z)


# -------------------------------------------------------------- geometry aid

# Squared distance from point P to segment AB (a: Vector3 from, b: Vector3 to).
static func dist2_point_seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var ap := p - a
	var t := clampf(ap.dot(ab) / maxf(ab.dot(ab), 0.0001), 0.0, 1.0)
	var q := a + ab * t
	return (p - q).length_squared()


# Squared distance between two segments ab and cd (capsule-approx hit tests).
static func dist2_seg_seg(a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3) -> float:
	# standard clip algorithm
	var d1 := a2 - a1
	var d2 := b2 - b1
	var r := a1 - b1
	var A := d1.dot(d1)
	var E := d2.dot(d2)
	var F := d2.dot(r)
	if A <= 0.0001 or E <= 0.0001:
		if A <= 0.0001:
			if E <= 0.0001:
				return r.length_squared()
			var ttt := clampf(-F / E, 0.0, 1.0)
			return (b1 + d2 * ttt - a1).length_squared()
		var ttt2 := clampf(r.dot(d1) / A, 0.0, 1.0)
		return (a1 + d1 * ttt2 - b1).length_squared()
	var C := d1.dot(r)
	var B := d1.dot(d2)
	var denom := A * E - B * B
	var s := 0.0
	if denom > 0.0001:
		s = clampf((B * F - C * E) / denom, 0.0, 1.0)
	var t := 0.0
	if absf(B) > 0.0001:
		t = 0.0 if (B * s + F) <= 0.0 else clampf((B * s + F) / E, 0.0, 1.0)
		if absf(1.0 - t) < 0.0001:
			# edge t=0 rejected; use s
			s = clampf((B - C) / A, 0.0, 1.0)
	var c1 := a1 + d1 * s
	var c2 := b1 + d2 * t
	return (c1 - c2).length_squared()


# ----------------------------------------------------------------- helpers

static func flight_points(rng: RandomNumberGenerator) -> Dictionary:
	var ang := rng.randf_range(0.0, TAU)
	var dir := Vector2(cos(ang), sin(ang))
	var from := dir * (ISLAND_R + 260.0)
	var to := -dir * (ISLAND_R + 260.0)
	return {"from": Vector3(from.x, MatchRules.PLANE_ALT, from.y), "to": Vector3(to.x, MatchRules.PLANE_ALT, to.y)}


static func clamped_to_bounds(x: float, z: float) -> Vector2:
	var l := Vector2(x, z).length()
	if l > HARD_R:
		return Vector2(x, z) * (HARD_R / l)
	return Vector2(x, z)
