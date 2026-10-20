class_name CardManagerPage
extends Control
## 卡片管理页面（客户端 · 全屏覆盖）
## 布局：左＝卡盒装饰条 / 中＝牌组编辑区（主牌组 + 额外牌组）/ 右＝卡片列表（搜索 · 筛选 · 排序 · 网格 · 分页）
## 数据：PackDB 卡包（卡片池 + 编辑中的牌组）；每次变更实时保存到 user://packs.json
## 交互：左键点列表卡片加入牌组（同名最多 3 张，凑够 40 张主牌组）/ 右键移除 / 点牌组区卡片移出
## —— 自服务端同步（2026-10-16 快照 · 含详情面板放大）；后续服务端改动需手动再同步

signal back_requested

const POOL_COLS := 5
const POOL_GAP := 5.0
const PAGE_SIZE := 200        # 每页固定显示 200 张卡片（全卡库分页）

var card_db: CardDB = null
var pack_db: PackDB = null

var _pack: Dictionary = {}
var _deck: Array = []      # 主牌组（id 列表，可重复）
var _extra: Array = []     # 额外牌组
var _pool: Array = []      # 卡包卡片池

var _filter_text := ""
var _filter_mode := 0      # 0=全部 1=怪兽 2=魔法陷阱
var _sort_mode := 0        # 0=默认 1=攻击力 2=名称
var _clear_armed := false  # 「清空」二次确认
var _selected_cid := 0     # 当前选中卡片（左侧详情显示）
var _auto_cols_demo := false   # 自测参数 --cm-cols-demo：打开后自动点一次「列数切换」（回归列数布局）
var _auto_page_demo := false   # 自测参数 --cm-page-demo：打开后自动翻到第 2 页（回归分页）
var _auto_detail_demo := false # 自测参数 --cm-detail-demo：打开后选中第一张非怪兽卡（回归左侧详情排版）
var _auto_deck_click_demo := false  # 自测参数 --cm-deck-click-demo：牌组区的卡自动「单击」（回归点击查看详情）
var _page := 0             # 卡片列表当前页（从 0 起，每页固定 PAGE_SIZE 张）
var _page_filtered: Array = []   # 过滤 + 排序后的全量卡片 id（分页数据源）
var _page_count := 1       # 总页数

var _left_name: Label
var _left_tag: Label
var _deck_icon: _DeckIcon
var _empty_holder: CenterContainer
var _detail_box: VBoxContainer
var _tex_frame: PanelContainer
var _detail_tex: TextureRect
var _detail_name: Label
var _detail_type: Label
var _detail_stats: Label
var _detail_desc: Label
var _join_btn: Button
var _remove_btn: Button
var _main_flow: HFlowContainer
var _extra_flow: HFlowContainer
var _main_hint: Label
var _extra_hint: Label
var _main_count: Label
var _extra_count: Label
var _pool_grid: GridContainer
var _pool_scroll: ScrollContainer
var _search_edit: LineEdit
var _filter_btn: Button
var _sort_btn: Button
var _clear_btn: Button
var _cols_btn: Button
var _page_prev: Button
var _page_next: Button
var _page_edit: LineEdit
var _page_label: Label
var _pool_cards := {}      # cid(int) -> MiniCard（当前页）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false   # 初始隐藏：仅由 open()/返回 控制显隐
	for a in OS.get_cmdline_user_args():
		if a == "--cm-cols-demo":
			_auto_cols_demo = true
		elif a == "--cm-page-demo":
			_auto_page_demo = true
		elif a == "--cm-detail-demo":
			_auto_detail_demo = true
		elif a == "--cm-deck-click-demo":
			_auto_deck_click_demo = true
	_build_ui()
	resized.connect(_layout_grid_cards)
	resized.connect(_fit_detail_panel)


## 打开指定卡包的卡片管理页
func open(pack_id: String) -> void:
	if pack_db == null or card_db == null:
		return
	_pack = pack_db.get_pack(pack_id)
	if _pack.is_empty():
		return
	_deck = PackDB._int_arr(_pack.get("deck", []))
	_extra = PackDB._int_arr(_pack.get("extra", []))
	_pool = PackDB._int_arr(_pack.get("cards", []))
	_filter_text = ""
	_filter_mode = 0
	_sort_mode = 0
	_selected_cid = 0
	_page = 0
	if _search_edit != null:
		_search_edit.text = ""
	_refresh_header()
	_update_cols_btn()
	_apply_filter()      # 过滤 + 排序 + 渲染第 1 页
	_rebuild_sections()
	_refresh_detail()
	visible = true
	_fit_detail_panel()
	_layout_grid_cards.call_deferred()
	if _auto_cols_demo:
		get_tree().create_timer(1.2).timeout.connect(_toggle_cols)
	if _auto_page_demo:
		get_tree().create_timer(1.2).timeout.connect(_on_page_next)
	if _auto_detail_demo:
		get_tree().create_timer(1.2).timeout.connect(demo_select_first_spell)
	if _auto_deck_click_demo:
		get_tree().create_timer(1.8).timeout.connect(_demo_click_deck_thumb)


