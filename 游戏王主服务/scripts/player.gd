class_name Player
extends RefCounted

## 服务端上的一个玩家（来自真实客户端连接）

var id := ""
var nickname := ""
var ip := ""
var conn: NetConn = null
var room_id := ""
var watch_room_id := ""     # 观战中的房间 id（观战者不占用房间席位）
var login_at := 0.0


func is_logged() -> bool:
	return nickname != ""


func is_online() -> bool:
	return conn != null and not conn.closed
