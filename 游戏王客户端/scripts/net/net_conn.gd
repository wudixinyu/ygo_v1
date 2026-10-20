class_name NetConn
extends RefCounted

## 封装一条 TCP 连接的收发与帧解析

var peer: StreamPeerTCP
var reader := FrameReader.new()
var closed := false
var close_reason := ""


func _init(p: StreamPeerTCP) -> void:
	peer = p


## 轮询连接，返回所有完整消息；连接断开时 closed 置为 true
func poll_messages() -> Array:
	var out := []
	if closed:
		return out
	if peer == null:
		closed = true
		close_reason = "连接为空"
		return out
	peer.poll()
	var st := peer.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTING:
		return out
	if st != StreamPeerTCP.STATUS_CONNECTED:
		closed = true
		close_reason = "连接已断开"
		return out
	var avail := peer.get_available_bytes()
	if avail > 0:
		var res := peer.get_partial_data(avail)
		if res[0] == OK:
			reader.push(res[1])
	return reader.read_all()


## 发送一条消息
func send(type: String, data: Dictionary = {}) -> bool:
	if closed or peer == null:
		return false
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var err := peer.put_data(Protocol.encode(Protocol.make(type, data)))
	if err != OK:
		closed = true
		close_reason = "发送失败"
		return false
	return true


func close() -> void:
	closed = true
	if peer != null:
		peer.disconnect_from_host()


## 连接是否畅通（注意：不能用 is_connected 命名，会与 Object 基类冲突）
func is_open() -> bool:
	return not closed and peer != null and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED
