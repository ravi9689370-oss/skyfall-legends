# hud.gd — original mobile-first HUD: virtual joystick, look pad, action
# cluster, minimap with zone rings, health/armor/ammo, kill feed, toasts and
# damage vignette. Everything is code-built (no scene files) for reviewability.
class_name Hud
extends Control


const BTN := 62.0
const BTN_BIG := 96.0
const BTN_GAP := 8.0

var joystick_vec := Vector2.ZERO
var look_sensitivity := 1.0
var control_flags := {
	"sprint": false, "crouch": false, "jump": false, "ability": false,
	"deploy": false, "reload": false, "swap": false, "heal": false,
	"pickup": false, "nade": false, "aim": false, "fire": false, "fire_hold": false,
}
var self_hp := 100.0
var self_armor := 0.0
var self_ammo := 0
var self_reserve := 0
var self_weapon := "fists"
var self_heals_a := 0
var self_heals_b := 0
var self_nades := 0
var self_state := 2
var self_ability_cd := 0.0
var alive_count := 8
var match_t := 0.0
var zone_phase_idx := 0
var zone_state := 0
var zone_time_left := 0.0
var spectating_name := ""
var self_char := "ranger"
var spectate_pid := 0

var entities: Array = []        # [{pid,pos,team,alive,state}] for minimap
var zone := {}                  # live zone state from snapshots
var loot_dots: Array = []       # [{pos, tier}]
var minimap_scale := 0.115

var _joy_center := Vector2.ZERO
var _joy_radius := 60.0
var _joy_touch := -1
var _look_id := -1
var _look_last := Vector2.ZERO
var _look_delta := Vector2.ZERO
var _feed: Array = []           # kill feed lines
var _toasts: Array = []
var _wrong_hp_flash := 0.0
var _hit_marker := 0.0
var _ability_btn: Button
var _hp_bar: ProgressBar
var _armor_bar: ProgressBar
var _ammo_label: Label
var _heal_btn: Button
var _nade_btn: Button
var _feed_label: Label
var _toast_label: Label
var _zone_label: Label
var _timer_label: Label
var _alive_label: Label
var _weapon_label: Label
var _state_label: Label
var _deploy_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_controls()


func _build_controls() -> void:
	# ---- look pad (full screen, behind everything)
	var look_pad := LookPad.new()
	look_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	look_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(look_pad)
	look_pad.hud = self

	# ---- joystick
	_joy_radius = 58.0
	_joy_center = Vector2(118, size.y - 128)

	# ---- top-right: timer, zone, alive
	_timer_label = _label(Vector2(-16, 12), "MATCH 0:00", HORIZONTAL_ALIGNMENT_RIGHT)
	_zone_label = _label(Vector2(-16, 44), "ZONE", HORIZONTAL_ALIGNMENT_RIGHT)
	_alive_label = _label(Vector2(-16, 74), "ALIVE %d" % alive_count, HORIZONTAL_ALIGNMENT_RIGHT)

	# ---- bottom-right cluster (mobile thumbs)
	var bx := size.x - BTN - 22.0
	var by := size.y - BTN_BIG - 120.0
	var fire := _btn(Vector2(bx, size.y - BTN_BIG - 26.0), BTN_BIG, "FIRE")
	fire.button_down.connect(func(): control_flags["fire_hold"] = true)
	fire.button_up.connect(func(): control_flags["fire_hold"] = false)
	fire.pressed.connect(func(): control_flags["fire"] = true)
	_btn(Vector2(bx - BTN - BTN_GAP, by + BTN + BTN_GAP), BTN, "AIM").pressed.connect(func(): control_flags["aim"] = true)
	_btn(Vector2(bx - 2 * (BTN + BTN_GAP), by + BTN + BTN_GAP), BTN, "JUMP").pressed.connect(func(): control_flags["jump"] = true)
	_btn(Vector2(bx - BTN - BTN_GAP, by), BTN, "RELOAD").pressed.connect(func(): control_flags["reload"] = true)
	_nade_btn = _btn(Vector2(bx - 2 * (BTN + BTN_GAP), by), BTN, "G\nx0")
	_nade_btn.pressed.connect(func(): control_flags["nade"] = true)
	_btn(Vector2(bx - 3 * (BTN + BTN_GAP), by + BTN + BTN_GAP), BTN, "SWAP").pressed.connect(func(): control_flags["swap"] = true)
	_heal_btn = _btn(Vector2(bx - 3 * (BTN + BTN_GAP), by), BTN, "MED x0")
	_heal_btn.pressed.connect(func(): control_flags["heal"] = true)
	_ability_btn = _btn(Vector2(bx - 4 * (BTN + BTN_GAP), by), BTN, "ABIL")
	_ability_btn.pressed.connect(func(): control_flags["ability"] = true)
	_btn(Vector2(bx - 4 * (BTN + BTN_GAP), by + BTN + BTN_GAP), BTN, "CROP").pressed.connect(func(): control_flags["crouch"] = true)
	_btn(Vector2(size.x - BTN - 22.0, size.y - 2 * BTN - 40.0), BTN, "GRAB").pressed.connect(func(): control_flags["pickup"] = true)
	_deploy_btn = _btn(Vector2(size.x / 2.0 - BTN / 2.0, size.y - BTN_BIG - 60.0), BTN_BIG, "DROP")
	_deploy_btn.visible = false
	_deploy_btn.pressed.connect(func(): control_flags["deploy"] = true)

	# ---- bottom-left: health/armor bars + weapon/ammo
	var hp_pos := Vector2(212, size.y - 176)
	_hp_bar = _bar(hp_pos, Color(0.15, 0.85, 0.45))
	_armor_bar = _bar(hp_pos + Vector2(0, 20), Color(0.3, 0.55, 0.95))
	_armor_bar.size = Vector2(160, 14)
	_weapon_label = _label(hp_pos + Vector2(0, 40), "Tanto Blade", HORIZONTAL_ALIGNMENT_LEFT)
	_ammo_label = _label(hp_pos + Vector2(0, 64), "0 / 0", HORIZONTAL_ALIGNMENT_LEFT)
	_ammo_label.add_theme_font_size_override("font_size", 26)

	# ---- center: crosshair + hitmarker vibes
	_feed_label = _label(Vector2(24, 120), "", HORIZONTAL_ALIGNMENT_LEFT)
	_feed_label.add_theme_color_override("font_color", Color(1, 0.85, 0.6))
	_toast_label = _label(Vector2(0, size.y * 0.24), "", HORIZONTAL_ALIGNMENT_CENTER)
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.add_theme_font_size_override("font_size", 22)

	# ---- mission display for various states
	_state_label = _label(Vector2(0, size.y * 0.34), "", HORIZONTAL_ALIGNMENT_CENTER)
	_state_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_state_label.add_theme_font_size_override("font_size", 30)