## 自测辅助：一键自动构筑（--cards-demo 用）
func demo_auto_build() -> void:
	_on_auto_build()


## 当前卡包名（供外部日志使用）
func name_text() -> String:
	return str(_pack.get("name", ""))


# ================= 界面构建 =================

func _build_ui() -> void:
	var backdrop := _Backdrop.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 14)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	row.add_child(_build_left_strip())
	row.add_child(_build_center())
	row.add_child(_build_right())


## 左：卡片详情面板（上面卡图 / 下面详情）+ 顶部卡包名
func _build_left_strip() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)   # 详情面板加宽（原 210）：卡图与文字整体放大
	panel.add_theme_stylebox_override("panel", UITheme.sb(Color(0.045, 0.055, 0.105, 0.95), Color(0.13, 0.16, 0.28), 12, 1, 12))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	_left_name = UITheme.text_label("", UITheme.TEXT, 15)
	_left_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_left_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_left_name)
	_left_tag = UITheme.text_label("STANDARD", UITheme.TEXT_DIM, 11, true)
	_left_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_left_tag)

	# 空态：点击卡片查看详情
	_empty_holder = CenterContainer.new()
	_empty_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_empty_holder)
	var hint := UITheme.text_label("点击卡片\n查看详情", UITheme.TEXT_DIM, 14, true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_holder.add_child(hint)

	# 详情组（选中卡片后显示）
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 8)
	_detail_box.visible = false
	v.add_child(_detail_box)

	# 上面：卡图（比例 200x290，等比完整显示；高度由 _fit_detail_panel 随窗口自适应）
	_tex_frame = PanelContainer.new()
	_tex_frame.custom_minimum_size = Vector2(0, 394)
	_tex_frame.add_theme_stylebox_override("panel", UITheme.sb(Color("0d1322"), Color(0.18, 0.22, 0.36), 6, 1, 2))
	_detail_box.add_child(_tex_frame)
	_detail_tex = TextureRect.new()
	_detail_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex_frame.add_child(_detail_tex)

	# 下面：详情（名称 / 类型 / 数据 / 效果文本）
	_detail_name = UITheme.text_label("", UITheme.TEXT, 17)
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(_detail_name)
	_detail_type = UITheme.text_label("", UITheme.TEXT_DIM, 13, true)
	_detail_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_type.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(_detail_type)
	_detail_stats = UITheme.text_label("", UITheme.BLUE, 14)
	_detail_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_box.add_child(_detail_stats)

	var desc_scroll := ScrollContainer.new()
	desc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	desc_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_box.add_child(desc_scroll)
	var desc_margin := MarginContainer.new()   # 效果文本左右留出内边距，避免贴边
	desc_margin.add_theme_constant_override("margin_left", 8)
	desc_margin.add_theme_constant_override("margin_right", 8)
	desc_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_scroll.add_child(desc_margin)
	_detail_desc = Label.new()
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_desc.add_theme_font_size_override("font_size", 13)
	_detail_desc.add_theme_constant_override("line_spacing", 4)   # 行距略放宽，长文本更易读
	_detail_desc.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	desc_margin.add_child(_detail_desc)

	_join_btn = Button.new()
	UITheme.style_button(_join_btn, true)
	_join_btn.pressed.connect(func() -> void: _add_card(_selected_cid))
	_detail_box.add_child(_join_btn)
	_remove_btn = Button.new()
	UITheme.style_button(_remove_btn, false)
	_remove_btn.pressed.connect(func() -> void: _remove_one(_selected_cid))
	_detail_box.add_child(_remove_btn)

	return panel


