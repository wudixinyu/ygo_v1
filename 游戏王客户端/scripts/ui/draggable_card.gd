class_name DraggableCard
extends TextureRect
## 可拖拽卡片（手牌 / 我方场上怪兽）—— 客户端专用
## 按住拖动 → 引擎调用 _get_drag_data 发起拖拽（预览跟随鼠标）；
## 纯点击（无拖动）→ 触发 on_click 回调（查看卡片详情）。
## 外部设置 card_data（拖拽数据）与 on_click（单击回调）；card_data 为空时不可拖。

var card_data: Dictionary = {}            # {"kind": "summon"/"attack", ...}；空字典 = 不可拖
var on_click: Callable = Callable()       # 单击（非拖拽）回调
var on_drag_start: Callable = Callable()  # 拖拽开始回调（可选）

var _skip_click := false                  # 双击的第二击不重复触发单击
var _drag_ended_ms := 0                   # 最近一次拖拽结束时间（防御：拖拽残留事件误触详情）


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drag_ended_ms = Time.get_ticks_msec()


## 拖动开始时由引擎调用：返回拖拽数据（含跟随鼠标的预览卡图）
func _get_drag_data(_at_position: Vector2) -> Variant:
	if card_data.is_empty():
		return null
	var preview := TextureRect.new()
	preview.texture = texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size = size
	preview.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(preview)
	if on_drag_start.is_valid():
		on_drag_start.call()
	return card_data


func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		# 双击的第二击不重复触发单击（第一击已显示详情）
		_skip_click = mb.double_click
		return
	# 释放：单击（非拖动）→ 触发查看详情
	if _skip_click:
		_skip_click = false
		return
	if Time.get_ticks_msec() - _drag_ended_ms < 150:
		return
	if on_click.is_valid():
		on_click.call()
