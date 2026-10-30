# match_view.gd — in-match world view on the client: terrain/structures/props,
# loot markers, safe-zone rings, remote entities, local controller, tracers,
# grenade arcs, explosions, spectate camera. All visuals are event/snapshot
# driven — no authoritative state lives here.
class_name MatchWorld
extends Node3D


var game                     # GameRoot
var fps: FpsController
var hud: Hud
var entities: Dictionary = {}          # pid -> RemotePlayer
var loot_markers: Dictionary = {}      # lid -> Node3D
var loot_list: Array = []              # [{id,item,pos}]
var self_pid := 0
var self_weapon := ""
var world_root: Node3D
var zone_ring: MeshInstance3D
var zone_ring_mat: StandardMaterial3D
var _tracer_pool: Array = []
var _explosions: Array = []
var spectate_target_pid := 0
var match_t := 0.0


func build(info: Dictionary) -> void:
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	MapGen.build(world_root)

	loot_list = info.get("loot", [])
	for l in loot_list:
		_add_loot_marker(int(l["id"]), Vector3(l["pos"].x, float(l["pos"].y) + 0.6, l["pos"].z))

	zone_ring = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 460.0
	cyl.bottom_radius = 460.0
	cyl.height = 44.0
	cyl.radial_segments = 48
	cyl.cap_top = false
	cyl.cap_bottom = false
	zone_ring.mesh = cyl
	zone_ring_mat = StandardMaterial3D.new()
	zone_ring_mat.albedo_color = Color(0.4, 0.7, 1.0, 0.16)
	zone_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	zone_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zone_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	zone_ring.mesh.surface_set_material(0, zone_ring_mat)
	zone_ring.position.y = 18.0
	world_root.add_child(zone_ring)

	var roster: Array = info.get("players", [])
	for r in roster:
		var pid := int(r["pid"])
		if bool(r["bot"]):
			# bots are visible like anyone else (marked by name prefix)
			var b := RemotePlayer.new(pid, str(r["char"]), int(r["team"]), "BOT " + str(r["name"]))
			b.position = Vector3(r["pos"].x, float(r["pos"].y), r["pos"].z)
			entities[pid] = b
			add_child(b)
		elif pid == self_pid:
			continue
		else:
			var rp := RemotePlayer.new(pid, str(r["char"]), int(r["team"]), str(r["name"]))
			rp.position = Vector3(r["pos"].x, float(r["pos"].y), r["pos"].z)
			entities[pid] = rp
			add_child(rp)

	fps = FpsController.new()
	fps.game = game
	add_child(fps)
	var my_char := "ranger"
	for r in roster:
		if int(r["pid"]) == self_pid:
			my_char = str(r["char"])
	fps.configure(my_char)
	# First person camera takes over as soon as a match world exists.
	fps.camera.make_current()


# ------------------------------------------------------------- snapshot input

func apply_snapshot(snap: Dictionary) -> void:
	var zone: Dictionary = snap["zone"]
	var you: Dictionary = snap["you"]
	match_t = float(snap["tick"]) / 1000.0
	# zone ring size
	var cur_r := float(zone["cur_radius"])
	var c: Vector3 = zone["cur_center"]
	zone_ring.scale = Vector3(cur_r / 460.0, 1.0, cur_r / 460.0)
	zone_ring.position.x = c.x
	zone_ring.position.z = c.z

	self_weapon = str(you["weapon"])
	game.slot_mirror = int(you["slot"])
	if int(you["state"]) == 0:
		# still in the conversion plane: keep us glued to the flight line
		fps.position = Vector3(you["pos"].x, you["pos"].y, you["pos"].z)
		fps.air_state = 0
		fps.reconcile_to(Vector3(you["pos"]), 0)
	elif int(you["state"]) == 1:
		fps.air_state = 1
		fps.reconcile_to(Vector3(you["pos"]), 1)
	else:
		fps.air_state = 2

	var others: Array = snap["others"]
	for o in others:
		var pid := int(o["pid"])
		var rp: RemotePlayer = entities.get(pid)
		if rp == null:
			continue
		rp.update_from(o)
	hud.apply_self(you)
	hud.apply_zone(zone)
	fps.self_av.set_held(self_weapon)
	fps.self_av.set_chute(int(you["state"]) == 1)
	_update_minimap(others, you)
	# self sweep
	for e in snap["events"]:
		notify_event(e)


