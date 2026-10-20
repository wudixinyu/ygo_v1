class_name Protocol
extends RefCounted

## 游戏王联机协议工具（三个项目共用，保持完全一致）
## 帧格式：[4 字节大端长度][UTF-8 JSON 消息体]
## 消息格式：{"type": "消息类型", "data": {...}, "ts": 毫秒时间戳}

const HEADER_SIZE := 4
const MAX_FRAME_SIZE := 1048576  # 单帧上限 1MB


## 将消息字典编码为一帧字节流
static func encode(msg: Dictionary) -> PackedByteArray:
	if not msg.has("ts"):
		msg["ts"] = int(Time.get_unix_time_from_system() * 1000.0)
	var body := JSON.stringify(msg).to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(HEADER_SIZE)
	out.encode_u32(0, body.size())
	out.append_array(body)
	return out


## 构造消息字典
static func make(type: String, data: Dictionary = {}) -> Dictionary:
	return {"type": type, "data": data}
