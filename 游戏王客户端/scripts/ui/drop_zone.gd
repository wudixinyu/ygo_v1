class_name DropZone
extends Panel
## 通用拖放目标（召唤空位 / 对手怪兽格）—— 客户端专用
## 外部设置 accept_kinds（接受的拖拽数据 kind 列表，如 ["summon"]）与 on_drop 回调；
## _can_drop_data / _drop_data 由引擎在拖拽悬停 / 释放时调用。

var accept_kinds: Array = []
var on_drop: Callable = Callable()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or on_drop.is_null():
		return false
	return accept_kinds.has(str((data as Dictionary).get("kind", "")))


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if on_drop.is_valid():
		on_drop.call(data)
