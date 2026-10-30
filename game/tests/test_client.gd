# NetClient wrapper with its own ENet peer (so several clients can run side by
# side), a signal-driven event log, await-style waiters (wait_for / wait_cond /
# wait_for_event) and a periodic "ticker" system for scripted input bursts.
# Everything a real client can do goes through the same wire protocol; the
# helper never touches server state directly.
class_name TestClient
extends Node


const TICK_S := 0.1 # ticker cadence (adds <=2 msgs/s per ticker vs the 70/s cap)

var host: Node = null            # tree-attached node used for timers/frames
var net: NetClient
var deploy_sent := false

var _kind_counts: Dictionary = {}   # kind -> how many records seen
var _last_of: Dictionary = {}       # kind -> latest record payload
var _evs: Array = []                # every parsed match event dict, in order
var _snap: Dictionary = {}
var _match: Dictionary = {}
var _team := 0
var _seq := 0

var _tickers: Dictionary = {}   # id -> Callable
var _next_ticker := 1
var _tick_accum := 0.0


func _init(host_in: Node = null) -> void:
	host = host_in
	net = NetClient.new()
	set_process(true)  # drive the ENet poll loop from _process
	net.hello_ok.connect(_on_hello)
	net.lobby_state.connect(_on_lobby)
	net.lobby_msg.connect(func(msg: String) -> void: _rec("msg", {"msg": msg}))
	net.match_started.connect(_on_match_start)
	net.snapshot.connect(_on_snapshot)
	net.match_event.connect(_event_rec)
	net.match_end.connect(func(d: Dictionary) -> void: _rec("end", d))
	net.closed.connect(func(reason: String) -> void: _rec("closed", {"reason": reason}))
	net.pong.connect(func(dt: float) -> void: _rec("pong", {"dt": dt}))


# --------------------------------------------------------------- record wiring

func _rec(kind: String, data: Dictionary) -> void:
	_kind_counts[kind] = int(_kind_counts.get(kind, 0)) + 1
	_last_of[kind] = data


func _on_hello(d: Dictionary) -> void:
	_rec("hello", d)


func _on_lobby(d: Dictionary) -> void:
	_rec("lobby", d)
	for p in d.get("players", []):
		if int(p.get("pid", 0)) == net.my_pid:
			_team = int(p.get("team", _team))


func _on_match_start(d: Dictionary) -> void:
	_match = d
	_rec("match", d)
	for p in d.get("players", []):
		if int(p.get("pid", 0)) == net.my_pid:
			_team = int(p.get("team", _team))


func _event_rec(ev: Dictionary) -> void:
	_evs.append(ev)
	_kind_counts["event"] = int(_kind_counts.get("event", 0)) + 1
	_last_of["event"] = ev


func _on_snapshot(data: Dictionary) -> void:
	_snap = data
	_rec("snap", data)
	for ev in data.get("events", []):
		_event_rec(ev)


func _host_timer(s: float) -> void:
	var tree: SceneTree = null
	if host != null and host.is_inside_tree():
		tree = host.get_tree()
	elif is_inside_tree():
		tree = get_tree()
	elif Engine.get_main_loop() is SceneTree:
		tree = Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.create_timer(s).timeout


# ------------------------------------------------------------------- waiters
# wait_for(kind): true when a record of that kind already arrived or lands in
# the window. wait_for_event: scans only events that arrive fresh during the
# window so repeated calls do not consume stale matches.

func wait_for(kind: String, timeout: float) -> bool:
	if int(_kind_counts.get(kind, 0)) > 0:
		return true
	var waited := 0.0
	while waited < timeout:
		await _host_timer(0.05)
		waited += 0.05
		if int(_kind_counts.get(kind, 0)) > 0:
			return true
	return false


func wait_for_event(evkind: int, timeout: float) -> Dictionary:
	var start := _evs.size()
	var waited := 0.0
	while waited < timeout:
		for i in range(start, _evs.size()):
			if int(_evs[i].get("t", -1)) == evkind:
				return _evs[i]
		await _host_timer(0.05)
		waited += 0.05
	return {}


func wait_cond(pred: Callable, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if pred.call():
			return true
		await _host_timer(0.05)
		waited += 0.05
	return pred.call()


# ------------------------------------------------------------------ accessors

func last(kind: String) -> Dictionary:
	return _last_of.get(kind, {})


func last_self() -> Dictionary:
	return _last_of.get("snap", {}).get("you", {})


func last_others() -> Array:
	return _last_of.get("snap", {}).get("others", [])


func last_team() -> int:
	return _team


func self_state() -> int:
	return int(last_self().get("state", MatchSim.State.PLANE))


func self_pos() -> Vector3:
	return last_self().get("pos", Vector3.ZERO)


func self_pid() -> int:
	return net.my_pid


func next_seq() -> int:
	_seq += 1
	return _seq


func match_info() -> Dictionary:
	return _match


func is_peer_connected() -> bool:
	return net.connected


func connect_now(pname: String, char_id: String, port: int) -> bool:
	var errtxt := net.connect_to("127.0.0.1", port, pname, char_id)
	if errtxt != "":
		return false
	# ENet connects asynchronously; the hello (and thus the lobby handshake)
	# is only sent once connected_to_server fires, so wait for it here.
	var waited := 0.0
	while not net.connected and waited < 8.0:
		await _host_timer(0.05)
		waited += 0.05
	return net.connected


# -------------------------------------------------------------------- tickers

func _process(delta: float) -> void:
	net._poll(delta)
	_tick_accum += delta
	if _tick_accum >= TICK_S:
		_tick_accum = 0.0
		_run_tickers()


func _run_tickers() -> void:
	for id in _tickers.keys():
		var fn: Callable = _tickers[id]
		if fn.is_valid():
			fn.call()


func add_ticker(fn: Callable) -> int:
	var id := _next_ticker
	_next_ticker += 1
	_tickers[id] = fn
	return id


func remove_ticker(id: int) -> void:
	_tickers.erase(id)


# Continuous server-validated walk in one compass direction.
func push_move_ticker(vec: Vector2) -> int:
	return add_ticker(func() -> void:
		if self_state() != MatchSim.State.GROUND:
			return
		net.send_input(next_seq(), self_pos(), 0.0, vec,
			{"sprint": false, "crouch": false, "jump": false, "deploy": false, "ability": false})
	)


# Fires at a specific foe from the shooter's eye, but only when both are on the
# ground (the authoritative sim ignores fire against airborne or dead targets).
func push_aim_fire_ticker(foe_pid: int) -> int:
	return add_ticker(func() -> void:
		if self_state() != MatchSim.State.GROUND:
			return
		for o in last_others():
			if int(o.get("pid", 0)) != foe_pid or not bool(o.get("alive", false)):
				continue
			if int(o.get("state", 0)) != MatchSim.State.GROUND:
				return
			var foe_pos: Vector3 = o.get("pos", Vector3.ZERO)
			var from_pos := self_pos()
			var to := Vector3(
				foe_pos.x - from_pos.x,
				(foe_pos.y + 1.15) - (from_pos.y + Combat.EYE_STAND),
				foe_pos.z - from_pos.z)
			if to.length_squared() < 0.0001:
				return
			var yaw := atan2(foe_pos.x - from_pos.x, foe_pos.z - from_pos.z)
			net.send_fire(yaw, to.normalized())
			return
	)
