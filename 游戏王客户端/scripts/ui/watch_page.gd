class_name WatchPage
extends Control
## 全屏观战页面（1920x1080 设计稿，等比缩放居中）—— 客户端版
## 背景：生成的决斗场原图；卡区按标准大师规则布局
## 卡牌：注入 CardDB 后显示真实卡图（怪兽区/手牌/墓地/卡组数量），
## 数据来自服务端 watch_snapshot 推送的 room.players[].{field_cards,hand_cards,grave_top,deck_count}；
## 未注入卡库或卡图缺失时自动回退卡背占位。

signal exit_requested

const BG_TEX := preload("res://assets/field_bg.jpg")
const CARD_BACK := preload("res://assets/card_back.png")

const DESIGN := Vector2(1920, 1080)
const ZONE_W := 122.0
const ZONE_H := 178.0
const COLS := [627.0, 763.0, 899.0, 1035.0, 1171.0]   # 5 列左边缘
const ROWS := [67.0, 259.0, 451.0, 643.0, 835.0]      # 5 行上边缘
const CIRCLE_D := 132.0
const CARD_MINI := Vector2(34, 50)
const CARD_BIG := Vector2(86, 126)
const HAND_SHOW_MAX := 5      # 手牌最多展示张数

# 区域配色
const COL_ZONE := Color(0.62, 0.64, 0.78, 0.5)        # 普通区
const COL_PEND := Color(0.42, 0.82, 0.76, 0.65)       # 灵摆区
const COL_EMZ := Color(0.72, 0.55, 0.95, 0.7)         # 额外怪兽区
const COL_DECK := Color(0.85, 0.68, 0.32, 0.85)       # 卡组
const COL_GRAVE := Color(0.72, 0.45, 0.85, 0.85)      # 墓地
const COL_EXTRA := Color(0.45, 0.62, 0.92, 0.85)      # 额外卡组
const COL_FIELD := Color(0.95, 0.8, 0.4, 0.95)        # 场地区域

var db: CardDB = null         # 客户端卡图库（main_ui 注入；null = 卡背占位模式）

var stage: Control

var room_title: Label
var badge_panel: PanelContainer
var badge_label: Label
var turn_title: Label
var turn_sub: Label
var ticker: Label
var opp_grave_card: TextureRect
var my_grave_card: TextureRect
var opp_field_slots: Array = []   # 对方怪兽区卡牌槽（5 个 TextureRect）
var my_field_slots: Array = []    # 己方怪兽区卡牌槽
var opp_spell_slots: Array = []   # 对方魔陷区卡牌槽（5 个 TextureRect）
var my_spell_slots: Array = []    # 己方魔陷区卡牌槽
var opp_deck_label: Label
var my_deck_label: Label

var opp_refs: Dictionary
var my_refs: Dictionary


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false   # 初始隐藏：仅由 open()/close_view() 控制显隐（否则会盖住登录/大厅页）
	_build_stage()
	_build_zones()
	_build_hud()
	resized.connect(_update_stage)
	_update_stage.call_deferred()


## 设计稿等比缩放并居中（保证 1920x1080 布局在任何窗口下不变形）
func _update_stage() -> void:
	var vs := get_viewport_rect().size
	var s: float = min(vs.x / DESIGN.x, vs.y / DESIGN.y)
	stage.scale = Vector2(s, s)
	stage.position = (Vector2(vs) - DESIGN * s) / 2.0


# ================= 场景构建 =================

func _build_stage() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.02, 0.04)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	stage = Control.new()
	stage.position = Vector2.ZERO
	stage.size = DESIGN
	stage.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(stage)

	var bg := TextureRect.new()
	bg.texture = BG_TEX
	bg.position = Vector2.ZERO
	bg.size = DESIGN
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(bg)


