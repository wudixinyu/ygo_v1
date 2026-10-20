class_name EnemyFieldView
extends Control
## 房间页「对手场地」横条（真人对战专用）—— 客户端专用
## 左侧：对手昵称 / LP / 手牌 · 卡组数量；中部：对手怪兽区 5 格；右侧：回合状态。
## 交互：
##  - 单击对手怪兽 = 查看卡片详情；双击的第二击忽略（不重复触发）
##  - 拖动我方怪兽到对手怪兽格 / 对手条任意位置 = 发起攻击（拖拽时格子红框高亮提示）
## 数据来自 room_update 推送的 room.players[] 中 id != ClientNet.my_id 的一项。

const CARD_BACK := preload("res://assets/card_back.png")

const SLOT_W := 86.0
const SLOT_H := 124.0
const SLOT_GAP := 12.0

signal attack_drop(attacker_id: int, target_id: int)   # 放置攻击（target_id=0 表示直接攻击玩家）
signal card_detail_requested(info: Dictionary)         # 单击对手怪兽：请求展示详情

var db: CardDB = null         # 客户端卡图库（main_ui 注入；null = 卡背占位）

var _name_label: Label
var _lp_bar: ProgressBar
var _lp_val: Label
var _info_label: Label
var _turn_label: Label
var _cells: Array = []        # 5 个格位（DropZone：接收攻击拖放）
var _slots: Array = []        # 5 个 TextureRect（卡图）
var _slot_panels: Array = []  # 5 个内部边框 Panel
var _spell_cells: Array = []  # 5 个魔陷格位（Panel：单击查看详情）
var _spell_slots: Array = []  # 5 个魔陷 TextureRect（卡图）
var _spell_frames: Array = [] # 5 个魔陷内部边框 Panel
var _targeting := false       # 拖拽攻击进行中（格子红框高亮）
var _skip_click := false      # 双击的第二击不重复触发单击
var _drag_ended_ms := 0       # 最近一次拖拽结束时间（防御：拖拽残留事件误触）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_build()


## 拖拽状态：拖动 attack 时格子红框高亮；结束时取消
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data = get_viewport().gui_get_drag_data()
		var kind := str((data as Dictionary).get("kind", "")) if data is Dictionary else ""
		set_targeting(kind == "attack")
	elif what == NOTIFICATION_DRAG_END:
		_drag_ended_ms = Time.get_ticks_msec()
		set_targeting(false)


func _build() -> void:
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.08, 0.85), UITheme.BORDER, 10))
	add_child(bg)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14
	row.offset_top = 10
	row.offset_bottom = -10
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	# ---- 左：对手信息 ----
	var lv := VBoxContainer.new()
	lv.custom_minimum_size = Vector2(232, 0)
	lv.add_theme_constant_override("separation", 4)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lv)

	lv.add_child(UITheme.text_label("对手场地", UITheme.TEXT_DIM, 11, true))
	_name_label = UITheme.text_label("等待对手加入…", UITheme.TEXT_DIM, 17)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lv.add_child(_name_label)

	var lp_row := HBoxContainer.new()
	lp_row.add_theme_constant_override("separation", 8)
	lp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(lp_row)
	lp_row.add_child(UITheme.text_label("LP", UITheme.TEXT_DIM, 11, true))
	_lp_bar = ProgressBar.new()
	_lp_bar.max_value = 8000
	_lp_bar.show_percentage = false
	_lp_bar.custom_minimum_size = Vector2(0, 13)
	_lp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lp_bar.add_theme_stylebox_override("background", UITheme.sb(Color("111122"), Color("111122"), 6, 0, 0))
	_lp_bar.add_theme_stylebox_override("fill", UITheme.sb(UITheme.GREEN, UITheme.GREEN, 6, 0, 0))
	lp_row.add_child(_lp_bar)
	_lp_val = UITheme.text_label("—", UITheme.TEXT, 13)
	_lp_val.custom_minimum_size = Vector2(46, 0)
	_lp_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lp_row.add_child(_lp_val)

	_info_label = UITheme.text_label("", UITheme.TEXT_DIM, 12, true)
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(_info_label)

	# ---- 中：对手怪兽区（5 格，接收攻击拖放）----
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(center)

	var slots_box := HBoxContainer.new()
	slots_box.add_theme_constant_override("separation", int(SLOT_GAP))
	slots_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(slots_box)

	for i in 5:
		var cell := DropZone.new()
		cell.custom_minimum_size = Vector2(SLOT_W, SLOT_H)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.accept_kinds = ["attack"]
		cell.add_theme_stylebox_override("panel", StyleBoxEmpty.new())   # 透明（边框由内部 frame 绘制）
		cell.set_meta("cid", 0)
		cell.set_meta("info", {})
		cell.on_drop = func(data: Dictionary) -> void:
			attack_drop.emit(int(data.get("card_id", 0)), int(cell.get_meta("cid", 0)))
		cell.gui_input.connect(_on_slot_input.bind(i))
		slots_box.add_child(cell)

		var frame := Panel.new()
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_theme_stylebox_override("panel", _frame_style(false, false))
		cell.add_child(frame)

		var tex := TextureRect.new()
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.visible = false
		cell.add_child(tex)

		_cells.append(cell)
		_slots.append(tex)
		_slot_panels.append(frame)

	# ---- 中右：对手魔陷区（5 小格，放置后展示；单击查看详情）----
	var spells_box := HBoxContainer.new()
	spells_box.add_theme_constant_override("separation", 8)
	spells_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spells_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(spells_box)

	for i in 5:
		var sp := Panel.new()
		sp.custom_minimum_size = Vector2(52, 76)
		sp.mouse_filter = Control.MOUSE_FILTER_STOP
		sp.add_theme_stylebox_override("panel", _frame_style(false, false))
		sp.set_meta("info", {})
		sp.gui_input.connect(_on_spell_input.bind(i))
		sp.tooltip_text = "对手魔法 / 陷阱卡"
		spells_box.add_child(sp)

		var stex := TextureRect.new()
		stex.set_anchors_preset(Control.PRESET_FULL_RECT)
		stex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		stex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stex.visible = false
		sp.add_child(stex)

		_spell_cells.append(sp)
		_spell_slots.append(stex)

	# ---- 右：回合状态 ----
	_turn_label = UITheme.text_label("", UITheme.TEXT_DIM, 13)
	_turn_label.custom_minimum_size = Vector2(128, 0)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_turn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_turn_label)