## 中：牌组编辑区（主牌组 + 额外牌组）
func _build_center() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.45
	panel.add_theme_stylebox_override("panel", UITheme.sb(Color(0.055, 0.07, 0.12, 0.92), Color(0.16, 0.2, 0.34), 12, 1, 14))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	# 工具行：卡组图标 + 改名 | 自动构筑 ← 清空
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	v.add_child(tools)

	_deck_icon = _DeckIcon.new()
	_deck_icon.custom_minimum_size = Vector2(30, 28)
	tools.add_child(_deck_icon)

	var rename_btn := Button.new()
	rename_btn.text = "改名"
	UITheme.style_button(rename_btn, false, true)
	rename_btn.tooltip_text = "重命名当前卡包"
	rename_btn.pressed.connect(_on_rename)
	tools.add_child(rename_btn)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(sp)

	var auto_btn := Button.new()
	auto_btn.text = "自动构筑"
	UITheme.style_button(auto_btn, true)
	auto_btn.tooltip_text = "从卡包卡片池随机构筑 %d 张主牌组 + %d 张额外牌组" % [PackDB.DECK_SIZE, PackDB.EXTRA_SIZE]
	auto_btn.pressed.connect(_on_auto_build)
	tools.add_child(auto_btn)

	var back_btn := Button.new()
	back_btn.text = "←"
	back_btn.custom_minimum_size = Vector2(40, 0)
	UITheme.style_button(back_btn, false, true)
	back_btn.tooltip_text = "返回卡包"
	back_btn.pressed.connect(func() -> void: back_requested.emit())
	tools.add_child(back_btn)

	_clear_btn = Button.new()
	_clear_btn.text = "清空"
	UITheme.style_button_danger(_clear_btn)
	_clear_btn.custom_minimum_size = Vector2(52, 0)
	_clear_btn.pressed.connect(_on_clear_pressed)
	tools.add_child(_clear_btn)

	# 主牌组
	v.add_child(_build_section_head("主牌组", true))
	var main_stack := _build_section_body()
	main_stack.custom_minimum_size = Vector2(0, 150)
	main_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(main_stack)

	# 额外牌组
	v.add_child(_build_section_head("额外牌组", false))
	var extra_stack := _build_section_body()
	extra_stack.custom_minimum_size = Vector2(0, 150)
	extra_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	extra_stack.size_flags_stretch_ratio = 0.62
	v.add_child(extra_stack)

	return panel


## 区块标题行：小图标 + 「主牌组 0」
func _build_section_head(title: String, is_main: bool) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var icon := _SectionIcon.new()
	icon.custom_minimum_size = Vector2(14, 14)
	h.add_child(icon)
	var l := UITheme.text_label("%s 0" % title, UITheme.TEXT, 14)
	h.add_child(l)
	if is_main:
		_main_count = l
	else:
		_extra_count = l
	return h


## 区块主体：深色框 + 空状态居中提示 + 卡片流式列表
func _build_section_body() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.sb(Color(0.04, 0.055, 0.1, 0.8), Color(0.15, 0.19, 0.32), 10, 1, 10))

	var stack := Control.new()
	panel.add_child(stack)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)

	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	scroll.add_child(flow)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(cc)
	var hint := UITheme.text_label("可以向牌组中添加卡片", UITheme.TEXT_DIM, 14, true)
	cc.add_child(hint)

	if _main_flow == null:
		_main_flow = flow
		_main_hint = hint
	else:
		_extra_flow = flow
		_extra_hint = hint
	return panel


