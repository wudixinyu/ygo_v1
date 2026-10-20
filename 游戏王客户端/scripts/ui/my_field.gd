class_name MyFieldView
extends Control
## 房间页「我方场地」视图（1280x720 设计稿，等比缩放居中）—— 客户端专用
## 布局：怪兽区 + 魔陷区（魔法/陷阱可拖放放置）、卡组/墓地/额外卡组圆区、
## 底部手牌区（横向滚动，可查看全部手牌）、左侧卡片详情预览（单击显示）、
## 我方信息面板（昵称/LP/准备状态）、右下角对战操作面板（回合指示 + 提示 + 结束回合）。
## 真人对战交互：
##  - 单击任意卡 = 查看详情（左侧放大显示，再点同一张收起）
##  - 拖动我方手牌怪兽 → 怪兽区空位 = 召唤（拖到哪格就召唤到哪格；拖拽时空位绿框高亮）
##  - 拖动我方手牌魔法/陷阱 → 魔陷区空位 = 放置（每回合 1 次；拖拽时空位绿框高亮）
##  - 拖动我方场上怪兽 → 拖向对手条 = 攻击（由 enemy_panel 接收放置）
## 数据来自 room_update 推送的 room.players[] 中 id == ClientNet.my_id 的一项；
## 未注入卡库或卡图缺失时自动回退卡背占位。

const BG_TEX := preload("res://assets/field_bg.jpg")    # 对战中的决斗场地背景
const WAIT_TEX := preload("res://assets/wait_bg.jpg")   # 等待阶段的青眼白龙背景
const CARD_BACK := preload("res://assets/card_back.png")

const DESIGN := Vector2(1280, 720)
const ZONE_W := 100.0
const ZONE_H := 145.0
const COLS := [362.0, 476.0, 590.0, 704.0, 818.0]   # 5 列左边缘
const ROW_FIELD := 210.0     # 我方怪兽区
const ROW_MAGIC := 388.0     # 我方魔陷区（两端灵摆）
const CIRCLE_D := 110.0
const CARD_BIG := Vector2(78, 114)
const HAND_SHOW_MAX := 5     # 手牌无卡牌数据时的兜底占位张数
const HAND_CARD := Vector2(90, 130)      # 底部手牌区卡牌尺寸（放大显示）
const HAND_GAP := 10.0                   # 手牌间距
const PREVIEW_CARD := Vector2(200, 290)  # 卡片详情放大尺寸（卡图原生尺寸）
const WHEEL_STEP := 92.0                 # 手牌滚轮每格滚动像素

# 右侧圆区中心：额外卡组 / 墓地 / 卡组
const C_EXTRA := Vector2(1080, 150)
const C_GRAVE := Vector2(1080, 340)
const C_DECK := Vector2(1080, 530)

# 区域配色（与观战页一致）
const COL_ZONE := Color(0.62, 0.64, 0.78, 0.5)        # 普通区
const COL_PEND := Color(0.42, 0.82, 0.76, 0.65)       # 灵摆区
const COL_DECK := Color(0.85, 0.68, 0.32, 0.85)       # 卡组
const COL_GRAVE := Color(0.72, 0.45, 0.85, 0.85)      # 墓地
const COL_EXTRA := Color(0.45, 0.62, 0.92, 0.85)      # 额外卡组
const COL_ZONE_HOT := Color(0.42, 0.85, 0.55, 0.9)    # 空位可放置高亮（绿）

signal summon_drop(card_id: int, hand_index: int, pos: int)  # 拖手牌怪兽到怪兽区空位：请求召唤（pos = 目标格 0-4）
signal circle_clicked(kind: String)                          # 点击右侧圆区：请求查看列表（kind = "deck" / "grave" / "extra"）
signal end_turn_requested()                                  # 点击「结束回合」按钮：请求结束我的回合

var db: CardDB = null         # 客户端卡图库（main_ui 注入；null = 仅卡背占位）

var stage: Control
var bg_rect: TextureRect   # 场地背景（等待=青眼白龙 / 对战=决斗场地，经 set_dueling 切换）
var turn_title: Label
var turn_sub: Label
var action_panel: Panel       # 右下角对战操作面板（提示 + 结束回合，常驻）
var action_tip: Label
var end_turn_btn: Button
var field_slots: Array = []   # 我方怪兽区卡牌（5 个 DraggableCard，默认隐藏）
var slot_zones: Array = []    # 我方怪兽区空位（5 个 DropZone：接收手牌拖放召唤）
var spell_slots: Array = []   # 我方魔陷区卡牌（5 个 DraggableCard，放置后展示，单击详情）
var spell_zones: Array = []   # 我方魔陷区空位（5 个 DropZone：接收手牌拖放放置）
var grave_card: TextureRect
var deck_label: Label
var circle_zones := {}        # kind -> Panel（额外卡组/墓地/卡组的圆区面板，供自测合成点击）
var refs: Dictionary          # 我方面板（昵称/LP/准备）引用
var hand_scroll: ScrollContainer     # 底部手牌滚动容器（横向滚动查看全部手牌）
var hand_box: HBoxContainer          # 手牌行（DraggableCard）
var hand_label: Label                # 底部手牌数量标签
var preview_panel: Panel             # 左侧卡片详情预览
var preview_card: TextureRect
var preview_name: Label
var preview_stats: Label
var _detail_card: Control = null     # 当前正在展示详情的卡牌节点（单击选中）
var _external_preview := false       # 当前详情是否为外部卡片（对手卡）临时展示
var _my_turn := false                # 是否轮到我操作（决定卡片能否拖动）
var _attacked_ids: Array = []        # 本回合已攻击过的我方怪兽卡 id（转 int）
var _drag_kind := ""                 # 当前拖拽类型（"summon"/"attack"/""）
var _drag_card_kind := ""            # 当前拖拽手牌的卡类型（"monster"/"spell"/"trap"，决定高亮目标区）
var _last_hand_n := -1               # 上一帧手牌张数（变化时自动滚动到最新）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_build_stage()
	_build_zones()
	_build_hud()
	resized.connect(_update_stage)
	_update_stage.call_deferred()