## 整条对手区域可接收攻击拖放（落在格子外 = 直接攻击；target=0 由 main_ui 校验）
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	return str((data as Dictionary).get("kind", "")) == "attack"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary:
		attack_drop.emit(int((data as Dictionary).get("card_id", 0)), 0)


# ================= 数据刷新 =================

## 刷新对手场地（enemy = 对手玩家数据，无对手时为 {}；room = 房间整体数据）
func update_view(enemy: Dictionary, room: Dictionary) -> void:
	if enemy.is_empty():
		# 房间已结束（对手中途离开）→ 提示已结束；否则等待对手加入
		var st := str(room.get("state", "waiting"))
		if st == "finished":
			_name_label.text = "对手已离开"
			_turn_label.text = "决斗已结束"
			_turn_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		else:
			_name_label.text = "等待对手加入…"
			_turn_label.text = ""
		_name_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		_lp_bar.value = 0
		_lp_val.text = "—"
		_info_label.text = ""
		_clear_slots()
		return

	_name_label.text = str(enemy.get("nickname", "对手"))
	_name_label.add_theme_color_override("font_color", UITheme.TEXT)

	var lp := int(enemy.get("lp", 8000))
	var ratio := lp / 8000.0
	var col: Color = UITheme.GREEN if ratio > 0.5 else (UITheme.YELLOW if ratio > 0.25 else UITheme.RED)
	_lp_bar.value = clampi(lp, 0, 8000)
	_lp_bar.add_theme_stylebox_override("fill", UITheme.sb(col, col, 6, 0, 0))
	_lp_val.text = str(lp)

	_info_label.text = "手牌 %d · 卡组 %d" % [int(enemy.get("hand", 0)), int(enemy.get("deck_count", 0))]

	# 回合状态
	var state := str(room.get("state", "waiting"))
	var active := str(room.get("active_pid", ""))
	if state == "dueling":
		if active == str(enemy.get("id", "")):
			_turn_label.text = "● 对手回合中"
			_turn_label.add_theme_color_override("font_color", UITheme.GOLD)
		else:
			_turn_label.text = "轮到你操作"
			_turn_label.add_theme_color_override("font_color", UITheme.GREEN)
	elif state == "finished":
		_turn_label.text = "决斗已结束"
		_turn_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	else:
		_turn_label.text = "等待双方准备"
		_turn_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)

	# 怪兽格：真实卡图（数组含空位 {}；格位保留，空位可接收直接攻击拖放）
	var fc = enemy.get("field_cards", [])
	var flist: Array = fc if fc is Array else []
	for i in _cells.size():
		var cell: DropZone = _cells[i]
		var tex: TextureRect = _slots[i]
		var info: Dictionary = flist[i] if (i < flist.size() and flist[i] is Dictionary) else {}
		if not info.is_empty():
			var t := _tex_of(info)
			tex.texture = t if t != null else CARD_BACK
			tex.visible = true
			cell.set_meta("cid", int(info.get("id", 0)))
			cell.set_meta("info", info)
		else:
			tex.visible = false
			cell.set_meta("cid", 0)
			cell.set_meta("info", {})

	# 魔陷格：真实卡图（放置后展示；单击查看详情）
	var sc = enemy.get("spell_cards", [])
	var slist: Array = sc if sc is Array else []
	for i in _spell_cells.size():
		var sp: Panel = _spell_cells[i]
		var stex: TextureRect = _spell_slots[i]
		var sinfo: Dictionary = slist[i] if (i < slist.size() and slist[i] is Dictionary) else {}
		if not sinfo.is_empty():
			var st := _tex_of(sinfo)
			stex.texture = st if st != null else CARD_BACK
			stex.visible = true
			sp.set_meta("info", sinfo)
		else:
			stex.visible = false
			sp.set_meta("info", {})
	_refresh_frames()


