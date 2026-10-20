class_name FrameReader
extends RefCounted

## 按帧解析 TCP 字节流：先读 4 字节长度，再读完整 JSON 体

var _buf := PackedByteArray()


## 追加收到的新数据
func push(data: PackedByteArray) -> void:
	_buf.append_array(data)


## 取出所有已收齐的完整消息
func read_all() -> Array:
	var frames := []
	while true:
		if _buf.size() < 4:
			break
		var n := _buf.decode_u32(0)
		if n == 0 or n > Protocol.MAX_FRAME_SIZE:
			# 协议数据异常，放弃当前缓冲
			_buf.clear()
			break
		if _buf.size() < 4 + n:
			break
		var body := _buf.slice(4, 4 + n)
		_buf = _buf.slice(4 + n)
		var json := JSON.new()
		var err := json.parse(body.get_string_from_utf8())
		if err == OK and json.data is Dictionary:
			frames.append(json.data)
	return frames
