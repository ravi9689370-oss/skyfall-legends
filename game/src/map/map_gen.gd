# map_gen.gd — client-only visual builder for Kestrel Atoll. Entirly derived
# from MapData constants: terrain mesh, water, roads, buildings, rocks, trees,
# lighting. No external assets; all textures are flat colors (mobile-friendly).
class_name MapGen
extends RefCounted


const GRID := 128
const EXTENT := MapData.HARD_R * 1.35
const SAND := Color(0.76, 0.68, 0.5)
const GRASS := Color(0.36, 0.53, 0.31)
const GRASS_DARK := Color(0.27, 0.42, 0.26)
const ROAD := Color(0.35, 0.35, 0.37)


static func build(root: Node3D) -> void:
	_terrain(root)
	_water(root)
	_roads(root)
	_structures(root)
	_props(root)
	_environment(root)


static func _terrain(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := GRID
	var step := (EXTENT * 2.0) / float(n)
	var shades := {}
	for i in range(n + 1):
		for j in range(n + 1):
			var x := -EXTENT + j * step
			var z := -EXTENT + i * step
			var h := MapData.height(x, z)
			var col := _terrain_color(x, z, h)
			st.set_color(col)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(x, h, z))
	for i in range(n):
		for j in range(n):
			var a := i * (n + 1) + j
			var b := a + 1
			var c := a + (n + 1)
			var d := c + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mi.mesh.surface_set_material(0, mat)
	root.add_child(mi)


static func _terrain_color(x: float, z: float, h: float) -> Color:
	var c := GRASS.lerp(GRASS_DARK, clampf((h - 3.0) / 22.0, 0.0, 1.0))
	if h <= 1.35:
		c = SAND
	if h <= 0.2:
		c = Color(0.72, 0.64, 0.42)
	for road in MapData.ROADS:
		var d := _dist_to_seg(x, z, road[0], road[1], road[2], road[3])
		if d < 3.2:
			var t := clampf((3.2 - d) / 1.2, 0.0, 1.0)
			c = c.lerp(ROAD, t)
	return c


static func _dist_to_seg(x: float, z: float, x1: float, z1: float, x2: float, z2: float) -> float:
	var dx := x2 - x1
	var dz := z2 - z1
	var len_sq := dx * dx + dz * dz
	var t := 0.0
	if len_sq > 0.001:
		t = clampf(((x - x1) * dx + (z - z1) * dz) / len_sq, 0.0, 1.0)
	var px := x1 + t * dx
	var pz := z1 + t * dz
	return Vector2(x - px, z - pz).length()


static func _water(root: Node3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(EXTENT * 4.0, EXTENT * 4.0)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.32, 0.45, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.mesh.surface_set_material(0, mat)
	mi.position.y = 0.55
	root.add_child(mi)


static func _roads(root: Node3D) -> void:
	for r in MapData.ROADS:
		var a := Vector2(r[0], r[1])
		var b := Vector2(r[2], r[3])
		var mid := (a + b) * 0.5
		var road_len := a.distance_to(b)
		var ang := atan2(b.x - a.x, b.y - a.y)
		var box := BoxMesh.new()
		box.size = Vector3(5.0, 0.06, road_len + 6.0)
		var mi := MeshInstance3D.new()
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ROAD
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.mesh.surface_set_material(0, mat)
		root.add_child(mi)
		mi.position = Vector3(mid.x, MapData.height(mid.x, mid.y) + 0.05, mid.y)
		mi.rotation.y = ang


static func _structures(root: Node3D) -> void:
	var bld_mat := StandardMaterial3D.new()
	bld_mat.albedo_color = Color(0.62, 0.6, 0.56)
	bld_mat.roughness = 1.0
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.32, 0.34, 0.4)
	roof_mat.roughness = 1.0
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.5, 0.46, 0.4)
	floor_mat.roughness = 1.0
	for b in MapData.BUILDINGS:
		var x := float(b[0])
		var z := float(b[1])
		var sx := float(b[2])
		var sz := float(b[3])
		var h := float(b[4])
		var roof_h := float(b[5])
		var y := float(MapData.height(x, z))
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(sx, h, sz)
		body.mesh = bm
		body.mesh.surface_set_material(0, bld_mat)
		body.position = Vector3(x, y + h * 0.5, z)
		root.add_child(body)
		var roof := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(sx * 1.15, roof_h, sz * 1.15)
		roof.mesh = rm
		roof.mesh.surface_set_material(0, roof_mat)
		roof.position = Vector3(x, y + h + roof_h * 0.5, z)
		root.add_child(roof)
		# collider
		var sb := StaticBody3D.new()
		var col := BoxShape3D.new()
		col.size = Vector3(sx, h + roof_h, sz)
		var cs := CollisionShape3D.new()
		cs.shape = col
		sb.add_child(cs)
		sb.position = Vector3(x, y + (h + roof_h) * 0.5, z)
		root.add_child(sb)


static func _props(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260214
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.45, 0.43, 0.4)
	rock_mat.roughness = 1.0
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.26, 0.18)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.22, 0.4, 0.2)
	for i in 46:
		var x := rng.randf_range(-EXTENT + 40.0, EXTENT - 40.0)
		var z := rng.randf_range(-EXTENT + 40.0, EXTENT - 40.0)
		var h := MapData.height(x, z)
		if h <= 1.8:
			continue
		if _near_any(x, z):
			continue
		var s := rng.randf_range(0.8, 2.2)
		var rock := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(s, s * 0.6, s * rng.randf_range(0.7, 1.3))
		rock.mesh = bm
		rock.mesh.surface_set_material(0, rock_mat)
		rock.position = Vector3(x, h + s * 0.2, z)
		rock.rotation.y = rng.randf_range(0.0, TAU)
		root.add_child(rock)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs
		sb.add_child(cs)
		sb.position = rock.position
		sb.rotation.y = rock.rotation.y
		root.add_child(sb)
	for i in 70:
		var x := rng.randf_range(-420.0, 420.0)
		var z := rng.randf_range(-420.0, 420.0)
		var h := MapData.height(x, z)
		if h <= 2.4:
			continue
		if _near_any(x, z):
			continue
		var trunk := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.22
		cyl.bottom_radius = 0.3
		cyl.height = 3.4
		trunk.mesh = cyl
		trunk.mesh.surface_set_material(0, trunk_mat)
		trunk.position = Vector3(x, h + 1.7, z)
		root.add_child(trunk)
		var canopy := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 1.7
		sph.height = 3.0
		canopy.mesh = sph
		canopy.mesh.surface_set_material(0, leaf_mat)
		canopy.position = Vector3(x, h + 4.2, z)
		root.add_child(canopy)


static func _near_any(x: float, z: float) -> bool:
	for b in MapData.BUILDINGS:
		if Vector2(x - b[0], z - b[1]).length() < 12.0:
			return true
	for p in MapData.LOOT_POINTS:
		if Vector2(x - p[0], z - p[1]).length() < 7.0:
			return true
	return false


static func _environment(root: Node3D) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.68, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.86)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	root.add_child(sun)