func _build_zones() -> void:
	# ---- 对方（上方）：最外行魔陷区（两端灵摆），怪兽区贴近中央 ----
	for i in 5:
		_tile_zone(COLS[i], ROWS[0], "灵摆" if i == 0 or i == 4 else "", COL_PEND if i == 0 or i == 4 else COL_ZONE)
	opp_spell_slots = _field_slots_for(ROWS[0])
	for i in 5:
		_tile_zone(COLS[i], ROWS[1])
	opp_field_slots = _field_slots_for(ROWS[1])
	_tile_zone(COLS[1], ROWS[2], "额外怪兽区", COL_EMZ)
	_tile_zone(COLS[3], ROWS[2], "额外怪兽区", COL_EMZ)
	# ---- 己方（下方）：怪兽区贴近中央，最外行魔陷区（两端灵摆）----
	for i in 5:
		_tile_zone(COLS[i], ROWS[3])
	my_field_slots = _field_slots_for(ROWS[3])
	for i in 5:
		_tile_zone(COLS[i], ROWS[4], "灵摆" if i == 0 or i == 4 else "", COL_PEND if i == 0 or i == 4 else COL_ZONE)
	my_spell_slots = _field_slots_for(ROWS[4])

	# 行标签（卡区左侧）
	_side_caption("对方魔陷区", ROWS[0])
	_side_caption("对方怪兽区", ROWS[1])
	_side_caption("己方怪兽区", ROWS[3])
	_side_caption("己方魔陷区", ROWS[4])

	# ---- 对方（左侧）圆区：卡组 / 墓地 / 额外卡组 + 场地区域 ----
	_circle_zone(Vector2(345, 200), COL_DECK, "卡组", true)
	opp_grave_card = _circle_zone(Vector2(345, 340), COL_GRAVE, "墓地", false)
	_circle_zone(Vector2(345, 480), COL_EXTRA, "额外卡组", true)
	_circle_zone(Vector2(205, 507), COL_FIELD, "场地区域", false)
	opp_deck_label = _deck_count_label(Vector2(424, 190))
	# ---- 己方（右侧）圆区（中心对称）----
	_circle_zone(Vector2(1575, 880), COL_DECK, "卡组", true)
	my_grave_card = _circle_zone(Vector2(1575, 740), COL_GRAVE, "墓地", false)
	_circle_zone(Vector2(1575, 600), COL_EXTRA, "额外卡组", true)
	_circle_zone(Vector2(1715, 507), COL_FIELD, "场地区域", false)
	my_deck_label = _deck_count_label(Vector2(1654, 870))


## 一行 5 个怪兽区卡牌槽（默认隐藏，update_view 时填真实卡图）
func _field_slots_for(row_y: float) -> Array:
	var out: Array = []
	for i in 5:
		var t := TextureRect.new()
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.position = Vector2(COLS[i], row_y)
		t.size = Vector2(ZONE_W, ZONE_H)
		t.mouse_filter = Control.MOUSE_FILTER_PASS   # 允许悬浮查看卡名
		t.visible = false
		stage.add_child(t)
		out.append(t)
	return out


## 卡组剩余数量标签（圆区右侧）
func _deck_count_label(pos: Vector2) -> Label:
	var l := UITheme.text_label("", Color(1, 1, 1, 0.65), 12)
	l.position = pos
	l.size = Vector2(150, 20)
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
		l.position = Vector2(x, y + ZONE_H - 18)
		l.size = Vector2(ZONE_W, 14)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(l)


