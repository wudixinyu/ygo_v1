extends Node
## 客户端网络层（Autoload: ClientNet）
## 注意：Godot 的 TCP 在连接失败时不会报"错误状态"，必须依赖连接超时检测

signal connected
signal connect_failed(message: String)
signal login_ok(player_id: String, nickname: String)
signal room_list_received(rooms: Array)
signal room_joined(room: Dictionary)
signal room_update(room: Dictionary)
signal room_closed(reason: String)
signal watch_snapshot_received(room: Dictionary)
signal watch_ended(reason: String)
signal kicked(reason: String)
signal broadcast_received(message: String)
signal net_error(message: String)
signal disconnected(reason: String)

const CONNECT_TIMEOUT := 3.0
const LOGIN_TIMEOUT := 6.0

var conn: NetConn = null
var connecting := false
var connect_started := 0.0
var connected_ever := false
var await_login := false
var login_started := 0.0
var my_id := ""
var my_nickname := ""
var my_room_id := ""
var my_server := ""


func connect_to(host: String, port: int) -> void:
	disconnect_now()
	var p := StreamPeerTCP.new()
	var err := p.connect_to_host(host, port)
	if err != OK:
		connect_failed.emit("无法发起连接（错误码 %d）" % err)
		return
	conn = NetConn.new(p)
	connecting = true
	connected_ever = false
	connect_started = Time.get_unix_time_from_system()
	my_server = "%s:%d" % [host, port]


func _process(_delta: float) -> void:
	if conn == null:
		return
	var msgs := conn.poll_messages()
	if conn.closed:
		var was := connected_ever
		disconnect_now()
		if was:
			disconnected.emit("与服务器的连接已断开")
		elif connecting:
			connecting = false
			connect_failed.emit("无法连接到服务器，请检查地址与端口")
		return
	if connecting:
		if conn.is_open():
			connecting = false
			connected_ever = true
			await_login = true
			login_started = Time.get_unix_time_from_system()
			connected.emit()
		elif Time.get_unix_time_from_system() - connect_started > CONNECT_TIMEOUT:
			connecting = false
			disconnect_now()
			connect_failed.emit("连接超时，请确认服务端已启动")
			return
	# 已连接但迟迟收不到登录响应（可能连接的不是游戏服务端）
	if await_login and Time.get_unix_time_from_system() - login_started > LOGIN_TIMEOUT:
		await_login = false
		disconnect_now()
		connect_failed.emit("服务器未响应登录，请确认连接的是游戏服务端")
		return
	for m in msgs:
		_dispatch(m)


func _dispatch(msg: Dictionary) -> void:
	var type := str(msg.get("type", ""))
	var raw = msg.get("data", {})
	var d: Dictionary = raw if raw is Dictionary else {}
	match type:
		"login_ok":
			await_login = false
			my_id = str(d.get("player_id", ""))
			my_nickname = str(d.get("nickname", ""))
			login_ok.emit(my_id, my_nickname)
		"room_list":
			var rooms = d.get("rooms", [])
			room_list_received.emit(rooms if rooms is Array else [])
		"lobby":
			var rooms = d.get("rooms", [])
			my_room_id = ""
			room_list_received.emit(rooms if rooms is Array else [])
		"room_joined":
			var r = d.get("room", {})
			if r is Dictionary:
				my_room_id = str(r.get("id", ""))
				room_joined.emit(r)
		"room_update":
			var r = d.get("room", {})
			if r is Dictionary:
				room_update.emit(r)
		"room_closed":
			my_room_id = ""
			room_closed.emit(str(d.get("reason", "")))
		"watch_snapshot":
			var wr = d.get("room", {})
			if wr is Dictionary:
				watch_snapshot_received.emit(wr)
		"watch_ended":
			watch_ended.emit(str(d.get("reason", "")))
		"kicked":
			kicked.emit(str(d.get("reason", "")))
		"broadcast":
			broadcast_received.emit(str(d.get("message", "")))
		"error":
			net_error.emit(str(d.get("message", "未知错误")))


func send(type: String, data: Dictionary = {}) -> bool:
	if conn == null or conn.closed:
		return false
	return conn.send(type, data)


func logout() -> void:
	if conn != null and not conn.closed:
		conn.send("logout")
	disconnect_now()


func disconnect_now() -> void:
	if conn != null:
		conn.close()
	conn = null
	connecting = false
	connected_ever = false
	await_login = false
	my_id = ""
	my_nickname = ""
	my_room_id = ""
