class_name PackPage
extends Control
## 卡包页面（客户端 · 全屏覆盖）
## 布局：深色星空背景 + 卡包网格（第一格为「＋ 新建卡包」）
## 每个卡包格：代表卡封面（卡图裁切 + 主题色调）+ STANDARD 标签 + 名称
## 点击卡包 → 发出 pack_opened 信号，由 main_ui 打开「卡片管理」页面
## —— 自服务端同步（2026-10-14 快照）；后续服务端改动需手动再同步

signal pack_opened(pack_id: String)
signal closed

const COLS := 6

var card_db: CardDB = null
var pack_db: PackDB = null

var _grid: GridContainer
var _toast: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false   # 初始隐藏：仅由 open()/close_page() 控制显隐
	_build_ui()
	resized.connect(_on_resized)


## 打开页面（重新构建卡包列表）
func open() -> void:
	visible = true
	_rebuild()


func close_page() -> void:
	visible = false
	closed.emit()


# ================= 界面构建 =================

func _build_ui() -> void:
	var backdrop := _Backdrop.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)

	# 顶栏：标题 + 构建全部 + 关闭
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	head.add_child(UITheme.text_label("卡包", UITheme.TEXT, 20))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var build_btn := Button.new()
	build_btn.text = "构建全部"
	UITheme.style_button(build_btn, true)
	build_btn.tooltip_text = "为还没有牌组的卡包各自动构筑 %d 张主牌组 + %d 张额外牌组（已有牌组的卡包跳过）" % [PackDB.DECK_SIZE, PackDB.EXTRA_SIZE]
	build_btn.pressed.connect(_on_build_all)
	head.add_child(build_btn)
	var close_btn := Button.new()
	close_btn.text = "关闭"
	UITheme.style_button(close_btn, false, true)
	close_btn.pressed.connect(close_page)
	head.add_child(close_btn)

	v.add_child(UITheme.text_label("点击「＋」新建卡包；点击卡包进入卡片管理，编辑该卡包的牌组", UITheme.TEXT_DIM, 12, true))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(_grid)

	# 底部轻提示（新建成功等）
	_toast = UITheme.text_label("", UITheme.YELLOW, 13)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_top = -40.0
	_toast.offset_bottom = -12.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)


# ================= 卡包网格 =================

func _rebuild() -> void:
	if pack_db == null or _grid == null:
		return
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()

	# 第一格：新建卡包
	var add_card := PackCard.new()
	_grid.add_child(add_card)
	add_card.configure_create()
	add_card.pressed.connect(_on_create_pack)

	# 卡包格
	for p in pack_db.packs:
		var c := PackCard.new()
		_grid.add_child(c)
		var tex: Texture2D = null
		if card_db != null:
			tex = card_db.texture_of(int(p.get("cover_id", 0)))
		c.configure_pack(p, tex)
		var pid := str(p.get("id", ""))
		c.pressed.connect(func() -> void: pack_opened.emit(pid))

	_on_resized()


## 按页面宽度自适应卡片高度（保持接近方形比例）
func _on_resized() -> void:
	if _grid == null:
		return
	var avail := size.x - 52.0 - 14.0   # 页面边距 + 滚动条余量
	var sep := float(_grid.get_theme_constant("h_separation"))
	var w := (avail - sep * (COLS - 1)) / float(COLS)
	if w <= 60.0:
		return
	# 格子略偏竖长：给封面区更多高度，完整卡图（竖版）能显示得更大
	var h := clampf(w * 1.12, 150.0, 340.0)
	for c in _grid.get_children():
		c.custom_minimum_size = Vector2(0.0, h)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


## 自测辅助：模拟点击第 index 个卡包格（0 = 第一个卡包，走真实 pressed → pack_opened 链路）
func simulate_click_pack(index: int) -> void:
	var pack_cards: Array = []
	for c in _grid.get_children():
		if c is PackCard and not (c as PackCard).is_create:
			pack_cards.append(c)
	if index >= 0 and index < pack_cards.size():
		(pack_cards[index] as PackCard).pressed.emit()


## 构建全部：为还没有牌组的卡包批量自动构筑（已有牌组的卡包跳过）
func _on_build_all() -> void:
	if pack_db == null:
		return
	var r: Array = pack_db.build_empty_packs()
	var built := int(r[0])
	var skipped := int(r[1])
	if built > 0:
		var msg := "已为 %d 个空卡包构建牌组（%d 张主牌组 + %d 张额外牌组）" % [built, PackDB.DECK_SIZE, PackDB.EXTRA_SIZE]
		if skipped > 0:
			msg += "；%d 个已有牌组，已跳过" % skipped
		_show_toast(msg)
	else:
		_show_toast("所有卡包都已有牌组；如需重建可进入对应卡包点「自动构筑」")