func _circle_zone(center: Vector2, border: Color, caption: String, deck_stack: bool) -> TextureRect:
	var p := Panel.new()
	p.position = center - Vector2(CIRCLE_D, CIRCLE_D) / 2.0
	p.size = Vector2(CIRCLE_D, CIRCLE_D)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _zone_style(Color(0.05, 0.05, 0.12, 0.55), border, CIRCLE_D / 2.0))
	stage.add_child(p)

	var card: TextureRect = null
	if deck_stack:
		# 卡组：叠放两张卡背占位
		_card_rect(center - CARD_BIG / 2.0 + Vector2(5, 6), CARD_BIG)
		card = _card_rect(center - CARD_BIG / 2.0, CARD_BIG)
	elif caption == "墓地":
		# 墓地：显示墓地最上一张卡（无数据时隐藏）
		card = _card_rect(center - CARD_BIG / 2.0, CARD_BIG)
		card.visible = false
		card.mouse_filter = Control.MOUSE_FILTER_PASS   # 允许悬浮查看卡名
	var l := UITheme.text_label(caption, Color(1, 1, 1, 0.6), 11)
	l.position = center + Vector2(-80, CIRCLE_D / 2.0 + 4)
	l.size = Vector2(160, 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(l)
	return card


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
	l.position = Vector2(430, row_y + ZONE_H / 2.0 - 9)
	l.size = Vector2(185, 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(l)


# ================= HUD 构建 =================

func _build_hud() -> void:
	_build_topbar()
	_build_turn_pill()
	opp_refs = _make_player_panel(Vector2(24, 14), "对手")
	my_refs = _make_player_panel(Vector2(24, DESIGN.y - 14 - 116), "玩家 1")
	_build_ticker()


func _build_topbar() -> void:
	# 房间名（顶部居中）
	room_title = UITheme.text_label("房间观战", UITheme.GOLD, 15)
	room_title.position = Vector2(420, 18)
	room_title.size = Vector2(1030, 24)
	room_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(room_title)

	# 右上角：状态徽章 + 退出观战
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.offset_right = -24
	bar.offset_top = 14
	bar.offset_bottom = 52
	stage.add_child(bar)

	badge_panel = PanelContainer.new()
	badge_panel.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG_PANEL_LIGHT, UITheme.BORDER, 6, 1, 5))
	bar.add_child(badge_panel)
	badge_label = UITheme.text_label("等待数据", UITheme.BLUE, 12)
	badge_panel.add_child(badge_label)

	var back_btn := Button.new()
	back_btn.text = "← 退出观战"
	back_btn.custom_minimum_size = Vector2(110, 34)
	UITheme.style_button(back_btn, true)
	back_btn.pressed.connect(func(): exit_requested.emit())
	bar.add_child(back_btn)


func _build_turn_pill() -> void:
	# 场地中央（两个额外怪兽区之间）：回合 / 阶段指示
	var p := Panel.new()
	p.position = Vector2(888, 502)
	p.size = Vector2(144, 76)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _zone_style(Color(0.03, 0.03, 0.08, 0.7), UITheme.GOLD, 12))
	stage.add_child(p)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)

	turn_title = UITheme.text_label("等待开始", UITheme.GOLD, 15)
	turn_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(turn_title)
	turn_sub = UITheme.text_label("—", UITheme.TEXT, 11)
	turn_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(turn_sub)


func _make_player_panel(pos: Vector2, role: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.size = Vector2(280, 116)
	panel.add_theme_stylebox_override("panel", UITheme.sb(Color(0.04, 0.04, 0.09, 0.72), UITheme.BORDER, 10, 1, 10))
	stage.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	panel.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	var role_l := UITheme.text_label(role, UITheme.TEXT_DIM, 12, true)
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

	var hand_row := HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", 5)
	v.add_child(hand_row)
	var hand_box := HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 3)
	hand_row.add_child(hand_box)
	var hand_val := UITheme.text_label("手牌 —", UITheme.TEXT_DIM, 11, true)
	hand_val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hand_row.add_child(hand_val)

	return {
		"panel": panel,
		"role": role_l,
		"ready": ready_l,
		"name": name_l,
		"lp_bar": bar,
		"lp_val": lp_val,
		"hand_box": hand_box,
		"hand_val": hand_val,
	}


func _build_ticker() -> void:
	var p := Panel.new()
	p.position = Vector2(332, 1024)
	p.size = Vector2(1236, 50)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _zone_style(Color(0.03, 0.03, 0.07, 0.62), Color(0.3, 0.3, 0.45, 0.5), 8))
	stage.add_child(p)

	ticker = UITheme.text_label("", UITheme.TEXT_DIM, 12)
	ticker.position = Vector2(344, 1030)
	ticker.size = Vector2(1212, 40)
	ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(ticker)


# ================= 数据刷新 =================

func open(room_name: String, server_text: String) -> void:
	room_title.text = "观战：「%s」  ·  %s" % [room_name, server_text]
	_set_badge("等待数据", UITheme.BLUE)
	turn_title.text = "等待开始"
	turn_sub.text = "—"
	ticker.text = ""
	_fill_panel(opp_refs, {}, opp_field_slots, opp_spell_slots, opp_deck_label)
	_fill_panel(my_refs, {}, my_field_slots, my_spell_slots, my_deck_label)
	_set_grave(opp_grave_card, {}, false)
	_set_grave(my_grave_card, {}, false)
	visible = true


func close_view() -> void:
	visible = false


func update_view(view: Dictionary) -> void:
	var state := str(view.get("state", "waiting"))
	_set_badge(_state_text(state), _state_color(state))

	var ps = view.get("players", [])
	var plist: Array = ps if ps is Array else []
	# 顶部 = 玩家2，底部 = 玩家1（房主）
	_fill_panel(opp_refs, plist[1] if plist.size() > 1 else {}, opp_field_slots, opp_spell_slots, opp_deck_label)
	_fill_panel(my_refs, plist[0] if plist.size() > 0 else {}, my_field_slots, my_spell_slots, my_deck_label)

	var turn := int(view.get("turn", 0))
	var phase := str(view.get("phase", ""))
	if state == "dueling":
		turn_title.text = "回合 %d" % turn
		turn_sub.text = phase if phase != "" else "决斗中"
	elif state == "finished":
		turn_title.text = "决斗结束"
		turn_sub.text = phase if phase != "" else "—"
	else:
		turn_title.text = "等待开始"
		turn_sub.text = "%d/%d 名玩家" % [int(view.get("member_count", 0)), int(view.get("max_players", 2))]

	# 墓地：显示墓地最上一张真实卡图（无卡牌数据时退回卡背占位）
	var dueling := state == "dueling"
	_set_grave(opp_grave_card, _item_dict(plist, 1, "grave_top"), dueling)
	_set_grave(my_grave_card, _item_dict(plist, 0, "grave_top"), dueling)

	# 底部动态条：最近两条日志
	var logs = view.get("logs", [])
	var lines: Array = logs if logs is Array else []
	var parts := []
	for i in range(maxi(0, lines.size() - 2), lines.size()):
		parts.append("· " + str(lines[i]))
	ticker.text = "\n".join(parts)


func _item_dict(plist: Array, idx: int, key: String) -> Dictionary:
	if idx < 0 or idx >= plist.size():
		return {}
	var p = plist[idx]
	if not (p is Dictionary):
		return {}
	var v = p.get(key, {})
	return v if v is Dictionary else {}


func _fill_panel(refs: Dictionary, p: Dictionary, slots: Array, spell_slots: Array, deck_label: Label) -> void:
	if p.is_empty():
		refs.name.text = "空位"
		refs.name.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		refs.ready.text = ""
		refs.lp_bar.value = 0
		refs.lp_val.text = "—"
		refs.hand_val.text = "手牌 —"
		_clear_hand(refs)
		_clear_slots(slots)
		_clear_slots(spell_slots)
		if deck_label != null:
			deck_label.text = ""
		return
	refs.name.text = str(p.get("nickname", "玩家"))
	refs.name.add_theme_color_override("font_color", UITheme.TEXT)
	var lp := int(p.get("lp", 8000))
	var ratio := lp / 8000.0
	var col: Color = UITheme.GREEN if ratio > 0.5 else (UITheme.YELLOW if ratio > 0.25 else UITheme.RED)
	refs.lp_bar.value = clampi(lp, 0, 8000)
	refs.lp_bar.add_theme_stylebox_override("fill", UITheme.sb(col, col, 6, 0, 0))
	refs.lp_val.text = str(lp)
	refs.ready.text = "已准备" if bool(p.get("ready", false)) else "未准备"
	refs.ready.add_theme_color_override("font_color", UITheme.GREEN if bool(p.get("ready", false)) else UITheme.TEXT_DIM)

	# 场上怪兽：真实卡图（显示在怪兽区槽位；数组含空位 {}，按格位渲染）
	var fc = p.get("field_cards", [])
	var flist: Array = fc if fc is Array else []
	for i in slots.size():
		var slot: TextureRect = slots[i]
		var info: Dictionary = flist[i] if (i < flist.size() and flist[i] is Dictionary) else {}
		if not info.is_empty():
			var tex := _tex_of(info)
			slot.texture = tex if tex != null else CARD_BACK
			slot.tooltip_text = _card_tip(info)
			slot.visible = true
		else:
			slot.visible = false
			slot.tooltip_text = ""

	# 魔陷区：真实卡图（放置后展示；数组含空位 {}，按格位渲染）
	var sc = p.get("spell_cards", [])
	var slist: Array = sc if sc is Array else []
	for i in spell_slots.size():
		var sslot: TextureRect = spell_slots[i]
		var sinfo: Dictionary = slist[i] if (i < slist.size() and slist[i] is Dictionary) else {}
		if not sinfo.is_empty():
			var stex := _tex_of(sinfo)
			sslot.texture = stex if stex != null else CARD_BACK
			sslot.tooltip_text = _card_tip(sinfo)
			sslot.visible = true
		else:
			sslot.visible = false
			sslot.tooltip_text = ""

	# 手牌：真实卡图（最多展示最新 5 张；无卡牌数据时退回卡背占位）+ 数量
	var hc = p.get("hand_cards", [])
	var hlist: Array = hc if hc is Array else []
	var hand := int(p.get("hand", hlist.size()))
	var entries: Array = []
	if hlist.is_empty():
		for i in mini(hand, HAND_SHOW_MAX):
			entries.append({})
	else:
		var start := maxi(0, hlist.size() - HAND_SHOW_MAX)
		for i in range(start, hlist.size()):
			entries.append(hlist[i] if hlist[i] is Dictionary else {})
	_rebuild_hand(refs, entries)
	refs.hand_val.text = "手牌 %d 张" % hand

	# 卡组剩余数量
	if deck_label != null:
		var dc := int(p.get("deck_count", 0))
		deck_label.text = ("剩余 %d 张" % dc) if dc > 0 else ""