func _update_minimap(others: Array, you: Dictionary) -> void:
	var list := []
	for o in others:
		list.append({"pid": int(o["pid"]), "pos": o["pos"], "team": int(o["team"]), "alive": true})
	list.append({"pid": self_pid, "pos": you["pos"], "team": game.self_team, "alive": bool(you["alive"])})
	hud.apply_entities(list)


# ---------------------------------------------------------------- event path

func notify_event(ev: Dictionary) -> void:
	hud.notify_event(ev)
	match int(ev.get("t", -1)):
		MatchEvents.SHOT:
			_spawn_tracer(ev.get("muzzle", Vector3.ZERO), ev.get("impact", Vector3.ZERO))
		MatchEvents.GRENADE_THROWN:
			_launch_arc(ev.get("pos", Vector3.ZERO), ev.get("vel", Vector3.ZERO))
		MatchEvents.GRENADE_EXPLODED:
			_explosion(ev.get("pos", Vector3.ZERO))
		MatchEvents.ELIMINATION:
			var victim := int(ev.get("victim", 0))
			var rp: RemotePlayer = entities.get(victim)
			if rp != null:
				rp.update_from({"pid": victim, "pos": rp.target_pos, "yaw": rp.target_yaw, "alive": false, "state": 2, "held": rp.held, "team": rp.team, "char": "ranger"})
			hud.set_state_hint("Noticed elimination: you or nearby player died." if victim == self_pid else "")
			if victim == self_pid:
				spectate_target_pid = hud.spectate_pid
		MatchEvents.LOOT_CLAIMED:
			var lid := int(ev.get("lid", 0))
			var marker: Node3D = loot_markers.get(lid)
			if marker != null:
				marker.queue_free()
				loot_markers.erase(lid)
		MatchEvents.ABILITY:
			pass
		_:
			pass


# --------------------------------------------------------------------- FX

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	if from.distance_to(to) < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var mid := (from + to) * 0.5
	var d := from.distance_to(to)
	bm.size = Vector3(0.045, 0.045, d)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.35, 0.9)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.mesh.surface_set_material(0, mat)
	add_child(mi)
	mi.look_at_from_position(mid, to)
	var life := 0.09
	var timer := get_tree().create_timer(life)
	timer.timeout.connect(func():
		if is_instance_valid(mi):
			mi.queue_free()
	)
	if _tracer_pool.size() > 96:
		var oldest: MeshInstance3D = _tracer_pool.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	_tracer_pool.append(mi)


func _launch_arc(pos: Vector3, vel: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.mesh.surface_set_material(0, mat)
	add_child(mi)
	var p := pos
	var v := vel
	var t := 0.0
	var steps := 0
	while steps < 220:
		var dt := 0.016
		v.y -= 20.0 * dt
		p += v * dt
		t += dt
		steps += 1
		if p.y <= MapData.height(p.x, p.z) + 0.1 or t > 3.2:
			break
		# step every 4th frame so the node tree has room to breathe
		if steps % 4 == 0:
			mi.position = p
			await get_tree().process_frame
	mi.position = p
	var timer := get_tree().create_timer(0.6)
	timer.timeout.connect(func():
		if is_instance_valid(mi):
			mi.queue_free()
	)


func _explosion(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.mesh.surface_set_material(0, mat)
	add_child(mi)
	mi.position = pos + Vector3(0, 1.2, 0)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(7.0, 3.2, 7.0), 0.4)
	tw.tween_callback(func():
		if is_instance_valid(mi):
			mi.queue_free()
	)


func _add_loot_marker(lid: int, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.42, 0.55)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.98, 0.82, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.25, 0.02)
	mi.mesh.surface_set_material(0, mat)
	add_child(mi)
	mi.position = pos
	loot_markers[lid] = mi
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(mi, "position:y", pos.y + 0.32, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(mi, "position:y", pos.y, 0.9).set_trans(Tween.TRANS_SINE)