## 右：卡片列表面板
func _build_right() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 0)
	panel.size_flags_stretch_ratio = 1.0
	panel.add_theme_stylebox_override("panel", UITheme.sb(Color(0.05, 0.065, 0.115, 0.94), Color(0.15, 0.19, 0.32), 12, 1, 12))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	# tab 行
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	v.add_child(tabs)
	var t1 := Button.new()
	t1.text = "卡片列表"
	UITheme.style_button(t1, false, true)
	t1.add_theme_color_override("font_color", Color("101a0a"))
	t1.add_theme_color_override("font_hover_color", Color("101a0a"))
	t1.add_theme_stylebox_override("normal", UITheme.sb(Color("a8e05f"), Color("a8e05f"), 7, 1, 8))
	t1.add_theme_stylebox_override("hover", UITheme.sb(Color("b8ef70"), Color("b8ef70"), 7, 1, 8))
	t1.add_theme_stylebox_override("pressed", UITheme.sb(Color("96cc52"), Color("96cc52"), 7, 1, 8))
	tabs.add_child(t1)
	var t2 := Button.new()
	t2.text = "★"
	UITheme.style_button(t2, false, true)
	t2.tooltip_text = "收藏夹（预留）"
	tabs.add_child(t2)
	var t3 := Button.new()
	t3.text = "▦"
	UITheme.style_button(t3, false, true)
	t3.tooltip_text = "卡片图鉴（预留）"
	tabs.add_child(t3)
	var tsp := Control.new()
	tsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(tsp)

	# 搜索行
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	v.add_child(srow)
	var sbox := PanelContainer.new()
	sbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sbox.add_theme_stylebox_override("panel", UITheme.sb(Color("0e1424"), Color("1b2338"), 8, 1, 6))
	srow.add_child(sbox)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 6)
	sbox.add_child(sh)
	var sicon := _SearchIcon.new()
	sicon.custom_minimum_size = Vector2(14, 14)
	sh.add_child(sicon)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "文字搜索"
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_search_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_search_edit.add_theme_color_override("font_color", UITheme.TEXT)
	_search_edit.add_theme_color_override("font_placeholder_color", UITheme.TEXT_DIM)
	_search_edit.add_theme_color_override("caret_color", UITheme.ACCENT)
	_search_edit.add_theme_font_size_override("font_size", 13)
	_search_edit.text_changed.connect(_on_search_changed)
	sh.add_child(_search_edit)

	_cols_btn = Button.new()
	_cols_btn.text = "▦ %d列" % POOL_COLS
	_cols_btn.custom_minimum_size = Vector2(56, 0)
	UITheme.style_button(_cols_btn, false, true)
	_cols_btn.tooltip_text = "切换卡片列数（当前 %d 列，点击切换）" % POOL_COLS
	_cols_btn.pressed.connect(_toggle_cols)
	srow.add_child(_cols_btn)

	# 操作行：筛选 / 排序 / 清空
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 6)
	v.add_child(orow)
	_filter_btn = Button.new()
	_filter_btn.text = "筛选：全部"
	_filter_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(_filter_btn, false, true)
	_filter_btn.pressed.connect(_cycle_filter)
	orow.add_child(_filter_btn)
	_sort_btn = Button.new()
	_sort_btn.text = "排序：默认"
	_sort_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(_sort_btn, false, true)
	_sort_btn.pressed.connect(_cycle_sort)
	orow.add_child(_sort_btn)
	var clear_pool_btn := Button.new()
	clear_pool_btn.text = "清空牌组"
	clear_pool_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button_danger(clear_pool_btn)
	clear_pool_btn.pressed.connect(_on_clear_pressed)
	orow.add_child(clear_pool_btn)

	# 卡片网格
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_pool_scroll = scroll
	_pool_grid = GridContainer.new()
	_pool_grid.columns = POOL_COLS
	_pool_grid.add_theme_constant_override("h_separation", int(POOL_GAP))
	_pool_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_pool_grid)

	# 分页行：上一页 / [输入页码] / 总页数 / 下一页（页码可直接输入回车跳转，全库 1.4 万张分 72 页）
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 6)
	v.add_child(prow)
	_page_prev = Button.new()
	_page_prev.text = "上一页"
	_page_prev.custom_minimum_size = Vector2(62, 0)
	UITheme.style_button(_page_prev, false, true)
	_page_prev.pressed.connect(_on_page_prev)
	prow.add_child(_page_prev)
	_page_edit = LineEdit.new()
	_page_edit.custom_minimum_size = Vector2(54, 26)
	_page_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_line_edit(_page_edit)
	_page_edit.add_theme_font_size_override("font_size", 12)
	_page_edit.tooltip_text = "输入页码后回车跳转"
	_page_edit.text_submitted.connect(_on_page_jump)
	_page_edit.focus_exited.connect(func() -> void: _page_edit.text = str(_page + 1))
	prow.add_child(_page_edit)
	_page_label = UITheme.text_label("/ 1", UITheme.TEXT_DIM, 12)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(_page_label)
	_page_next = Button.new()
	_page_next.text = "下一页"
	_page_next.custom_minimum_size = Vector2(62, 0)
	UITheme.style_button(_page_next, false, true)
	_page_next.pressed.connect(_on_page_next)
	prow.add_child(_page_next)

	return panel


# ================= 刷新 =================

func _pack_color() -> Color:
	return Color(str(_pack.get("color", "6f7fd8")))


func _refresh_header() -> void:
	var nm := str(_pack.get("name", ""))
	_left_name.text = nm
	_deck_icon.accent = _pack_color()
	_deck_icon.queue_redraw()


## 右侧卡片列表：过滤 + 排序 → 分页数据源（现在为「整个卡库」的全部卡片），重算总页数并渲染当前页
func _apply_filter() -> void:
	if _pool_grid == null:
		return
	var arr: Array = []
	if _filter_mode == 0 and _filter_text == "":
		# 无筛选：直接引用全卡库 id 列表（避免每次 1.4 万次字典查询）
		arr = card_db.ids.duplicate()
	else:
		for cid in card_db.ids:
			var c := card_db.get_card(cid)
			if c.is_empty():
				continue
			var kind := str(c.get("kind", ""))
			if _filter_mode == 1 and kind != "monster":
				continue
			if _filter_mode == 2 and kind == "monster":
				continue
			if _filter_text != "" and not card_db.name_of(cid).to_lower().contains(_filter_text):
				continue
			arr.append(cid)
	if _sort_mode == 1:
		arr.sort_custom(func(a, b) -> bool:
			return int(card_db.get_card(a).get("atk", -1)) > int(card_db.get_card(b).get("atk", -1))
		)
	elif _sort_mode == 2:
		arr.sort_custom(func(a, b) -> bool: return card_db.name_of(a) < card_db.name_of(b))
	_page_filtered = arr
	_page_count = maxi(1, int(ceil(float(arr.size()) / float(_page_size()))))
	_page = clampi(_page, 0, _page_count - 1)
	_render_page()