## 设计稿等比缩放并居中（保证 1280x720 布局在任何容器尺寸下不变形）
func _update_stage() -> void:
	var s: float = min(size.x / DESIGN.x, size.y / DESIGN.y)
	if s <= 0.0:
		return
	stage.scale = Vector2(s, s)
	stage.position = (size - DESIGN * s) / 2.0


## 背景切换：等待阶段显示青眼白龙，开战后切换为决斗场地（由 main_ui 按房间状态调用）
func set_dueling(on: bool) -> void:
	if bg_rect == null or bg_rect.texture == (BG_TEX if on else WAIT_TEX):
		return
	bg_rect.texture = BG_TEX if on else WAIT_TEX


## 拖拽状态通知：拖动开始时高亮可放置空位（拖怪兽 → 怪兽区绿框；拖魔法/陷阱 → 魔陷区绿框）
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data = get_viewport().gui_get_drag_data()
		if data is Dictionary:
			_drag_kind = str(data.get("kind", ""))
			var cid := int(data.get("card_id", 0))
			_drag_card_kind = str(db.get_card(cid).get("kind", "")) if (db != null and cid > 0) else ""
		else:
			_drag_kind = ""
			_drag_card_kind = ""
		_refresh_zone_highlight()
	elif what == NOTIFICATION_DRAG_END:
		_drag_kind = ""
		_drag_card_kind = ""
		_refresh_zone_highlight()


# ================= 场景构建 =================

func _build_stage() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.02, 0.04)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	# 背景：挂在根节点（容器尺寸）按 cover 等比铺满——场地区容器比 16:9 宽，
	# 若放進 1280x720 stage 会被二次放大裁切（素材已按 2.25:1 预裁，cover 后基本无裁切）
	bg_rect = TextureRect.new()
	bg_rect.texture = WAIT_TEX
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_rect)

	stage = Control.new()
	stage.position = Vector2.ZERO
	stage.size = DESIGN
	stage.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(stage)


func _build_zones() -> void:
	# 我方怪兽区（贴近中央）：空位 = 拖放目标（接收手牌拖放召唤）
	for i in 5:
		var dz := DropZone.new()
		dz.position = Vector2(COLS[i], ROW_FIELD)
		dz.size = Vector2(ZONE_W, ZONE_H)
		dz.mouse_filter = Control.MOUSE_FILTER_STOP
		dz.accept_kinds = ["summon"]
		var slot_i := i
		dz.on_drop = func(data: Dictionary) -> void:
			summon_drop.emit(int(data.get("card_id", 0)), int(data.get("hand_index", -1)), slot_i)
		dz.add_theme_stylebox_override("panel", _zone_style(Color(0.04, 0.04, 0.1, 0.42), COL_ZONE))
		stage.add_child(dz)
		slot_zones.append(dz)
	field_slots = _field_slots_for(ROW_FIELD)
	# 我方魔陷区（最外行，两端灵摆区）：空位 = 拖放目标（接收手牌魔法/陷阱卡放置）
	for i in 5:
		var border: Color = COL_PEND if i == 0 or i == 4 else COL_ZONE
		var sz := DropZone.new()
		sz.position = Vector2(COLS[i], ROW_MAGIC)
		sz.size = Vector2(ZONE_W, ZONE_H)
		sz.mouse_filter = Control.MOUSE_FILTER_STOP
		sz.accept_kinds = ["summon"]
		var spell_i := i
		sz.on_drop = func(data: Dictionary) -> void:
			summon_drop.emit(int(data.get("card_id", 0)), int(data.get("hand_index", -1)), spell_i)
		sz.add_theme_stylebox_override("panel", _zone_style(Color(0.04, 0.04, 0.1, 0.42), border))
		stage.add_child(sz)
		spell_zones.append(sz)
		if i == 0 or i == 4:
			# 灵摆区标签（保留原有提示，叠在空位上）
			var l := UITheme.text_label("灵摆", Color(1, 1, 1, 0.45), 10)
			l.position = Vector2(COLS[i], ROW_MAGIC + ZONE_H - 17)
			l.size = Vector2(ZONE_W, 14)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stage.add_child(l)
	spell_slots = _spell_slots_for(ROW_MAGIC)

	# 行标签（卡区左侧）
	_side_caption("我方怪兽区", ROW_FIELD)
	_side_caption("我方魔陷区", ROW_MAGIC)

	# 右侧圆区：额外卡组 / 墓地 / 卡组（三者均可点击 → 弹出对应列表）
	_circle_zone(C_EXTRA, COL_EXTRA, "额外卡组", true, "extra")
	grave_card = _circle_zone(C_GRAVE, COL_GRAVE, "墓地", false, "grave")
	_circle_zone(C_DECK, COL_DECK, "卡组", true, "deck")
	deck_label = _deck_count_label(Vector2(1150, 522))


