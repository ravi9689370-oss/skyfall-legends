# fps_controller.gd — local player: third-person camera, input capture, and
# movement client-prediction reconciled by server snapshots. The dedicated
# server stays authoritative: local movement is a prediction only.
class_name FpsController
extends CharacterBody3D


const GRAVITY := 24.0
const JUMP_V := 7.4
const SEND_MS := 62

var game                          # GameRoot (untyped to avoid cyclic class hints)
var yaw := 0.0
var pitch := -0.26
var ads := false
var fire_held := false
var mouse_captured := false
var air_state := 2                # MatchSim.State mirror for self
var decorate := false
var last_slot := 0                # last weapon group used before nade slot
var sens := 1.0
var hud = null                    # Hud
var cam_root: Node3D
var pitch_node: Node3D
var camera: Camera3D
var self_av: Mannequin
var _seq := 0
var _send_ms := 0
var _aim := Vector3.FORWARD


func _init() -> void:
	name = "local_player"
	cam_root = Node3D.new()
	cam_root.position = Vector3(0, 1.68, 0)
	add_child(cam_root)
	pitch_node = Node3D.new()
	cam_root.add_child(pitch_node)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.1
	pitch_node.add_child(camera)
	camera.position = Vector3(0.9, 0.5, 5.4)
	camera.rotation_degrees = Vector3(0, -10, 0)


func configure(char_id: String) -> void:
	if self_av != null:
		remove_child(self_av)
		self_av.queue_free()
	self_av = Mannequin.new(char_id, 0)
	add_child(self_av)


func apply_snapshot(you: Dictionary) -> void:
	air_state = int(you["state"])
	decorate = false


func _ready() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.72
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		yaw -= event.relative.x * 0.0022 * sens
		pitch = clampf(pitch - event.relative.y * 0.0022 * sens, -1.25, 0.95)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			fire_held = true
		mouse_captured = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.is_released():
		if event.button_index == MOUSE_BUTTON_LEFT:
			fire_held = false
	elif event is InputEventKey and Input.is_key_pressed(KEY_ESCAPE):
		mouse_captured = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if game == null:
		return
	sens = float(game.settings.get("sensitivity", 1.0))

	# --- pointer look (touch drag handled by HUD)
	var look := Vector2.ZERO
	if hud != null:
		look = hud.consume_look_delta()
	if look != Vector2.ZERO:
		yaw -= look.x * 0.004 * sens
		pitch = clampf(pitch - look.y * 0.004 * sens, -1.25, 0.95)
	rotation.y = yaw
	pitch_node.rotation.x = pitch

	# --- HUD buttons + keyboard flags
	var move := _read_move()
	var sprint := Input.is_key_pressed(KEY_SHIFT)
	var crouch := false
	var jump := false
	var ability := false
	var deploy := false
	var reload_req := false
	var swap_req := false
	var heal_req := ""
	var nade_req := false
	var pickup_req := false
	var aim_req := false
	var fire_now := fire_held
	if Input.is_key_pressed(KEY_CTRL):
		crouch = true
	if Input.is_key_pressed(KEY_SPACE):
		jump = true
	if Input.is_key_pressed(KEY_Q):
		ability = true
	if Input.is_key_pressed(KEY_F):
		deploy = true
	if Input.is_key_pressed(KEY_R):
		reload_req = true
	if Input.is_key_pressed(KEY_E):
		pickup_req = true
	if Input.is_key_pressed(KEY_G):
		nade_req = true
	if Input.is_key_pressed(KEY_H):
		if hud != null and int(hud.self_heals_a) > 0:
			heal_req = "medkit"
		else:
			heal_req = "bandage"
	if hud != null:
		var f: Dictionary = hud.control_flags
		if bool(f.get("sprint", false)):
			sprint = true
		if bool(f.get("crouch", false)):
			crouch = not crouch
			f["crouch"] = false
		if bool(f.get("jump", false)):
			jump = true
			f["jump"] = false
		if bool(f.get("ability", false)):
			ability = true
			f["ability"] = false
		if bool(f.get("deploy", false)):
			deploy = true
			f["deploy"] = false
		if bool(f.get("reload", false)):
			reload_req = true
			f["reload"] = false
		if bool(f.get("swap", false)):
			swap_req = true
			f["swap"] = false
		if bool(f.get("heal", false)):
			heal_req = "bandage"
			f["heal"] = false
		if bool(f.get("pickup", false)):
			pickup_req = true
			f["pickup"] = false
		if bool(f.get("nade", false)):
			nade_req = true
			f["nade"] = false
		if bool(f.get("aim", false)):
			aim_req = true
			f["aim"] = false
		if bool(f.get("fire", false)) or bool(f.get("fire_hold", false)):
			fire_now = true
	# ADS toggle
	if aim_req:
		ads = not ads
	camera.fov = lerpf(camera.fov, 40.0 if ads else 62.0, delta * 10.0)
	camera.position = Vector3(
		lerpf(camera.position.x, 0.5 if ads else 0.9, delta * 10.0),
		lerpf(camera.position.y, 1.55 if ads else 0.5, delta * 10.0),
		lerpf(camera.position.z, 1.8 if ads else 5.4, delta * 10.0)
	)

	# --- movement prediction
	if air_state == 2:
		var speed := _speed(sprint, crouch)
		# joystick input -> WORLD-space direction (the server validates in world axes)
		var wish_world := (basis * Vector3(move.x, 0.0, move.y)) * speed
		wish_world.y = velocity.y
		velocity = wish_world
		if jump and is_on_floor():
			velocity.y = JUMP_V
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		var g := MapData.height(position.x, position.z)
		if position.y < g and velocity.y <= 0.01:
			position.y = g
			velocity.y = 0.0
	else:
		velocity = Vector3.ZERO

	# --- effects / actions
	_aim = compute_aim_dir()
	if reload_req:
		game.net.reload()
	if pickup_req:
		game.net.pickup()
	if swap_req:
		_cycle_slot()
	if heal_req != "":
		game.net.use_item(heal_req)
	if nade_req:
		_throw_nade()
	if ability:
		pass  # ability rides in the input flags

	# --- send input + fire at fixed cadence
	var now_ms := Time.get_ticks_msec()
	if now_ms - _send_ms >= SEND_MS:
		_send_ms = now_ms
		_seq += 1
		if game.net != null and game.net.connected:
			var world_move := (basis * Vector3(move.x, 0.0, move.y)).limit_length(1.0)
			game.net.send_input(_seq, position, yaw, world_move, {
				"sprint": sprint, "crouch": crouch, "jump": jump,
				"deploy": deploy, "ability": ability,
			})
			if _aim.length_squared() > 0.5 and fire_now and air_state == 2:
				game.net.send_fire(yaw, _aim)