## 每页卡片数量：固定 200 张（与列数无关）
func _page_size() -> int:
	return PAGE_SIZE


## 渲染「卡片列表」当前页（第 _page 页）并刷新分页栏
func _render_page() -> void:
	if _pool_grid == null:
		return
	for c in _pool_grid.get_children():
		_pool_grid.remove_child(c)
		c.queue_free()
	_pool_cards.clear()
	var page_size := _page_size()
	var start := _page * page_size
	var end := mini(start + page_size, _page_filtered.size())
	for i in range(start, end):
		var cid := int(_page_filtered[i])
		var m := MiniCard.new()
		_pool_grid.add_child(m)
		m.setup(card_db, cid, _count_of(cid))
		m.pressed.connect(_on_pool_click)
		m.double_pressed.connect(_on_pool_double)
		m.right_pressed.connect(_on_pool_right)
		m.set_selected(cid == _selected_cid)
		_pool_cards[cid] = m
	# 翻页/切列后回到列表顶部
	if _pool_scroll != null:
		_pool_scroll.scroll_vertical = 0
	_refresh_page_bar()
	_layout_grid_cards.call_deferred()


## 刷新分页栏：页码输入框 / 总页数 / 前后按钮可用状态
func _refresh_page_bar() -> void:
	if _page_label == null:
		return
	_page_label.text = "/ %d" % _page_count
	_page_label.tooltip_text = "共 %d 张卡片 · 每页 %d 张" % [_page_filtered.size(), PAGE_SIZE]
	if _page_edit != null and not _page_edit.has_focus():
		_page_edit.text = str(_page + 1)
	_page_prev.disabled = _page <= 0
	_page_next.disabled = _page >= _page_count - 1


## 上一页
func _on_page_prev() -> void:
	if _page > 0:
		_page -= 1
		_render_page()


## 下一页（--cm-page-demo 自测也走这里翻到第 2 页）
func _on_page_next() -> void:
	if _page < _page_count - 1:
		_page += 1
		_render_page()


## 输入页码回车跳转到指定页
func _on_page_jump(text: String) -> void:
	var n := int(text.strip_edges()) - 1
	_page = clampi(n, 0, _page_count - 1)
	_render_page()


## 详情卡图高度自适应：窗口大时用满 394（≈ 面板内宽 272 × 卡图比例 1.45），
## 窗口小时压缩卡图，保证效果文本区保底可见（最低约 240 高）
func _fit_detail_panel() -> void:
	if _tex_frame == null:
		return
	var h := clampf(size.y - 400.0, 280.0, 394.0)
	_tex_frame.custom_minimum_size = Vector2(0, h)


## 网格卡片尺寸：随面板宽度均分（卡高 ≈ 宽 × 1.45，接近卡图 200:290）
## 宽度取整（floor）：避免亚像素宽导致卡图采样发虚，同时保证网格总宽不溢出视口
func _layout_grid_cards() -> void:
	if _pool_grid == null:
		return
	var inner := _pool_grid.size.x
	if inner <= 40.0:
		return
	var cols := _pool_grid.columns
	var w := maxf(floorf((inner - POOL_GAP * (cols - 1)) / float(cols)), 40.0)
	var h := w * 1.45
	for c in _pool_grid.get_children():
		c.custom_minimum_size = Vector2(w, h)


## 中间两个牌组区块
func _rebuild_sections() -> void:
	_fill_flow(_main_flow, _deck)
	_fill_flow(_extra_flow, _extra)
	_main_hint.visible = _deck.is_empty()
	_extra_hint.visible = _extra.is_empty()
	_main_count.text = "主牌组 %d" % _deck.size()
	_extra_count.text = "额外牌组 %d" % _extra.size()


func _fill_flow(flow: HFlowContainer, arr: Array) -> void:
	for c in flow.get_children():
		flow.remove_child(c)
		c.queue_free()
	for cid in arr:
		var t := DeckThumb.new()
		flow.add_child(t)
		t.configure(card_db, cid)
		var capture_cid: int = cid   # 显式捕获当前值，避免闭包引用循环变量
		t.pressed.connect(func() -> void: _select_card(capture_cid))   # 单击牌组区卡片＝查看详情（移出用左侧「移出牌组」按钮）


# ================= 交互逻辑 =================

func _count_of(cid: int) -> int:
	return _deck.count(cid) + _extra.count(cid)


func _is_extra(cid: int) -> bool:
	var c := card_db.get_card(cid)
	var types := str(c.get("types", ""))
	var head := types.split("\n")[0] if "\n" in types else types
	return ("融合" in head) or ("同调" in head) or ("超量" in head) or ("连接" in head)


## 单击列表卡片：显示详情
func _on_pool_click(cid: int) -> void:
	_select_card(cid)