## 一行 5 个怪兽区卡牌（默认隐藏，update_view 时填真实卡图；可拖出攻击）
func _field_slots_for(row_y: float) -> Array:
	var out: Array = []
	for i in 5:
		var t := DraggableCard.new()
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.position = Vector2(COLS[i], row_y)
		t.size = Vector2(ZONE_W, ZONE_H)
		t.visible = false
		stage.add_child(t)
		out.append(t)
	return out


## 一行 5 个魔陷区卡牌（默认隐藏，update_view 时填真实卡图；仅展示 + 单击详情，不可拖出）
func _spell_slots_for(row_y: float) -> Array:
	var out: Array = []
	for i in 5:
		var t := DraggableCard.new()
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.position = Vector2(COLS[i], row_y)
		t.size = Vector2(ZONE_W, ZONE_H)
		t.visible = false
		t.tooltip_text = "单击查看详情"
		stage.add_child(t)
		out.append(t)
	return out


## 卡组剩余数量标签（圆区右侧）
func _deck_count_label(pos: Vector2) -> Label:
	var l := UITheme.text_label("", Color(1, 1, 1, 0.65), 12)
	l.position = pos
	l.size = Vector2(120, 20)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(l)
	return l


func _tile_zone(x: float, y: float, caption := "", border := COL_ZONE) -> void:
	var p := Panel.new()
	p.position = Vector2(x, y)
	p.size = Vector2(ZONE_W, ZONE_H)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _zone_style(Color(0.04, 0.04, 0.1, 0.42), border))
	stage.add_child(p)
	if caption != "":
		var l := UITheme.text_label(caption, Color(1, 1, 1, 0.45), 10)
		l.position = Vector2(x, y + ZONE_H - 17)
		l.size = Vector2(ZONE_W, 14)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(l)