func _speed(sprint: bool, crouch_in: bool) -> float:
	if crouch_in:
		return MatchRules.SPEED_CROUCH
	return MatchRules.SPEED_SPRINT if sprint else MatchRules.SPEED_WALK


func _cycle_slot() -> void:
	var next_slot := (int(last_slot) + 1) % 3
	last_slot = next_slot
	game.net.switch_weapon(next_slot)


func compute_aim_dir() -> Vector3:
	var from := camera.global_position + (-camera.global_transform.basis.z) * 0.4
	var to := camera.global_position + (-camera.global_transform.basis.z) * 400.0
	var params := PhysicsRayQueryParameters3D.create(from, to, 65535, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(params)
	var point: Vector3 = hit.get("position", to)
	var dir := point - (position + Vector3(0, 1.4, 0))
	if dir.length_squared() < 0.001:
		return Vector3.FORWARD
	return dir.normalized()


func _read_move() -> Vector2:
	var v := Vector2.ZERO
	if hud != null:
		v = hud.joystick_vec
	if Input.is_key_pressed(KEY_W):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		v.y += 1.0
	if Input.is_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		v.x += 1.0
	return v.limit_length(1.0)


func _throw_nade() -> void:
	if int(game.slot_mirror) == 3:
		return
	last_slot = int(game.slot_mirror)
	game.net.switch_weapon(3)
	game.net.send_fire(yaw, _aim)
	game.net.switch_weapon(last_slot)


func reconcile_to(server_pos: Vector3, server_state: int) -> void:
	if server_state != 2:
		position = server_pos
		velocity = Vector3.ZERO
		air_state = server_state
		return
	air_state = 2
	var pos_d: float = (position - server_pos).length()
	if pos_d > 2.2:
		position = server_pos
		velocity = Vector3.ZERO
	else:
		position += (server_pos - position) * 0.1


func follow(targetEntity: Node3D) -> void:
# simple spectator camera
	if targetEntity == null:
		return
	var origin := targetEntity.global_position + Vector3(0, 4.2, 6.5)
	global_position = origin
	look_at(targetEntity.global_position)