func _label(pos: Vector2, text: String, align: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(340, 26)
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", 18)
	add_child(l)
	return l


func _btn(pos: Vector2, s: float, text: String) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = Vector2(s, s)
	b.text = text
	b.add_theme_font_size_override("font_size", 15)
	add_child(b)
	return b


func _bar(pos: Vector2, col: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.position = pos
	p.size = Vector2(160, 14)
	p.max_value = 100.0
	p.show_percentage = false
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	p.add_theme_stylebox_override("fill", fg)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.07, 0.09, 0.7)
	p.add_theme_stylebox_override("background", bg)
	add_child(p)
	return p


# ------------------------------------------------------------------ per-frame

func consume_look_delta() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d


func _process(_delta: float) -> void:
	# keep trailing HUD in sync
	_hp_bar.value = self_hp
	_armor_bar.value = self_armor
	_weapon_label.text = "held: %s" % self_weapon
	_ammo_label.text = "%d / %d" % [self_ammo, self_reserve]
	_nade_btn.text = "G\nx%d" % self_nades
	_heal_btn.text = "MK x%d" % self_heals_a
	_ability_btn.text = "ABIL %d" % self_ability_cd
	_timer_label.text = _fmt_time(match_t)
	_zone_label.text = _zone_text()
	_alive_label.text = "ALIVE %d" % alive_count
	_deploy_btn.visible = self_state == 0
	_state_label.text = spectating_name
	if _hit_marker > 0.0:
		_hit_marker -= _delta * 3.0
	if _wrong_hp_flash > 0.0:
		_wrong_hp_flash -= _delta * 1.4
	queue_redraw()


func set_state_hint(txt: String) -> void:
	spectating_name = txt


func _fmt_time(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	return "MATCH %d:%02d" % [m, s]


func _zone_text() -> String:
	var z: Dictionary = zone
	if z.is_empty():
		return "ZONE"
	var phase := int(z.get("phase_idx", 0)) + 1
	var st := "GROW" if int(z.get("state", 0)) == 0 else "SHRINK"
	return "R%d %s %.0fs (dps %.0f)" % [phase, st, float(z.get("time_left", 0.0)), float(z.get("dps", 0.0))]


# ---------------------------------------------------------------- update API

func apply_self(you: Dictionary) -> void:
	self_state = int(you["state"])
	self_hp = float(you["hp"])
	self_armor = float(you["armor"])
	self_weapon = str(you["weapon"])
	self_ammo = int(you["mag"])
	self_reserve = int(you["reserve"])
	self_heals_a = int(you["heals_a"])
	self_heals_b = int(you["heals_b"])
	self_nades = int(you["nades"])
	self_ability_cd = float(you["ability_left"])
	decorate_me()


func decorate_me() -> void:
	pass


func apply_zone(z: Dictionary) -> void:
	zone = z


func apply_entities(list: Array) -> void:
	entities = list
	alive_count = 0
	for e in entities:
		if bool(e.get("alive", true)):
			alive_count += 1


func notify_event(ev: Dictionary) -> void:
	match int(ev.get("t", -1)):
		MatchEvents.HIT_TAKEN:
			_wrong_hp_flash = 1.0
			_toasts.append("Taking fire!")
		MatchEvents.HIT_DEALT:
			if bool(ev.get("kill", false)):
				_hit_marker = 2.0
				_feed.append("You eliminated!")
				_toasts.append("ELIMINATED")
			else:
				_hit_marker = 1.0
		MatchEvents.HEALED:
			_toasts.append("Healed")
		MatchEvents.ELIMINATION:
			_feed.append("ELIMINATION (see feed)")
		MatchEvents.LOOT_CLAIMED:
			if bool(ev.get("yours", false)):
				_toasts.append("Picked up %s" % str(ev.get("item", "?")))
		MatchEvents.ZONE_ANNOUNCE:
			if int(ev.get("phase_idx", 0)) >= 90:
				_toasts.append("Match over")
			else:
				_toasts.append("Shrink inbound! ring %d: r=%.0fm" % [int(ev.get("phase_idx", 0)) + 1, float(ev.get("radius", 0))])
		MatchEvents.MSG:
			_toasts.append(str(ev.get("msg", "")))
		MatchEvents.SPECTATE_OFFER:
			spectate_pid = int(ev.get("pid", 0))
			_toasts.append("Now following %s" % str(ev.get("name", "?")))
		MatchEvents.ABILITY:
			_toasts.append("Ability used")
		_:
			pass
	if _feed.size() > 4:
		_feed.pop_front()


# ---------------------------------------------------------------- capability

func _draw() -> void:
	# joystick
	var jj := _joy_center
	if _joy_touch >= 0:
		draw_circle(jj, _joy_radius + 4, Color(1, 1, 1, 0.12))
	draw_circle(jj, _joy_radius * 0.42, Color(1, 1, 1, 0.25))
	var knob := jj + joystick_vec * _joy_radius * 0.6
	draw_circle(knob, _joy_radius * 0.3, Color(1, 1, 1, 0.4))

	# crosshair
	var c := size * 0.5
	draw_circle(c, 3, Color(1, 1, 1, 0.95))
	if _hit_marker > 0:
		draw_line(c + Vector2(-10, -10), c + Vector2(-4, -4), Color(1, 0.3, 0.25, clampf(_hit_marker, 0, 1)), 2)
		draw_line(c + Vector2(10, 10), c + Vector2(4, 4), Color(1, 0.3, 0.25, clampf(_hit_marker, 0, 1)), 2)
		draw_line(c + Vector2(10, -10), c + Vector2(4, -4), Color(1, 0.3, 0.25, clampf(_hit_marker, 0, 1)), 2)
		draw_line(c + Vector2(-10, 10), c + Vector2(-4, 4), Color(1, 0.3, 0.25, clampf(_hit_marker, 0, 1)), 2)
	if _wrong_hp_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.1, 0.1, clampf(_wrong_hp_flash, 0, 1) * 0.25), true)

	# minimap
	var map_c := Vector2(size.x - 92, 108)
	var map_r := 82.0
	draw_circle(map_c, map_r + 2, Color(0, 0, 0, 0.45))
	draw_circle(map_c, map_r, Color(0.4, 0.7, 0.55, 0.22))
	var z: Dictionary = zone
	if not z.is_empty():
		var zzScale := float(map_r) / 520.0
		var cur_c: Vector3 = z.get("cur_center", Vector3.ZERO)
		var cur_r: float = float(z.get("cur_radius", 0.0))
		draw_arc(map_c + Vector2(cur_c.x, cur_c.z) * zzScale, cur_r * zzScale, 0, TAU, 40, Color(1, 1, 1, 0.85), 2.0)
		var next_c: Vector3 = z.get("next_center", Vector3.ZERO)
		var next_r := float(z.get("next_radius", 0.0))
		draw_arc(map_c + Vector2(next_c.x, next_c.z) * zzScale, next_r * zzScale, 0, TAU, 40, Color(1, 0.85, 0.3, 0.6), 1.6)
	for l in loot_dots:
		var lp: Vector3 = l.get("pos", Vector3.ZERO)
		var at := map_c + Vector2(lp.x, lp.z) * minimap_scale
		if at.distance_to(map_c) <= map_r:
			draw_circle(at, 2.2, Color(1, 0.9, 0.4, 0.9))
	for ent in entities:
		var ep: Vector3 = ent.get("pos", Vector3.ZERO)
		var et: int = int(ent.get("team", 0))
		var at2 := map_c + Vector2(ep.x, ep.z) * minimap_scale
		draw_circle(at2, 3.4, Mannequin.team_colors(et))
