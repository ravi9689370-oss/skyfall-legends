# net_client.gd — client-side ENet session wrapper. Owns the socket state and
# emits typed signals for the game state machine; gameplay and UI never touch
# raw packets. Endpoint: host:port, ENet UDP, op-code protocol (see protocol.gd).
class_name NetClient
extends RefCounted


signal hello_ok(info: Dictionary)
signal lobby_state(info: Dictionary)
signal lobby_msg(msg: String)
signal match_started(info: Dictionary)
signal snapshot(data: Dictionary)
signal match_event(ev: Dictionary)
signal match_end(data: Dictionary)
signal closed(reason: String)
signal pong(dt: float)

var peer: ENetMultiplayerPeer
var connected := false
var connected_host := ""
var connected_port := 0
var my_pid := 0
var _pending_hello := false
var _hello_name := ""
var _hello_char := ""


func connect_to(host: String, port: int, name: String, char_id: String) -> String:
	if connected:
		disconnect_now("reconnect")
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		return "Connection failed (code %d)" % err
	peer.peer_connected.connect(_on_connected)
	peer.peer_disconnected.connect(_on_server_disconnected)
	connected_host = host
	connected_port = port
	_hello_name = name
	_hello_char = char_id
	_pending_hello = true
	return ""


func disconnect_now(reason: String = "") -> void:
	if peer != null:
		peer.close()
	peer = null
	_pending_hello = false
	connected = false
	if reason != "":
		closed.emit(reason)


func _on_connected(pid: int) -> void:
	connected = true
	if _pending_hello:
		_pending_hello = false
		_peer_send(1, Protocol.c_hello(_hello_name, _hello_char))


func _on_server_disconnected() -> void:
	connected = false
	_pending_hello = false
	closed.emit("Connection to server lost.")


func _on_packet(pid: int, bytes: PackedByteArray) -> void:
	var dec := Protocol.decode(bytes)
	if dec.is_empty():
		return
	var op: int = int(dec["op"])
	var b: StreamPeerBuffer = dec["b"]
	match op:
		Protocol.Op.HELLO_OK:
			my_pid = int(b.get_u32())
			var sname := Protocol.get_str(b)
			var motd := Protocol.get_str(b)
			hello_ok.emit({"pid": my_pid, "server": sname, "motd": motd})
		Protocol.Op.LOBBY_STATE:
			lobby_state.emit(Protocol.parse_lobby_state(b))
		Protocol.Op.LOBBY_MSG:
			lobby_msg.emit(Protocol.get_str(b))
		Protocol.Op.MATCH_START:
			match_started.emit(Protocol.parse_match_start(b))
		Protocol.Op.SNAPSHOT:
			snapshot.emit(Protocol.parse_snapshot(b))
		Protocol.Op.MATCH_EVENT:
			match_event.emit(Protocol._read_event(b))
		Protocol.Op.MATCH_END:
			match_end.emit(Protocol.parse_match_end(b))
		Protocol.Op.SERVER_CLOSE, Protocol.Op.KICKED:
			closed.emit(Protocol.get_str(b))
		Protocol.Op.PONG:
			pong.emit(float(b.get_double()))
		_:
			pass


func _peer_send(target: int, bytes: PackedByteArray, rel := true) -> void:
	if peer == null:
		return
	peer.set_transfer_channel(0)
	peer.set_transfer_mode(
		MultiplayerPeer.TRANSFER_MODE_RELIABLE if rel else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	peer.set_target_peer(target)
	peer.put_packet(bytes)


# Pump the ENet socket and dispatch incoming packets. Call once per frame from
# the owning Node's _process.
func _poll(delta: float) -> void:
	if peer == null:
		return
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var pid := peer.get_packet_peer()
		var bytes := peer.get_packet()
		_on_packet(pid, bytes)


# ---------------------------------------------------------------- outbound

func create_lobby(mode: String, is_private: bool) -> void:
	_peer_send(1, Protocol.c_lobby_create(mode, is_private))


func join_lobby(code: String, mode: String, char_id: String) -> void:
	_peer_send(1, Protocol.c_lobby_join(code, mode, char_id))


func set_ready(ready: bool, char_id: String) -> void:
	_peer_send(1, Protocol.c_set_ready(ready, char_id))


func back() -> void:
	_peer_send(1, Protocol.c_back())


func send_input(seq: int, pos: Vector3, yaw: float, move: Vector2, flags: Dictionary) -> void:
	_peer_send(1, Protocol.c_input(seq, pos, yaw, move, flags), false)


func send_fire(yaw: float, dir: Vector3) -> void:
	_peer_send(1, Protocol.c_fire(yaw, dir), false)


func use_item(kind: String) -> void:
	_peer_send(1, Protocol.c_use_item(kind))


func pickup() -> void:
	_peer_send(1, Protocol.c_pickup())


func reload() -> void:
	_peer_send(1, Protocol.c_reload())


func switch_weapon(slot: int) -> void:
	_peer_send(1, Protocol.c_switch(slot))


func spectate(pid: int) -> void:
	_peer_send(1, Protocol.c_spectate(pid))


func ping(t: float) -> void:
	_peer_send(1, Protocol.c_ping(t), false)
