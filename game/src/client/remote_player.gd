# remote_player.gd — visual read-only actor for every non-local player. State
# comes only from server snapshots; position/yaw are interpolated. Nothing
# here is authoritative — it mirrors the simulation.
class_name RemotePlayer
extends Node3D


var pid := 0
var target_pos := Vector3.ZERO
var target_yaw := 0.0
var alive := true
var air_state := 2
var held := ""
var team := 0
var display_name := ""
var mannequin: Mannequin
var name_label: Label3D


func _init(pid_in: int, char_id: String, team_in: int, display_name_in: String) -> void:
	pid = pid_in
	team = team_in
	display_name = display_name_in
	mannequin = Mannequin.new(char_id, team_in)
	add_child(mannequin)
	name_label = Label3D.new()
	name_label.text = display_name_in
	name_label.font_size = 40
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.outline_size = 6
	name_label.position = Vector3(0, 2.2, 0)
	add_child(name_label)


func update_from(o: Dictionary) -> void:
	var pos_in: Vector3 = o["pos"]
	target_pos = pos_in
	target_yaw = o["yaw"]
	alive = bool(o["alive"])
	air_state = int(o["state"])
	var held_in := str(o["held"])
	if held_in != held:
		held = held_in
		mannequin.set_held(held)
	air_state = int(o["state"])
	mannequin.set_chute(air_state == 1)
	visible = air_state >= 1 and alive


func _process(delta: float) -> void:
	var t := 1.0 - exp(-12.0 * delta)
	var prev := position
	position = position.lerp(target_pos, t)
	var yaw_diff := wrapf(target_yaw - rotation.y, -PI, PI)
	rotation.y += yaw_diff * t
	var moving := (target_pos - prev).length() > 0.4
	mannequin.tick_anim(delta, moving)