# ================= 新建卡包弹窗 =================

func _on_create_pack() -> void:
	if pack_db == null:
		return
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cc)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG_PANEL, UITheme.ACCENT_DEEP, 12, 1, 16))
	cc.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UITheme.text_label("新建卡包", UITheme.TEXT, 15))

	var edit := LineEdit.new()
	edit.placeholder_text = "输入卡包名称（留空自动命名）"
	edit.custom_minimum_size = Vector2(0, 38)
	UITheme.style_line_edit(edit)
	v.add_child(edit)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	btns.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(btns)

	var cancel := Button.new()
	cancel.text = "取消"
	UITheme.style_button(cancel)
	cancel.pressed.connect(func() -> void: layer.queue_free())
	btns.add_child(cancel)

	var ok := Button.new()
	ok.text = "创建"
	UITheme.style_button(ok, true)
	btns.add_child(ok)

	var do_create := func(name: String) -> void:
		var p := pack_db.create_pack(name)
		layer.queue_free()
		_rebuild()
		_show_toast("已创建卡包「%s」（卡片池 %d 张）" % [str(p.get("name", "")), int((p.get("cards", []) as Array).size())])
	ok.pressed.connect(func() -> void: do_create.call(edit.text))
	edit.text_submitted.connect(func(t: String) -> void: do_create.call(t))
	edit.grab_focus()


# ================= 内部类：卡包格 =================

class PackCard extends Button:
	## 卡包格：自绘底板 + 封面（卡图裁切 + 主题色调），子标签显示 STANDARD / 名称
	var is_create := false
	var accent := Color("6f7fd8")
	var cover_tex: Texture2D = null
	var display_name := ""
	var _hovered := false
	var _name_label: Label
	var _tag_label: Label

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		size_flags_horizontal = Control.SIZE_EXPAND_FILL   # 在网格中均分列宽
		custom_minimum_size = Vector2(150, 190)
		mouse_entered.connect(func() -> void:
			_hovered = true
			queue_redraw()
		)
		mouse_exited.connect(func() -> void:
			_hovered = false
			queue_redraw()
		)
		resized.connect(queue_redraw)
		_ensure_labels()

	func _ensure_labels() -> void:
		if _name_label != null:
			return
		_name_label = Label.new()
		_name_label.add_theme_font_size_override("font_size", 13)
		_name_label.add_theme_color_override("font_color", UITheme.TEXT)
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_name_label.offset_top = -32.0
		_name_label.offset_bottom = -8.0
		add_child(_name_label)

		_tag_label = Label.new()
		_tag_label.add_theme_font_size_override("font_size", 9)
		_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tag_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_tag_label.offset_left = 8.0
		_tag_label.offset_right = -10.0
		_tag_label.offset_top = 6.0
		_tag_label.offset_bottom = 24.0
		add_child(_tag_label)

	func configure_create() -> void:
		_ensure_labels()
		is_create = true
		accent = Color("c8e05a")
		_name_label.text = "新建卡包"
		_name_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		_tag_label.text = ""
		tooltip_text = "新建卡包"
		queue_redraw()

	func configure_pack(p: Dictionary, tex: Texture2D) -> void:
		_ensure_labels()
		is_create = false
		display_name = str(p.get("name", ""))
		accent = Color(str(p.get("color", "6f7fd8")))
		cover_tex = tex
		_name_label.text = display_name
		_name_label.add_theme_color_override("font_color", UITheme.TEXT)
		_tag_label.text = "STANDARD"
		_tag_label.add_theme_color_override("font_color", accent.lightened(0.5))
		_tag_label.add_theme_constant_override("outline_size", 3)
		_tag_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.12, 0.9))
		tooltip_text = "%s（点击进入卡片管理）" % display_name
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if r.size.x <= 1.0 or r.size.y <= 1.0:
			return
		var border := accent.darkened(0.25) if not _hovered else accent.lightened(0.3)
		draw_style_box(UITheme.sb(Color(0.075, 0.09, 0.16, 0.94), border, 14, 1.4, 0), r)
		if is_create:
			_draw_create()
			return
		var pad := 9.0
		var name_h := 38.0
		var cover_rect := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0 - name_h)
		if cover_tex != null:
			# 背景氛围层：卡图 cover 铺底 + 重度暗化（保留卡面色彩氛围，不抢主体）
			draw_texture_rect_region(cover_tex, cover_rect, _cover_src(cover_tex.get_size(), cover_rect.size))
			draw_rect(cover_rect, Color(0.03, 0.04, 0.08, 0.56 if _hovered else 0.68))
			var tint := accent
			tint.a = 0.12 if _hovered else 0.20
			draw_rect(cover_rect, tint)
			# 主体：完整卡图等比缩放居中（contain 模式，不裁切，整张卡完整可见）
			var fit := _contain_dst(cover_tex.get_size(), cover_rect.grow(-6.0))
			draw_rect(Rect2(fit.position + Vector2(2.0, 3.0), fit.size), Color(0, 0, 0, 0.38))   # 柔和投影
			draw_texture_rect(cover_tex, fit, false)
			draw_rect(fit, Color(1, 1, 1, 0.10), false, 1.0)   # 细描边，与暗底分离
		else:
			# 无卡图兜底：主题色渐变块
			draw_rect(cover_rect, accent.darkened(0.62))
			draw_rect(Rect2(cover_rect.position, Vector2(cover_rect.size.x, cover_rect.size.y * 0.45)), accent.darkened(0.42))
		# 封面底边轻渐隐（贴合底边，避免压暗卡图主体）
		for i in 3:
			var hh := cover_rect.size.y * 0.12 / pow(2.0, i)
			draw_rect(Rect2(cover_rect.position.x, cover_rect.end.y - hh, cover_rect.size.x, hh), Color(0.04, 0.05, 0.09, 0.05))
		# 顶部内侧高光
		draw_line(Vector2(pad + 8.0, pad + 3.0), Vector2(size.x - pad - 8.0, pad + 3.0), Color(1, 1, 1, 0.08), 1.0)

	## 封面裁切：按目标框比例取纹理中心区域（cover 模式，用作背景氛围层）
	static func _cover_src(tex_size: Vector2, target: Vector2) -> Rect2:
		var ta := tex_size.x / tex_size.y
		var ra := target.x / target.y
		if ta > ra:
			var w := tex_size.y * ra
			return Rect2((tex_size.x - w) * 0.5, 0.0, w, tex_size.y)
		var h := tex_size.x / ra
		return Rect2(0.0, (tex_size.y - h) * 0.5, tex_size.x, h)

	## 完整卡图：等比缩放至目标框内居中（contain 模式，不裁切）
	static func _contain_dst(tex_size: Vector2, target: Rect2) -> Rect2:
		if tex_size.x <= 0.0 or tex_size.y <= 0.0:
			return target
		var sc: float = minf(target.size.x / tex_size.x, target.size.y / tex_size.y)
		var s := tex_size * sc
		return Rect2(target.position + (target.size - s) * 0.5, s)

	func _draw_create() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5 - 14.0)
		var rad: float = minf(size.x, size.y) * 0.17
		var col := accent
		for i in 3:
			draw_circle(c, rad * (1.9 - 0.3 * i), Color(col.r, col.g, col.b, 0.035))
		draw_arc(c, rad, 0.0, TAU, 48, col, 2.2, true)
		var arm := rad * 0.52
		draw_line(c - Vector2(arm, 0.0), c + Vector2(arm, 0.0), col, 2.2, true)
		draw_line(c - Vector2(0.0, arm), c + Vector2(0.0, arm), col, 2.2, true)


# ================= 内部类：星空背景 =================

class _Backdrop extends Control:
	## 深色星空背景 + 斜向纹理 + 底部光晕星点（静态种子，draw 稳定）

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var s := size
		if s.x <= 0.0 or s.y <= 0.0:
			return
		draw_rect(Rect2(Vector2.ZERO, s), Color("0b1120"))
		draw_rect(Rect2(0.0, 0.0, s.x, s.y * 0.55), Color(0.055, 0.08, 0.16))
		# 斜切亮面
		draw_colored_polygon(PackedVector2Array([
			Vector2(s.x * 0.52, 0.0), Vector2(s.x * 0.78, 0.0),
			Vector2(s.x * 0.38, s.y), Vector2(s.x * 0.12, s.y),
		]), Color(1, 1, 1, 0.018))
		# 平行斜线纹理
		for i in 9:
			var x0 := s.x * (0.42 + i * 0.068)
			draw_line(Vector2(x0, 0.0), Vector2(x0 - s.y * 0.42, s.y), Color(1, 1, 1, 0.03), 1.0)
		# 底部光晕
		draw_circle(Vector2(s.x * 0.5, s.y * 1.08), s.x * 0.30, Color(0.35, 0.4, 0.9, 0.05))
		draw_circle(Vector2(s.x * 0.5, s.y * 1.02), s.x * 0.16, Color(0.4, 0.45, 0.95, 0.05))
		# 星点（固定种子）
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 60:
			var p := Vector2(rng.randf() * s.x, s.y * (0.45 + 0.55 * rng.randf()))
			var cc := Color(0.6, 0.65, 1.0) if rng.randf() < 0.65 else Color(0.9, 0.9, 1.0)
			draw_circle(p, 0.7 + rng.randf() * 1.7, Color(cc.r, cc.g, cc.b, 0.08 + rng.randf() * 0.3))