## 双击列表卡片：加入牌组（快捷）
func _on_pool_double(cid: int) -> void:
	_add_card(cid)


## 右键列表卡片：移出一张
func _on_pool_right(cid: int) -> void:
	if _deck.has(cid) or _extra.has(cid):
		_remove_one(cid)


func _add_card(cid: int) -> void:
	if cid <= 0 or _count_of(cid) >= PackDB.MAX_COPY:
		return
	if _is_extra(cid):
		_extra.append(cid)
	else:
		_deck.append(cid)
	_after_change()


func _remove_one(cid: int) -> void:
	if cid <= 0:
		return
	if _deck.has(cid):
		_deck.erase(cid)
	elif _extra.has(cid):
		_extra.erase(cid)
	else:
		return
	_after_change()


## 选中卡片 → 左侧详情区显示（并给列表卡片加选中高亮）
func _select_card(cid: int) -> void:
	_selected_cid = cid
	_refresh_detail()
	for k in _pool_cards.keys():
		(_pool_cards[k] as MiniCard).set_selected(int(k) == cid)


## 刷新左侧详情：上面卡图 / 下面详情（名称 · 类型 · 数据 · 效果文本）+ 操作按钮
func _refresh_detail() -> void:
	var has := _selected_cid > 0 and not card_db.get_card(_selected_cid).is_empty()
	_detail_box.visible = has
	_empty_holder.visible = not has
	if not has:
		return
	var c := card_db.get_card(_selected_cid)
	_detail_tex.texture = card_db.texture_of(_selected_cid)
	_detail_name.text = str(c.get("name", ""))
	# 类型行：如「[怪兽|通常] 龙/光」→「怪兽/通常 龙/光」
	var types := str(c.get("types", "")).replace("[", "").replace("]", "").replace("|", "/")
	_detail_type.text = types.split("\n")[0]
	# 数据行：仅怪兽显示 ★等级 + ATK/DEF（魔法/陷阱卡没有攻防，不显示该行）
	if str(c.get("kind", "")) == "monster":
		var level := int(c.get("level", 0))
		var atk := int(c.get("atk", -1))
		var df := int(c.get("def", -1))
		var parts: Array = []
		if level > 0:
			parts.append("★%d" % level)
		parts.append("ATK %s" % ("—" if atk < 0 else str(atk)))
		parts.append("DEF %s" % ("—" if df < 0 else str(df)))
		_detail_stats.text = "   ".join(parts)
		_detail_stats.visible = true
	else:
		_detail_stats.text = ""
		_detail_stats.visible = false
	var desc := str(c.get("desc", "")).strip_edges()
	_detail_desc.text = desc if desc != "" else "（无效果文本）"
	# 操作按钮状态
	var cnt := _count_of(_selected_cid)
	_join_btn.disabled = cnt >= PackDB.MAX_COPY
	if cnt >= PackDB.MAX_COPY:
		_join_btn.text = "已达上限（%d 张）" % PackDB.MAX_COPY
	else:
		_join_btn.text = "加入额外牌组" if _is_extra(_selected_cid) else "加入主牌组"
	_remove_btn.disabled = cnt <= 0
	_remove_btn.text = ("移出牌组（%d 张）" % cnt) if cnt > 0 else "移出牌组"


## 自测辅助：选中卡片池第一张（详情面板截图用）
func demo_select_first() -> void:
	if not _page_filtered.is_empty():
		_select_card(int(_page_filtered[0]))


## 自测辅助：选中第一张非怪兽卡（验证魔法/陷阱卡详情排版）
func demo_select_first_spell() -> void:
	for cid in _page_filtered:
		if str(card_db.get_card(int(cid)).get("kind", "")) != "monster":
			_select_card(int(cid))
			return
	if not _page_filtered.is_empty():
		_select_card(int(_page_filtered[0]))


## 自测辅助：模拟单击牌组区第一张卡（走真实信号链路 → 查看详情）
func _demo_click_deck_thumb() -> void:
	if _main_flow == null:
		return
	for c in _main_flow.get_children():
		if c is DeckThumb:
			(c as DeckThumb).pressed.emit()
			return
	# 主牌组为空时尝试额外牌组
	for c in _extra_flow.get_children():
		if c is DeckThumb:
			(c as DeckThumb).pressed.emit()
			return


## 变更后：落盘 + 刷新计数/角标/牌组区/详情按钮
func _after_change() -> void:
	pack_db.set_deck(str(_pack.get("id", "")), _deck, _extra)
	for cid in _pool_cards.keys():
		(_pool_cards[cid] as MiniCard).set_count(_count_of(cid))
	_rebuild_sections()
	_refresh_detail()


func _on_search_changed(text: String) -> void:
	_filter_text = text.strip_edges().to_lower()
	_page = 0   # 搜索条件变化：回到第 1 页
	_apply_filter()