## 设置「攻击拖拽中」高亮（对手怪兽格显示红框提示可放置）
func set_targeting(on: bool) -> void:
	if _targeting == on:
		return
	_targeting = on
	_refresh_frames()


# ================= 交互 =================

## 对手怪兽格单击 = 查看详情（双击的第二击忽略，不重复触发）
func _on_slot_input(event: InputEvent, idx: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_skip_click = mb.double_click
		return
	if _skip_click:
		_skip_click = false
		return
	if Time.get_ticks_msec() - _drag_ended_ms < 150:
		return   # 刚结束拖拽（防御：拖放残留事件不触发详情）
	var info: Dictionary = _cells[idx].get_meta("info", {})
	if not info.is_empty():
		card_detail_requested.emit(info)


## 对手魔陷格单击 = 查看详情
func _on_spell_input(event: InputEvent, idx: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var info: Dictionary = _spell_cells[idx].get_meta("info", {})
	if not info.is_empty():
		card_detail_requested.emit(info)


# ================= 自测辅助（--duel-ui-demo） =================
# 说明：引擎拖拽启动依赖真实鼠标输入（合成事件无法触发），自测按「业务等价」路径直接调用
# 拖放三件套：按目标命中格位后走 _can_drop_data / _drop_data。

## 自测：模拟「拖怪兽到对手条」放置（target_id = 对手怪兽 id；0 = 直接攻击，取第一个空格）
func demo_drop_attack(data: Variant, target_id: int) -> bool:
	if not (data is Dictionary):
		return false
	var target_cell: DropZone = null
	for cell in _cells:
		if target_id > 0 and int(cell.get_meta("cid", 0)) == target_id:
			target_cell = cell
			break
		if target_id <= 0 and int(cell.get_meta("cid", 0)) == 0:
			target_cell = cell
			break
	var receiver: Control = target_cell if target_cell != null else self
	if receiver.call("_can_drop_data", Vector2.ZERO, data):
		receiver.call("_drop_data", Vector2.ZERO, data)
		return true
	return false


# ================= 内部 =================

func _clear_slots() -> void:
	for i in _cells.size():
		var cell: DropZone = _cells[i]
		_slots[i].visible = false
		cell.set_meta("cid", 0)
		cell.set_meta("info", {})
	for i in _spell_cells.size():
		_spell_slots[i].visible = false
		(_spell_cells[i] as Panel).set_meta("info", {})
	_refresh_frames()


func _refresh_frames() -> void:
	for i in _cells.size():
		var has_card := int(_cells[i].get_meta("cid", 0)) > 0
		_slot_panels[i].add_theme_stylebox_override("panel", _frame_style(has_card, _targeting))


func _frame_style(has_card: bool, targeting: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if has_card:
		s.bg_color = Color(0.06, 0.06, 0.13, 0.6)
		s.border_color = UITheme.RED if targeting else Color(0.62, 0.64, 0.78, 0.6)
		s.set_border_width_all(2 if targeting else 1)
	else:
		s.bg_color = Color(0.05, 0.05, 0.1, 0.35)
		s.border_color = Color(0.35, 0.36, 0.5, 0.22)
		s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	return s


func _box(bg: Color, border: Color, radius: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(int(radius))
	return s


## 卡片信息 → 纹理（需要外部注入的 CardDB）
func _tex_of(info: Dictionary) -> Texture2D:
	if db == null or info.is_empty():
		return null
	return db.texture_of(int(info.get("id", 0)))
