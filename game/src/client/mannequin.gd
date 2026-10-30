# mannequin.gd — procedural original character visual. No imported meshes:
# every Skyfall avatar is assembled from flat-shaded primitive parts colored by
# the character's palette, with a style variant (visor / cap / helm) that makes
# each roster member readable at range. Cheap enough for 9 actors on mobile.
class_name Mannequin
extends Node3D


var suit_color := Color(0.3, 0.4, 0.5)
var trim_color := Color(0.9, 0.7, 0.2)
var visor_color := Color(0.8, 0.9, 1.0)
var style := "visor"
var walk_phase := 0.0
var moving := false

var _legs: Array = []
var _arms: Array = []
var _head: Node3D
var _chute: MeshInstance3D
var _slot: MeshInstance3D
const colors := {}


func _init(char_id: String, team: int) -> void:
	var ch: Dictionary = CharactersDB.get_character(char_id)
	var pal: Dictionary = ch.get("palette", {})
	suit_color = pal.get("suit", suit_color)
	trim_color = pal.get("trim", trim_color)
	visor_color = pal.get("visor", visor_color)
	style = str(ch.get("style", "visor"))
	_build(team)


func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, rotate_deg := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mi.mesh.surface_set_material(0, mat)
	parent.add_child(mi)
	mi.position = pos
	if rotate_deg != 0.0:
		mi.rotation.y = deg_to_rad(rotate_deg)
	return mi


func _build(team: int) -> void:
	var body := Node3D.new()
	add_child(body)
	# torso
	_box(body, Vector3(0.55, 0.72, 0.34), Vector3(0, 1.08, 0), suit_color)
	# belt (team color)
	_box(body, Vector3(0.58, 0.12, 0.37), Vector3(0, 0.78, 0), team_colors(team))
	# head + style
	var head := Node3D.new()
	head.position = Vector3(0, 1.58, 0)
	body.add_child(head)
	_head = head
	match style:
		"cap":
			_box(head, Vector3(0.34, 0.3, 0.32), Vector3.ZERO, Color(0.82, 0.72, 0.6))
			_box(head, Vector3(0.38, 0.06, 0.4), Vector3(0, 0.06, 0.06), trim_color)
		"helm":
			_box(head, Vector3(0.38, 0.34, 0.36), Vector3.ZERO, Color(0.55, 0.57, 0.6))
			_box(head, Vector3(0.3, 0.08, 0.06), Vector3(0, 0.02, 0.2), visor_color)
		"visor":
			_box(head, Vector3(0.33, 0.32, 0.3), Vector3.ZERO, Color(0.76, 0.62, 0.5))
			_box(head, Vector3(0.29, 0.1, 0.05), Vector3(0, 0.05, 0.185), visor_color)
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.37, 1.4, 0)
		body.add_child(arm)
		_arms.append(arm)
		_box(arm, Vector3(0.16, 0.62, 0.16), Vector3(0, -0.3, 0), suit_color)
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.15, 0.72, 0)
		body.add_child(leg)
		_legs.append(leg)
		_box(leg, Vector3(0.19, 0.72, 0.2), Vector3(0, -0.36, 0), suit_color)
	# weapon slot in right hand area
	_slot = _box(body, Vector3(0.1, 0.1, 0.7), Vector3(0.42, 1.25, -0.2), Color(0.2, 0.2, 0.2))
	_slot.visible = false
	# parachute
	_chute = _box(body, Vector3(2.4, 0.35, 2.4), Vector3(0, 3.1, 0), trim_color)
	_chute.visible = false


static func team_colors(team: int) -> Color:
	var arr := [
		Color(0.85, 0.36, 0.3), Color(0.3, 0.6, 0.85), Color(0.5, 0.75, 0.35), Color(0.85, 0.7, 0.3),
	]
	return arr[team % 4]


func set_held(wid: String) -> void:
	if wid == "" or wid == "grenade_skyring":
		_slot.visible = false
		return
	var w := WeaponsDB.get_weapon(wid)
	if w.is_empty():
		_slot.visible = false
		return
	var cat := int(w["cat"])
	_slot.visible = cat != WeaponsDB.Cat.MELEE
	match cat:
		WeaponsDB.Cat.SNIPER:
			_slot.mesh.size = Vector3(0.09, 0.1, 1.1)
		WeaponsDB.Cat.SG:
			_slot.mesh.size = Vector3(0.11, 0.12, 0.85)
		WeaponsDB.Cat.SMG:
			_slot.mesh.size = Vector3(0.09, 0.12, 0.62)
		_:
			_slot.mesh.size = Vector3(0.1, 0.11, 0.78)
	if wid in ["ar_vanguard", "ar_compass"]:
		_slot.mesh.size = Vector3(0.1, 0.11, 0.86)


func set_chute(v: bool) -> void:
	_chute.visible = v


func tick_anim(dt: float, is_moving: bool) -> void:
	moving = is_moving
	if moving:
		walk_phase += dt * 9.0
	else:
		walk_phase += dt * 2.0
	var amp := 0.7 if moving else 0.06
	var s := sin(walk_phase)
	for i in _legs.size():
		var leg: Node3D = _legs[i]
		leg.rotation.x = s * amp * (1.0 if i == 0 else -1.0)
	for i in _arms.size():
		var arm: Node3D = _arms[i]
		arm.rotation.x = -s * amp * (1.0 if i == 0 else -1.0)