## 切换列数（5 ↔ 4）：重排卡片尺寸并重渲染；按钮实时显示当前列数
func _toggle_cols() -> void:
	_pool_grid.columns = 4 if _pool_grid.columns == POOL_COLS else POOL_COLS
	_update_cols_btn()
	_apply_filter()   # 列数变化 → 重新渲染（每页 200 张固定，行数随列数变化）


## 刷新列数按钮文案（显示当前列数）
func _update_cols_btn() -> void:
	if _cols_btn == null or _pool_grid == null:
		return
	_cols_btn.text = "▦ %d列" % _pool_grid.columns
	_cols_btn.tooltip_text = "切换卡片列数（当前 %d 列，点击切换）" % _pool_grid.columns


func _cycle_filter() -> void:
	_filter_mode = (_filter_mode + 1) % 3
	match _filter_mode:
		0: _filter_btn.text = "筛选：全部"
		1: _filter_btn.text = "筛选：怪兽"
		2: _filter_btn.text = "筛选：魔陷"
	_page = 0   # 筛选条件变化：回到第 1 页
	_apply_filter()


func _cycle_sort() -> void:
	_sort_mode = (_sort_mode + 1) % 3
	match _sort_mode:
		0: _sort_btn.text = "排序：默认"
		1: _sort_btn.text = "排序：攻击"
		2: _sort_btn.text = "排序：名称"
	_page = 0   # 排序变化：回到第 1 页
	_apply_filter()


## 自动构筑：卡池随机 40 主牌组 + 5 额外牌组（去重、不重复）
func _on_auto_build() -> void:
	var shuffled := _pool.duplicate()
	shuffled.shuffle()
	_deck.clear()
	_extra.clear()
	for cid in shuffled:
		if _is_extra(cid):
			if _extra.size() < PackDB.EXTRA_SIZE:
				_extra.append(cid)
		elif _deck.size() < PackDB.DECK_SIZE:
			_deck.append(cid)
		if _deck.size() >= PackDB.DECK_SIZE and _extra.size() >= PackDB.EXTRA_SIZE:
			break
	_after_change()


## 清空（二次确认）
func _on_clear_pressed() -> void:
	if not _clear_armed:
		_clear_armed = true
		_clear_btn.text = "再点确认"
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			_clear_armed = false
			if is_instance_valid(_clear_btn):
				_clear_btn.text = "清空"
		)
		return
	_clear_armed = false
	_clear_btn.text = "清空"
	_deck.clear()
	_extra.clear()
	_after_change()


# ================= 改名弹窗 =================

func _on_rename() -> void:
	if _pack.is_empty():
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
	v.add_child(UITheme.text_label("重命名卡包", UITheme.TEXT, 15))

	var edit := LineEdit.new()
	edit.text = str(_pack.get("name", ""))
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
	ok.text = "确定"
	UITheme.style_button(ok, true)
	ok.pressed.connect(func() -> void:
		pack_db.rename_pack(str(_pack.get("id", "")), edit.text)
		layer.queue_free()
		_refresh_header()
	)
	btns.add_child(ok)
	edit.text_submitted.connect(func(t: String) -> void:
		pack_db.rename_pack(str(_pack.get("id", "")), t)
		layer.queue_free()
		_refresh_header()
	)
	edit.grab_focus()
	edit.select_all()


# ================= 内部类：卡片小组件 =================