func _circle_zone(center: Vector2, border: Color, caption: String, deck_stack: bool, kind := "") -> TextureRect:
	var p := Panel.new()
	p.position = center - Vector2(CIRCLE_D, CIRCLE_D) / 2.0
	p.size = Vector2(CIRCLE_D, CIRCLE_D)
	p.add_theme_stylebox_override("panel", _zone_style(Color(0.05, 0.05, 0.12, 0.55), border, CIRCLE_D / 2.0))
	if kind != "":
		# 圆区可点击：请求查看对应列表（卡组 / 墓地 / 额外卡组）
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.tooltip_text = "点击查看%s列表" % caption
		p.gui_input.connect(_on_circle_zone_input.bind(kind))
		circle_zones[kind] = p
	stage.add_child(p)

	var card: TextureRect = null
	if deck_stack:
		# 卡组：叠放两张卡背占位
		_card_rect(center - CARD_BIG / 2.0 + Vector2(5, 6), CARD_BIG)
		card = _card_rect(center - CARD_BIG / 2.0, CARD_BIG)
	elif caption == "墓地":
		# 墓地：显示墓地最上一张卡（无数据时隐藏）；点击由圆区面板接收（查看墓地列表）
		card = _card_rect(center - CARD_BIG / 2.0, CARD_BIG)
		card.visible = false
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.text_label(caption, Color(1, 1, 1, 0.6), 11)
	l.position = center + Vector2(-80, CIRCLE_D / 2.0 + 4)
	l.size = Vector2(160, 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(l)
	return card


## 圆区单击：请求查看对应列表（main_ui 弹窗：deck = 卡组 / grave = 墓地 / extra = 额外卡组）
func _on_circle_zone_input(event: InputEvent, kind: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.double_click:
			circle_clicked.emit(kind)


## 自测（--list-demo）：合成一次单击 —— 点击对应圆区中心（走真实输入链路 → circle_clicked → 列表弹窗）
func demo_click_circle(kind: String) -> bool:
	var p: Control = circle_zones.get(kind)
	if p == null or not is_instance_valid(p):
		return false
	var c := p.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = c
	get_viewport().push_input(press, true)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = c
	get_viewport().push_input(rel, true)
	return true


func _zone_style(bg: Color, border: Color, radius := 9.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(int(radius))
	return s


func _card_rect(pos: Vector2, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	# 先设 expand 再设 size，否则纹理会以原始尺寸钳制最小大小
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture = CARD_BACK
	t.position = pos
	t.size = size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(t)
	return t


func _side_caption(text: String, row_y: float) -> void:
	var l := UITheme.text_label(text, Color(1, 1, 1, 0.35), 11)
	l.position = Vector2(196, row_y + ZONE_H / 2.0 - 9)
	l.size = Vector2(150, 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(l)


# ================= HUD 构建 =================

func _build_hud() -> void:
	refs = _make_player_panel(Vector2(24, 560))
	_build_hand_area()
	_build_preview()
	_build_action_panel()


## 我方信息面板（左下角）：角色 / 准备状态 / 昵称 / LP
func _make_player_panel(pos: Vector2) -> Dictionary:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.size = Vector2(300, 112)
	panel.add_theme_stylebox_override("panel", UITheme.sb(Color(0.04, 0.04, 0.09, 0.72), UITheme.BORDER, 10, 1, 10))
	stage.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	panel.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	var role_l := UITheme.text_label("我方", UITheme.TEXT_DIM, 12, true)
	top.add_child(role_l)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var ready_l := UITheme.text_label("", UITheme.TEXT_DIM, 12, true)
	top.add_child(ready_l)

	var name_l := UITheme.text_label("空位", UITheme.TEXT_DIM, 17)
	v.add_child(name_l)

	var lp_row := HBoxContainer.new()
	lp_row.add_theme_constant_override("separation", 8)
	v.add_child(lp_row)
	lp_row.add_child(UITheme.text_label("LP", UITheme.TEXT_DIM, 11, true))
	var bar := ProgressBar.new()
	bar.max_value = 8000
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 13)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UITheme.sb(Color("111122"), Color("111122"), 6, 0, 0))
	bar.add_theme_stylebox_override("fill", UITheme.sb(UITheme.GREEN, UITheme.GREEN, 6, 0, 0))
	lp_row.add_child(bar)
	var lp_val := UITheme.text_label("—", UITheme.TEXT, 13)
	lp_val.custom_minimum_size = Vector2(46, 0)
	lp_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lp_row.add_child(lp_val)

	return {
		"panel": panel,
		"role": role_l,
		"ready": ready_l,
		"name": name_l,
		"lp_bar": bar,
		"lp_val": lp_val,
	}


## 底部手牌区：横向滚动容器（任意张数，滚轮左右滚动查看全部手牌）+ 数量标签
func _build_hand_area() -> void:
	# 半透明底板，让手牌在场地背景上更醒目
	var bg := Panel.new()
	bg.position = Vector2(371, 528)
	bg.size = Vector2(538, 168)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", _zone_style(Color(0.03, 0.03, 0.08, 0.45), Color(0.3, 0.3, 0.45, 0.35), 10))
	stage.add_child(bg)

	hand_label = UITheme.text_label("手牌 · 0 张", Color(1, 1, 1, 0.55), 12)
	hand_label.position = Vector2(490, 533)
	hand_label.size = Vector2(300, 18)
	hand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hand_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(hand_label)

	# 横向滚动容器（滚动条隐藏；滚轮 / 触控板左右查看，召唤等操作后自动滚到最新）
	hand_scroll = ScrollContainer.new()
	hand_scroll.position = Vector2(374, 554)
	hand_scroll.size = Vector2(532, 138)
	hand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_scroll.gui_input.connect(_on_hand_scroll_input)
	stage.add_child(hand_scroll)

	# 居中容器：手牌不足一屏时居中；超出一屏时可左右滚动
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_scroll.add_child(center)

	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", int(HAND_GAP))
	hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 不挡卡片自身的拖拽 / 点击
	center.add_child(hand_box)


## 手牌区滚轮 → 横向滚动（查看全部手牌）
func _on_hand_scroll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			hand_scroll.scroll_horizontal -= int(WHEEL_STEP)
			hand_scroll.accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			hand_scroll.scroll_horizontal += int(WHEEL_STEP)
			hand_scroll.accept_event()


## 滚动到最新（新抽到的手牌在行尾）
func _scroll_hand_to_end() -> void:
	if hand_scroll != null:
		hand_scroll.scroll_horizontal = 1000000


## 左侧卡片详情预览（绿色区域）：单击任意卡牌放大显示卡图 + 名称 + ATK/DEF（再点同一张收起）
func _build_preview() -> void:
	preview_panel = Panel.new()
	preview_panel.position = Vector2(12, 80)
	preview_panel.size = Vector2(232, 380)
	preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.add_theme_stylebox_override("panel", _zone_style(Color(0.03, 0.03, 0.08, 0.82), UITheme.BORDER, 12))
	preview_panel.visible = false
	stage.add_child(preview_panel)

	preview_card = TextureRect.new()
	preview_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_card.position = Vector2(16, 14)
	preview_card.size = PREVIEW_CARD
	preview_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.add_child(preview_card)

	preview_name = UITheme.text_label("", UITheme.TEXT, 15)
	preview_name.position = Vector2(12, 312)
	preview_name.size = Vector2(208, 22)
	preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.add_child(preview_name)

	preview_stats = UITheme.text_label("", UITheme.TEXT_DIM, 12, true)
	preview_stats.position = Vector2(12, 336)
	preview_stats.size = Vector2(208, 18)
	preview_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.add_child(preview_stats)

	# 操作提示（常驻在预览面板下方）
	var hint := UITheme.text_label("单击卡牌查看详情", Color(1, 1, 1, 0.4), 11)
	hint.position = Vector2(12, 466)
	hint.size = Vector2(232, 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(hint)


## 右下角对战操作面板（常驻）：回合指示 + 操作提示 + 「结束回合」
## （回合牌自场地中央并入此处；等待 / 对战 / 结束全程显示）
func _build_action_panel() -> void:
	action_panel = Panel.new()
	action_panel.position = Vector2(948, 582)
	action_panel.size = Vector2(320, 132)
	action_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	action_panel.tooltip_text = "对战操作"
	action_panel.add_theme_stylebox_override("panel", _zone_style(Color(0.03, 0.03, 0.08, 0.78), UITheme.GOLD, 12))
	stage.add_child(action_panel)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_top = 8
	v.offset_right = -10
	v.offset_bottom = -8
	v.add_theme_constant_override("separation", 5)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	action_panel.add_child(v)

	# 回合指示行（原场地中央回合牌并入此处，不再遮挡卡区视野）
	var turn_row := HBoxContainer.new()
	turn_row.add_theme_constant_override("separation", 8)
	turn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(turn_row)
	turn_title = UITheme.text_label("等待开始", UITheme.GOLD, 14)
	turn_row.add_child(turn_title)
	var tsp := Control.new()
	tsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_row.add_child(tsp)
	turn_sub = UITheme.text_label("—", UITheme.TEXT, 11, true)
	turn_row.add_child(turn_sub)

	action_tip = UITheme.text_label("等待双方准备后开始决斗", UITheme.TEXT_DIM, 11, true)
	action_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_tip.custom_minimum_size = Vector2(0, 30)
	action_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(action_tip)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)

	end_turn_btn = Button.new()
	end_turn_btn.text = "结束回合"
	end_turn_btn.tooltip_text = "结束我的回合，轮到对方操作"
	end_turn_btn.custom_minimum_size = Vector2(0, 42)
	end_turn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_turn_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.style_button(end_turn_btn, true)
	end_turn_btn.pressed.connect(func() -> void: end_turn_requested.emit())
	h.add_child(end_turn_btn)


## 刷新右下角对战操作面板（main_ui 在房间刷新 / 本方操作后调用）
## d = {state, my_turn, summon_used, attacked(int 数组)}
func update_duel_actions(d: Dictionary) -> void:
	if action_panel == null or end_turn_btn == null:
		return
	var state := str(d.get("state", "waiting"))
	var my_turn := bool(d.get("my_turn", false))
	if state == "dueling":
		var attacked: Array = d.get("attacked", [])
		var spell_used := bool(d.get("spell_used", false))
		if not my_turn:
			action_tip.text = "对方回合操作中，请等待…"
			action_tip.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		elif not bool(d.get("summon_used", false)):
			action_tip.text = "你的回合：拖手牌召唤怪兽 / 放置魔法陷阱 · 拖怪兽攻击"
			action_tip.add_theme_color_override("font_color", UITheme.GOLD)
		elif _has_attacker_local(attacked) and not spell_used:
			action_tip.text = "你的回合：可攻击 / 放置魔法陷阱，或结束回合"
			action_tip.add_theme_color_override("font_color", UITheme.GOLD)
		elif _has_attacker_local(attacked):
			action_tip.text = "你的回合：可拖怪兽攻击，或结束回合"
			action_tip.add_theme_color_override("font_color", UITheme.GOLD)
		elif not spell_used:
			action_tip.text = "你的回合：可放置魔法 / 陷阱卡，或结束回合"
			action_tip.add_theme_color_override("font_color", UITheme.GOLD)
		else:
			action_tip.text = "你的回合：本回合已操作完，可结束回合"
			action_tip.add_theme_color_override("font_color", UITheme.GOLD)
		end_turn_btn.disabled = not my_turn
	else:
		action_tip.text = "本场决斗已结束（可查看卡组 / 墓地）" if state == "finished" else "等待双方准备后开始决斗"
		action_tip.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		end_turn_btn.disabled = true


## 我方场上是否有未攻击过的怪兽（按当前场上卡牌 meta 判断；attacked 已转 int）
func _has_attacker_local(attacked: Array) -> bool:
	for s in field_slots:
		var c := s as Control
		if c == null or not c.visible:
			continue
		var info: Dictionary = c.get_meta("info", {})
		var cid := int(info.get("id", 0))
		if cid > 0 and not attacked.has(cid):
			return true
	return false


# ================= 数据刷新 =================

## 刷新我方场地（mine = 当前玩家数据，room = 房间整体数据）
func update_view(mine: Dictionary, room: Dictionary) -> void:
	# ---- 回合指示（右下角操作面板顶行）----
	var state := str(room.get("state", "waiting"))
	var mine_id := str(mine.get("id", ""))
	var mine_turn := mine_id != "" and str(room.get("active_pid", "")) == mine_id
	_my_turn = state == "dueling" and mine_turn
	if state == "dueling":
		turn_title.text = "回合 %d" % int(room.get("turn", 0))
		if mine_turn:
			turn_sub.text = "你的回合"
			turn_sub.add_theme_color_override("font_color", UITheme.GOLD)
		else:
			turn_sub.text = "对方回合"
			turn_sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	elif state == "finished":
		turn_title.text = "决斗结束"
		turn_sub.text = "胜负已分"
		turn_sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	else:
		turn_title.text = "等待开始"
		turn_sub.text = "—"
		turn_sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)

	# 本回合已攻击过的怪兽卡 id（JSON 数字为 float，统一转 int）
	_attacked_ids = []
	for v in room.get("attacked", []):
		_attacked_ids.append(int(v))

	# ---- 我方面板 / 场上怪兽 / 手牌 / 墓地 / 卡组 ----
	if mine.is_empty():
		_fill_empty()
		return
	refs.name.text = str(mine.get("nickname", "玩家"))
	refs.name.add_theme_color_override("font_color", UITheme.TEXT)
	var ready_on := bool(mine.get("ready", false))
	refs.ready.text = "已准备" if ready_on else "未准备"
	refs.ready.add_theme_color_override("font_color", UITheme.GREEN if ready_on else UITheme.TEXT_DIM)

	var lp := int(mine.get("lp", 8000))
	var ratio := lp / 8000.0
	var col: Color = UITheme.GREEN if ratio > 0.5 else (UITheme.YELLOW if ratio > 0.25 else UITheme.RED)
	refs.lp_bar.value = clampi(lp, 0, 8000)
	refs.lp_bar.add_theme_stylebox_override("fill", UITheme.sb(col, col, 6, 0, 0))
	refs.lp_val.text = str(lp)

	# 场上怪兽：真实卡图（数组含空位 {}；可拖动发起攻击，单击查看详情）
	var fc = mine.get("field_cards", [])
	var flist: Array = fc if fc is Array else []
	for i in field_slots.size():
		var slot: DraggableCard = field_slots[i]
		var info: Dictionary = flist[i] if (i < flist.size() and flist[i] is Dictionary) else {}
		if not info.is_empty():
			var tex := _tex_of(info)
			slot.texture = tex if tex != null else CARD_BACK
			slot.visible = true
			slot.set_meta("info", info)
			slot.on_click = func() -> void:
				_toggle_card_detail(slot)
			var cid := int(info.get("id", 0))
			if _my_turn and cid > 0 and not _attacked_ids.has(cid):
				slot.card_data = {"kind": "attack", "card_id": cid}
				slot.tooltip_text = "拖向对手条发起攻击 · 单击查看详情"
			else:
				slot.card_data = {}
				slot.tooltip_text = "单击查看详情"
		else:
			slot.visible = false
			slot.set_meta("info", {})
			slot.card_data = {}
			slot.tooltip_text = ""

	# 魔陷区：真实卡图（放置后展示；单击查看详情，不可拖出攻击）
	var sc = mine.get("spell_cards", [])
	var slist: Array = sc if sc is Array else []
	for i in spell_slots.size():
		var sslot: DraggableCard = spell_slots[i]
		var sinfo: Dictionary = slist[i] if (i < slist.size() and slist[i] is Dictionary) else {}
		if not sinfo.is_empty():
			var stex := _tex_of(sinfo)
			sslot.texture = stex if stex != null else CARD_BACK
			sslot.visible = true
			sslot.set_meta("info", sinfo)
			sslot.card_data = {}
			sslot.on_click = func() -> void:
				_toggle_card_detail(sslot)
		else:
			sslot.visible = false
			sslot.set_meta("info", {})
			sslot.card_data = {}

	# 手牌：底部手牌区（横向滚动，可查看全部）—— entries 项：{info, gi}
	var hc = mine.get("hand_cards", [])
	var hlist: Array = hc if hc is Array else []
	var hand := int(mine.get("hand", hlist.size()))
	var entries: Array = []
	if hlist.is_empty():
		for i in mini(hand, HAND_SHOW_MAX):
			entries.append({"info": {}, "gi": -1})
	else:
		for i in hlist.size():
			entries.append({"info": hlist[i] if hlist[i] is Dictionary else {}, "gi": i})
	_rebuild_hand_row(entries)
	if entries.size() != _last_hand_n:
		_last_hand_n = entries.size()
		_scroll_hand_to_end.call_deferred()
	hand_label.text = ("手牌 · %d 张（滚轮查看）" % hand) if hand > 5 else ("手牌 · %d 张" % hand)

	# 墓地：显示墓地最上一张真实卡图（无数据时隐藏）
	var gt = mine.get("grave_top", {})
	_set_grave(grave_card, gt if gt is Dictionary else {}, state == "dueling" or state == "finished")

	# 卡组剩余数量
	var dc := int(mine.get("deck_count", 0))
	deck_label.text = ("剩余 %d 张" % dc) if dc > 0 else ""

	# 空位高亮（按当前拖拽类型刷新）
	_refresh_zone_highlight()

	# 外部（对手卡）详情为临时展示：房间数据一经刷新即收起，避免显示过时数据
	if _external_preview:
		_external_preview = false
		_hide_preview()

	_guard_preview()


## 面板复位（无我方数据时）
func _fill_empty() -> void:
	refs.name.text = "空位"
	refs.name.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	refs.ready.text = ""
	refs.lp_bar.value = 0
	refs.lp_val.text = "—"
	_attacked_ids = []
	_my_turn = false
	_rebuild_hand_row([])
	hand_label.text = "手牌 · 0 张"
	_clear_slots()
	_set_grave(grave_card, {}, false)
	deck_label.text = ""
	_refresh_zone_highlight()
	_hide_preview()


## 底部手牌行：复用已有节点，仅在数量变化时增删（放大卡图，可拖动召唤 / 单击详情）
## entries 项：{info: 卡片信息, gi: 手牌原始下标}
func _rebuild_hand_row(entries: Array) -> void:
	var box := hand_box
	while box.get_child_count() > entries.size():
		var c := box.get_child(box.get_child_count() - 1)
		box.remove_child(c)
		if _detail_card == c:
			_hide_preview()
		c.queue_free()
	while box.get_child_count() < entries.size():
		var t := DraggableCard.new()
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = HAND_CARD
		box.add_child(t)
	for i in entries.size():
		var t2: DraggableCard = box.get_child(i)
		var e: Dictionary = entries[i]
		var info: Dictionary = e.get("info", {})
		var tex := _tex_of(info)
		t2.texture = tex if tex != null else CARD_BACK
		t2.set_meta("info", info)
		t2.set_meta("hand_index", int(e.get("gi", -1)))
		t2.on_click = func() -> void:
			_toggle_card_detail(t2)
		var cid := int(info.get("id", 0))
		var kind := ""
		if cid > 0 and db != null:
			kind = str(db.get_card(cid).get("kind", ""))
		if _my_turn and kind == "monster":
			t2.card_data = {"kind": "summon", "card_id": cid, "hand_index": int(e.get("gi", -1))}
			t2.tooltip_text = "拖到怪兽区召唤 · 单击查看详情"
		elif _my_turn and (kind == "spell" or kind == "trap"):
			t2.card_data = {"kind": "summon", "card_id": cid, "hand_index": int(e.get("gi", -1))}
			t2.tooltip_text = "拖到魔陷区放置 · 单击查看详情"
		elif kind == "spell" or kind == "trap":
			t2.card_data = {}
			t2.tooltip_text = "等待你的回合（单击查看详情）"
		else:
			t2.card_data = {}
			t2.tooltip_text = ""


## 空位高亮：拖怪兽时空怪兽区绿框；拖魔法/陷阱时空魔陷区绿框（可放置提示）
func _refresh_zone_highlight() -> void:
	if slot_zones.is_empty():
		return
	var hot := _drag_kind == "summon"
	var hot_monster := hot and _drag_card_kind == "monster"
	var hot_spell := hot and (_drag_card_kind == "spell" or _drag_card_kind == "trap")
	for i in slot_zones.size():
		var occupied := i < field_slots.size() and (field_slots[i] as Control).visible
		var dz: DropZone = slot_zones[i]
		if hot_monster and not occupied:
			dz.add_theme_stylebox_override("panel", _zone_style(Color(0.12, 0.3, 0.2, 0.5), COL_ZONE_HOT))
		else:
			dz.add_theme_stylebox_override("panel", _zone_style(Color(0.04, 0.04, 0.1, 0.42), COL_ZONE))
	for i in spell_zones.size():
		var soccupied := i < spell_slots.size() and (spell_slots[i] as Control).visible
		var sz: DropZone = spell_zones[i]
		var border: Color = COL_PEND if i == 0 or i == 4 else COL_ZONE
		if hot_spell and not soccupied:
			sz.add_theme_stylebox_override("panel", _zone_style(Color(0.12, 0.3, 0.2, 0.5), COL_ZONE_HOT))
		else:
			sz.add_theme_stylebox_override("panel", _zone_style(Color(0.04, 0.04, 0.1, 0.42), border))


func _clear_slots() -> void:
	for s in field_slots:
		s.visible = false
		s.set_meta("info", {})
		s.card_data = {}
	for s in spell_slots:
		s.visible = false
		s.set_meta("info", {})
		s.card_data = {}


func _set_grave(card: TextureRect, top: Dictionary, dueling: bool) -> void:
	if card == null:
		return
	var tex := _tex_of(top)
	if tex != null:
		card.texture = tex
		card.visible = true
		card.set_meta("info", top)
	else:
		card.texture = CARD_BACK
		card.visible = dueling and db == null   # 无卡牌数据时保留旧的占位卡背
		card.set_meta("info", {})


## 外部（对手卡等）单击时展示详情：临时展示，房间数据刷新后自动收起
func show_detail_info(info: Dictionary) -> void:
	if preview_panel == null or info.is_empty():
		return
	_detail_card = null
	_external_preview = true
	_show_preview(info)


# ================= 自测辅助（--duel-ui-demo / --preview-demo） =================
# 说明：Godot 引擎的拖拽「启动」依赖真实鼠标输入（合成事件无法触发 drag 系统），
# 自测改为直接调用拖放业务链路（_get_drag_data → 目标 _can_drop_data / _drop_data），
# 覆盖除「引擎启动拖拽」外的全部代码路径；引擎启动部分为引擎标准行为。

## 自测：模拟「拖手牌到怪兽区 / 魔陷区格」——走 _get_drag_data → 空位 _can_drop_data/_drop_data
## area = "monster"（默认，怪兽区）/ "spell"（魔陷区）
func demo_drag_hand_to_slot(card_id: int, pos: int, area := "monster") -> bool:
	var from: Control = null
	for i in range(hand_box.get_child_count() - 1, -1, -1):
		var c: Control = hand_box.get_child(i)
		var info: Dictionary = c.get_meta("info", {})
		if int(info.get("id", 0)) == card_id:
			from = c
			break
	var zones: Array = spell_zones if area == "spell" else slot_zones
	if from == null or pos < 0 or pos >= zones.size():
		return false
	var data = from.call("_get_drag_data", (from as Control).size / 2.0)
	if not (data is Dictionary):
		print("[自测] 拖拽数据为空（卡不可拖）")
		return false
	var dz: DropZone = zones[pos]
	if dz.call("_can_drop_data", Vector2.ZERO, data):
		dz.call("_drop_data", Vector2.ZERO, data)
		return true
	return false


## 自测：构造我方场上怪兽的「攻击拖拽数据」（走该卡的 _get_drag_data）
func demo_make_attack_data(card_id: int) -> Variant:
	for s in field_slots:
		var info: Dictionary = s.get_meta("info", {})
		if (s as Control).visible and int(info.get("id", 0)) == card_id:
			return (s as Control).call("_get_drag_data", (s as Control).size / 2.0)
	return null


## 合成一次「单击左键」事件并送入视口（自测：--preview-demo 的详情展示走真实输入链路）
func _demo_click(node: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = node.get_global_rect().get_center()
	get_viewport().push_input(ev, true)
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = false
	ev2.position = ev.position
	get_viewport().push_input(ev2, true)


# ================= 卡牌详情预览（单击放大） =================

## 给卡牌节点挂接单击查看详情（墓地等无拖拽需求的卡牌用）
func _wire_preview(node: Control) -> void:
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.gui_input.connect(_on_card_gui_input.bind(node))


func _on_card_gui_input(event: InputEvent, node: Control) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not mb.double_click:
			_toggle_card_detail(node)


## 切换该卡详情：未显示则放大显示；已显示同一张则收起
func _toggle_card_detail(node: Control) -> void:
	var info: Dictionary = node.get_meta("info", {})
	if info.is_empty():
		return
	if _detail_card == node and preview_panel.visible:
		_hide_preview()
	else:
		_show_detail_on(node)


## 在某张卡上展示详情（记录选中卡）
func _show_detail_on(node: Control) -> void:
	_detail_card = node
	_external_preview = false
	_show_preview(node.get_meta("info", {}))


## 显示卡片详情：放大卡图 + 名称 + ATK/DEF
func _show_preview(info: Dictionary) -> void:
	if preview_panel == null or info.is_empty():
		return
	var tex := _tex_of(info)
	preview_card.texture = tex if tex != null else CARD_BACK
	preview_name.text = str(info.get("name", "卡片"))
	var atk := int(info.get("atk", -1))
	var dfn := int(info.get("def", -1))
	preview_stats.text = ("ATK %d ／ DEF %d" % [atk, dfn]) if atk >= 0 else ""
	preview_panel.visible = true


func _hide_preview() -> void:
	if preview_panel != null:
		preview_panel.visible = false
	_detail_card = null


## 详情守护：被选中展示的卡牌消失/隐藏/数据清空时自动收起
func _guard_preview() -> void:
	if _detail_card == null:
		return
	if not is_instance_valid(_detail_card) or not _detail_card.visible:
		_hide_preview()
		return
	var info: Dictionary = _detail_card.get_meta("info", {})
	if info.is_empty():
		_hide_preview()
	else:
		_show_preview(info)


## 自测辅助（--preview-demo）：单击第一张有卡数据的卡（优先场上怪兽 → 手牌 → 墓地），
## 已有详情展示时保持不动；返回是否已有一张卡处于详情显示状态
func demo_show_detail() -> bool:
	if _detail_card != null and is_instance_valid(_detail_card) and _detail_card.visible:
		var cur: Dictionary = _detail_card.get_meta("info", {})
		if not cur.is_empty():
			return true
	var node := _find_first_card_node()
	if node == null:
		return false
	# 优先走真实链路（合成单击事件送入视口）；未命中则兜底直接展示
	_demo_click(node)
	if _detail_card != node:
		print("[自测] 合成单击未命中，兜底直接展示卡牌详情")
		_show_detail_on(node)
	return true


## 找第一张有卡数据的卡牌节点（怪兽槽优先，其次手牌，最后墓地）
func _find_first_card_node() -> Control:
	for s in field_slots:
		var info: Dictionary = s.get_meta("info", {})
		if (s as Control).visible and not info.is_empty():
			return s
	for i in range(hand_box.get_child_count() - 1, -1, -1):
		var c: Control = hand_box.get_child(i)
		var hinfo: Dictionary = c.get_meta("info", {})
		if not hinfo.is_empty():
			return c
	return null


## 自测（--hand-demo=N）：用卡库真卡造 N 张假手牌填充手牌视图（验证多张手牌布局与横向滚动）
func demo_show_fake_hand(n: int) -> void:
	if db == null or db.ids.is_empty() or n <= 0:
		return
	var entries: Array = []
	var total := db.ids.size()
	for i in n:
		var cid := int(db.ids[(i * 977 + 123) % total])   # 分散取样，避免相邻重复
		entries.append({"info": db.brief(cid), "gi": i})
	_rebuild_hand_row(entries)
	hand_label.text = ("手牌 · %d 张（滚轮查看）" % n) if n > 5 else ("手牌 · %d 张" % n)
	_last_hand_n = n
	_scroll_hand_to_end.call_deferred()


## 卡片信息 → 纹理（需要外部注入的 CardDB）
func _tex_of(info: Dictionary) -> Texture2D:
	if db == null or info.is_empty():
		return null
	return db.texture_of(int(info.get("id", 0)))