## 手牌小图：复用已有节点，仅在数量变化时增删（避免每 0.5s 重建节点）
func _rebuild_hand(refs: Dictionary, entries: Array) -> void:
	var box: HBoxContainer = refs.hand_box
	while box.get_child_count() > entries.size():
		var c := box.get_child(box.get_child_count() - 1)
		box.remove_child(c)
		c.queue_free()
	while box.get_child_count() < entries.size():
		var t := TextureRect.new()
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = CARD_MINI
		t.mouse_filter = Control.MOUSE_FILTER_PASS   # 允许悬浮查看卡名
		box.add_child(t)
	for i in entries.size():
		var t2: TextureRect = box.get_child(i)
		var info: Dictionary = entries[i]
		var tex := _tex_of(info)
		t2.texture = tex if tex != null else CARD_BACK
		t2.tooltip_text = _card_tip(info)


func _clear_hand(refs: Dictionary) -> void:
	_rebuild_hand(refs, [])


func _clear_slots(slots: Array) -> void:
	for s in slots:
		s.visible = false
		s.tooltip_text = ""


func _set_grave(card: TextureRect, top: Dictionary, dueling: bool) -> void:
	if card == null:
		return
	var tex := _tex_of(top)
	if tex != null:
		card.texture = tex
		card.tooltip_text = _card_tip(top)
		card.visible = true
	else:
		card.texture = CARD_BACK
		card.tooltip_text = ""
		card.visible = dueling and db == null   # 无卡牌数据时保留旧的占位卡背


## 卡片信息 → 纹理（需要外部注入的 CardDB）
func _tex_of(info: Dictionary) -> Texture2D:
	if db == null or info.is_empty():
		return null
	return db.texture_of(int(info.get("id", 0)))


func _card_tip(info: Dictionary) -> String:
	if info.is_empty():
		return ""
	var cname := str(info.get("name", ""))
	var atk := int(info.get("atk", -1))
	var dfn := int(info.get("def", -1))
	if atk >= 0:
		return "%s\nATK %d ／ DEF %d" % [cname, atk, dfn]
	return cname


func _state_text(state: String) -> String:
	match state:
		"waiting":
			return "等待中"
		"dueling":
			return "对战中"
		"finished":
			return "已结束"
	return state


func _state_color(state: String) -> Color:
	match state:
		"waiting":
			return UITheme.BLUE
		"dueling":
			return UITheme.GOLD
	return UITheme.TEXT_DIM


func _set_badge(text: String, color: Color) -> void:
	badge_label.text = text
	badge_label.add_theme_color_override("font_color", color)
	badge_panel.add_theme_stylebox_override("panel", UITheme.sb(color.darkened(0.75), color.darkened(0.25), 6, 1, 5))