class MiniCard extends Control:
	## 卡片列表小卡：卡图 + 右上稀有度角标 + 底部数量
	## 交互：单击查看详情 / 双击加入牌组 / 右键移出一张
	signal pressed(cid: int)
	signal double_pressed(cid: int)
	signal right_pressed(cid: int)
	var card_id := 0
	var tex: Texture2D = null
	var count := 0
	var rarity := "N"
	var selected := false
	var _hovered := false

	func setup(p_db: CardDB, cid: int, p_count: int) -> void:
		card_id = cid
		tex = p_db.texture_of(cid)
		count = p_count
		rarity = "R" if (cid % 9 == 0) else "N"
		custom_minimum_size = Vector2(62, 90)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "%s\n单击查看详情 · 双击加入牌组 · 右键移出" % p_db.name_of(cid)
		mouse_entered.connect(func() -> void:
			_hovered = true
			queue_redraw()
		)
		mouse_exited.connect(func() -> void:
			_hovered = false
			queue_redraw()
		)
		resized.connect(queue_redraw)
		queue_redraw()

	func set_count(n: int) -> void:
		count = n
		queue_redraw()

	func set_selected(v: bool) -> void:
		selected = v
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT:
				if e.double_click:
					double_pressed.emit(card_id)
				else:
					pressed.emit(card_id)
				accept_event()
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				right_pressed.emit(card_id)
				accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if tex != null:
			draw_texture_rect(tex, r, false)
		else:
			draw_rect(r, Color("151b2e"))
			draw_rect(r.grow(-3.0), Color("20294a"))
		# 边框：选中（金）> 悬停（亮蓝）> 默认
		if selected:
			draw_rect(r, Color(1.0, 0.83, 0.4, 0.95), false, 2.0)
		elif _hovered:
			draw_rect(r, Color(0.55, 0.75, 1.0, 0.85), false, 1.5)
		else:
			draw_rect(r, Color(0, 0, 0, 0.45), false, 1.0)
		# 稀有度角标（右上）：R = 蓝底白字 / N = 浅底深字
		var clip := Rect2(size.x - 19.0, 2.0, 17.0, 13.0)
		if clip.position.x > 2.0:
			var chip_bg := Color("2f66c8") if rarity == "R" else Color(0.92, 0.93, 0.96, 0.92)
			var chip_fg := Color.WHITE if rarity == "R" else Color("1a1d2a")
			draw_rect(clip, chip_bg)
			draw_string(get_theme_default_font(), Vector2(clip.position.x, clip.position.y + 10.0), rarity,
				HORIZONTAL_ALIGNMENT_CENTER, clip.size.x, 9, chip_fg)
		# 数量（底部中央，0 显示暗色）
		var num_col := Color(1, 1, 1, 0.96) if count > 0 else Color(0.78, 0.8, 0.92, 0.7)
		draw_string(get_theme_default_font(), Vector2(0.0, size.y - 3.0), str(count),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, num_col)


class DeckThumb extends Control:
	## 牌组区缩略卡：单击查看详情（悬停亮蓝框提示）
	signal pressed
	var tex: Texture2D = null
	var _hovered := false

	func configure(p_db: CardDB, cid: int) -> void:
		tex = p_db.texture_of(cid)
		custom_minimum_size = Vector2(54, 78)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "%s（点击查看详情）" % p_db.name_of(cid)
		mouse_entered.connect(func() -> void:
			_hovered = true
			queue_redraw()
		)
		mouse_exited.connect(func() -> void:
			_hovered = false
			queue_redraw()
		)
		resized.connect(queue_redraw)
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if tex != null:
			draw_texture_rect(tex, r, false)
		else:
			draw_rect(r, Color("1a2136"))
		draw_rect(r, Color(0.55, 0.75, 1.0, 0.9) if _hovered else Color(0, 0, 0, 0.5), false, 1.5 if _hovered else 1.0)


class _DeckIcon extends Control:
	## 卡组图标：主题色小方块 + 白色斜纹（当前卡包主题色）
	var accent := Color("c0473c")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(0.0, 3.0, size.x, maxf(0.0, size.y - 6.0))
		if r.size.x <= 1.0:
			return
		draw_style_box(UITheme.sb(accent, accent.lightened(0.3), 5, 1, 0), r)
		for i in 3:
			var x := r.position.x + r.size.x * (0.22 + 0.24 * i)
			draw_line(Vector2(x, r.position.y + 3.0), Vector2(x + 4.0, r.end.y - 3.0), Color(1, 1, 1, 0.5), 1.4)


class _SectionIcon extends Control:
	## 区块小图标：叠放的两张小卡
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_style_box(UITheme.sb(Color("2a3357"), Color("3a466f"), 2, 1, 0), Rect2(0.0, size.y * 0.25, size.x - 3.0, size.y * 0.75))
		draw_style_box(UITheme.sb(Color("3d4a7a"), Color("54639c"), 2, 1, 0), Rect2(3.0, 0.0, size.x - 3.0, size.y * 0.75))


class _SearchIcon extends Control:
	## 放大镜
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var col := UITheme.TEXT_DIM
		var c := Vector2(size.x * 0.42, size.y * 0.42)
		var rad: float = minf(size.x, size.y) * 0.32
		draw_arc(c, rad, 0.0, TAU, 20, col, 1.5, true)
		draw_line(c + Vector2(rad * 0.7, rad * 0.7), Vector2(size.x * 0.9, size.y * 0.9), col, 1.8)


class _Backdrop extends Control:
	## 深色背景 + 左侧卡盒条的暗渐变（页面级装饰）
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var s := size
		if s.x <= 0.0:
			return
		draw_rect(Rect2(Vector2.ZERO, s), Color("090d17"))
		draw_rect(Rect2(0.0, 0.0, s.x, s.y * 0.4), Color(0.05, 0.065, 0.125))
		# 左上对角亮线
		draw_line(Vector2(s.x * 0.02, s.y * 0.06), Vector2(s.x * 0.10, s.y * 0.02), Color(1, 1, 1, 0.07), 1.0)
		# 底部微光
		draw_circle(Vector2(s.x * 0.08, s.y * 1.1), s.x * 0.22, Color(0.35, 0.4, 0.9, 0.04))
