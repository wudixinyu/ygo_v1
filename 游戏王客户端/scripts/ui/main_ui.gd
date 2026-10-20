extends Control
## 游戏王客户端主界面：登录 → 大厅 → 房间（三页面切换）
## 全局背景：等待阶段主题（青眼白龙）；对战中场地视图切换为决斗场地（my_field.set_dueling）

const WAIT_BG_TEX := preload("res://assets/wait_bg.jpg")   # 青眼白龙等待背景（登录/大厅/房间等待）

var page := "login"

# 登录页
var login_page: Control
var nick_edit: LineEdit
var addr_edit: LineEdit
var login_status: Label
var login_btn: Button
var pending_nick := ""

# 大厅页
var lobby_page: Control
var lobby_user_label: Label
var lobby_server_label: Label
var lobby_room_box: VBoxContainer
var lobby_room_count: Label
var create_name_edit: LineEdit
var lobby_hint: Label

# 房间页
var room_page: Control
var room_title: Label
var room_badge_panel: PanelContainer
var room_badge: Label
var room_server_label: Label
var enemy_panel: EnemyFieldView
var my_field: MyFieldView
var ready_btn: Button
var pack_select: OptionButton     # 我的卡包：对战用牌组来源选择
var _pack_option_ids: Array = []  # 与下拉项平行的卡包 id 列表（"" = 默认卡组）
var my_pack_id := ""              # 当前已上传给服务端的卡包选择
var room_log: RichTextLabel
var room_hint: Label
var room_side_box: VBoxContainer   # 右侧栏（准备/提示/动态，收起为右下角按钮，点击展开）
var room_side_wrap: HBoxContainer  # 右侧栏容器（含 room_side_box，展开时占右列宽度）
var room_side_btn: Button          # 右下角固定按钮（展开/收起右侧栏）
# 对战操作按钮在 my_field 右下角（结束回合 / 查看卡组），经信号回调到这里
var _card_list_layer: Control = null   # 卡片列表停靠面板（卡组/墓地/额外卡组，打开时非空）

# 通用
var toast_box: PanelContainer
var toast_label: Label
var _toast_tween: Tween

# 观战
var watch_page: WatchPage
var watching_id := ""
var watching_name := ""

# 卡包
var card_db: CardDB
var pack_db: PackDB
var pack_page: PackPage
var card_manager: CardManagerPage

var my_ready := false
var current_room := {}
var _side_collapsed := true       # 右侧栏是否已收起（默认收起：点击右下角按钮展开）

# 自动化测试
var auto_addr := ""
var auto_watch := false        # 自测参数 --auto-watch：登录后自动观战第一个房间
var auto_collapse_side := false # 自测参数 --collapse-side：进入房间后自动收起右侧栏
var preview_demo := false       # 自测参数 --preview-demo：进入房间后自动双击卡牌触发详情放大
var _preview_demo_tries := 0
var demo_packs := false         # 自测参数 --packs-demo：直接打开卡包页面
var demo_cards := false         # 自测参数 --cards-demo：打开第一个卡包的卡片管理页（空态）
var demo_build := false         # 自测参数 --cards-demo-build：打开后延迟自动构筑（验收牌组渲染）
var demo_select := false        # 自测参数 --cards-demo-select：打开后选中第一张卡（验收左侧详情面板）
var auto_join := false          # 自测参数 --auto-join：登录后自动加入第一个可加入房间（真人对战联调）
var auto_duel := false          # 自测参数 --auto-duel：对战中自动操作（召唤 / 攻击 / 结束回合）
var duel_ui_demo := false       # 自测参数 --duel-ui-demo：用合成点击走 UI 交互链路自动对战
var list_demo_kind := ""        # 自测参数 --list-demo=deck|grave|extra（兼容 --deck-view-demo）：对战中自动打开对应列表弹窗（截图验收）
var hand_demo := 0              # 自测参数 --hand-demo=N：用 N 张假手牌验证手牌区布局与滚动
var _deck_demo_done := false
var _hand_demo_running := false
var _auto_joined := false
var _auto_duel_running := false
var _duel_ui_demo_running := false
var test_duration := 0.0
var screenshot_delay := 0.0   # 自测参数 --screenshot=秒：延迟截图后自动退出
var _start_time := 0.0


func _ready() -> void:
	get_window().title = "游戏王客户端 · 联机对战"
	get_window().min_size = Vector2i(1024, 680)
	_start_time = Time.get_unix_time_from_system()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--auto-test="):
			auto_addr = a.trim_prefix("--auto-test=")
		elif a == "--auto-watch":
			auto_watch = true
		elif a == "--collapse-side":
			auto_collapse_side = true
		elif a == "--preview-demo":
			preview_demo = true
		elif a == "--packs-demo":
			demo_packs = true
		elif a == "--cards-demo":
			demo_cards = true
		elif a == "--cards-demo-build":
			demo_cards = true
			demo_build = true
		elif a == "--cards-demo-select":
			demo_cards = true
			demo_select = true
		elif a == "--auto-join":
			auto_join = true
		elif a == "--auto-duel":
			auto_duel = true
		elif a == "--duel-ui-demo":
			duel_ui_demo = true
		elif a == "--deck-view-demo":
			list_demo_kind = "deck"
		elif a.begins_with("--list-demo="):
			list_demo_kind = a.trim_prefix("--list-demo=")
		elif a.begins_with("--hand-demo="):
			hand_demo = int(a.trim_prefix("--hand-demo="))
		elif a.begins_with("--test-duration="):
			test_duration = float(a.trim_prefix("--test-duration="))
		elif a.begins_with("--screenshot="):
			screenshot_delay = float(a.trim_prefix("--screenshot="))
	_build_ui()
	ClientNet.connected.connect(_on_connected)
	ClientNet.connect_failed.connect(_on_connect_failed)
	ClientNet.login_ok.connect(_on_login_ok)
	ClientNet.room_list_received.connect(_on_room_list)
	ClientNet.room_joined.connect(_on_room_joined)
	ClientNet.room_update.connect(_on_room_update)
	ClientNet.room_closed.connect(_on_room_closed)
	ClientNet.watch_snapshot_received.connect(_on_watch_snapshot)
	ClientNet.watch_ended.connect(_on_watch_ended)
	ClientNet.kicked.connect(_on_kicked)
	ClientNet.net_error.connect(_on_net_error)
	ClientNet.broadcast_received.connect(_on_broadcast)
	ClientNet.disconnected.connect(_on_disconnected)
	_show_page("login")
	# 卡包/卡片管理自测入口（与服务端同名参数）
	if demo_packs:
		_open_pack_page()
	if demo_cards:
		# 走真实链路：打开卡包页 → 模拟点击第 1 个卡包格（pressed → pack_opened → 卡片管理页）
		_open_pack_page()
		pack_page.simulate_click_pack(0)
		if demo_build:
			get_tree().create_timer(1.2).timeout.connect(func() -> void: card_manager.demo_auto_build())
		elif demo_select:
			get_tree().create_timer(0.8).timeout.connect(func() -> void: card_manager.demo_select_first())
	if auto_addr != "":
		addr_edit.text = auto_addr
		nick_edit.text = "测试客户端"
		get_tree().create_timer(1.0).timeout.connect(_do_login)
	if screenshot_delay > 0.0:
		get_tree().create_timer(screenshot_delay).timeout.connect(_take_screenshot)


func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("user://screenshot.png")
	print("[截图] 结果=%d 文件=%s" % [err, ProjectSettings.globalize_path("user://screenshot.png")])
	get_tree().quit()


func _process(_delta: float) -> void:
	if test_duration > 0.0 and Time.get_unix_time_from_system() - _start_time > test_duration:
		print("[自测] 到达测试时长，自动退出")
		get_tree().quit()


# ================= 界面构建 =================

func _build_ui() -> void:
	# 全局背景：青眼白龙（cover 铺满 + 暗化遮罩保证前景可读）；房间页对战区会覆盖在其上
	var bg := TextureRect.new()
	bg.texture = WAIT_BG_TEX
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var bg_dim := ColorRect.new()
	bg_dim.color = Color(0.02, 0.02, 0.05, 0.5)
	bg_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_dim)

	_build_login_page()
	_build_lobby_page()
	_build_room_page()
	_build_toast()

	# 观战页（独立全屏覆盖层，显示时盖住登录/大厅/房间页）
	watch_page = preload("res://scenes/watch_page.tscn").instantiate()
	add_child(watch_page)
	watch_page.exit_requested.connect(_do_stop_watch)
	# 注入客户端卡片库：观战页/我方场地/对手场地/卡包与管理页共用
	# （解析 assets/cards.json 提供卡名/类型/效果；卡图按需读 assets/cards_raw）
	card_db = CardDB.new()
	card_db.load_all()
	watch_page.db = card_db
	my_field.db = card_db
	enemy_panel.db = card_db

	# 卡包数据库（预置 6 卡包 + 可新建，持久化 user://packs.json）
	pack_db = PackDB.new()
	pack_db.setup(card_db)

	# 卡包页面（点击卡包 → 卡片管理）
	pack_page = preload("res://scenes/pack_page.tscn").instantiate()
	pack_page.card_db = card_db
	pack_page.pack_db = pack_db
	add_child(pack_page)
	pack_page.pack_opened.connect(_open_pack_manager)

	# 卡片管理页面（牌组编辑）
	card_manager = preload("res://scenes/card_manager_page.tscn").instantiate()
	card_manager.card_db = card_db
	card_manager.pack_db = pack_db
	add_child(card_manager)
	card_manager.back_requested.connect(_close_pack_manager)


func _build_login_page() -> void:
	login_page = Control.new()
	login_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(login_page)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	login_page.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 0)
	panel.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG_PANEL, UITheme.ACCENT_DEEP, 16, 1, 30))
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var t1 := UITheme.text_label("游戏王 · 联机对战", UITheme.GOLD, 26)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t1)
	var t2 := UITheme.text_label("XINYU TCG ARENA · ONLINE", UITheme.TEXT_DIM, 12, true)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t2)

	var sep := HSeparator.new()
	v.add_child(sep)

	v.add_child(UITheme.text_label("昵称", UITheme.TEXT_DIM, 12, true))
	nick_edit = LineEdit.new()
	nick_edit.placeholder_text = "输入你的昵称"
	nick_edit.text = "决斗者%d" % (randi() % 9000 + 1000)
	nick_edit.custom_minimum_size = Vector2(0, 40)
	nick_edit.max_length = 16
	UITheme.style_line_edit(nick_edit)
	nick_edit.text_submitted.connect(func(_t): _do_login())
	v.add_child(nick_edit)

	v.add_child(UITheme.text_label("服务器地址（IP:端口）", UITheme.TEXT_DIM, 12, true))
	addr_edit = LineEdit.new()
	addr_edit.text = "127.0.0.1:9000"
	addr_edit.custom_minimum_size = Vector2(0, 40)
	UITheme.style_line_edit(addr_edit)
	addr_edit.text_submitted.connect(func(_t): _do_login())
	v.add_child(addr_edit)

	login_btn = Button.new()
	login_btn.text = "进入大厅"
	login_btn.custom_minimum_size = Vector2(0, 44)
	UITheme.style_button(login_btn, true)
	login_btn.pressed.connect(_do_login)
	v.add_child(login_btn)

	login_status = UITheme.text_label("", UITheme.RED, 12, true)
	login_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	login_status.custom_minimum_size = Vector2(0, 18)
	v.add_child(login_status)


func _build_lobby_page() -> void:
	lobby_page = Control.new()
	lobby_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(lobby_page)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	lobby_page.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# 顶栏
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG_PANEL, UITheme.BORDER, 12, 1, 12))
	root.add_child(top)
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 12)
	top.add_child(top_h)
	top_h.add_child(UITheme.text_label("游戏王 · 联机对战", UITheme.GOLD, 17))
	# 卡包管理入口（标题右侧）
	var pack_btn := Button.new()
	pack_btn.text = "卡包管理"
	UITheme.style_button(pack_btn, true)
	pack_btn.pressed.connect(_open_pack_page)
	top_h.add_child(pack_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_h.add_child(sp)
	lobby_user_label = UITheme.text_label("玩家：—", UITheme.TEXT, 13)
	top_h.add_child(lobby_user_label)
	lobby_server_label = UITheme.text_label("服务器：—", UITheme.TEXT_DIM, 12, true)
	top_h.add_child(lobby_server_label)
	var logout_btn := Button.new()
	logout_btn.text = "退出登录"
	UITheme.style_button(logout_btn)
	logout_btn.pressed.connect(_do_logout)
	top_h.add_child(logout_btn)

	# 主体
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# 左：房间列表
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", UITheme.panel_box())
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	lobby_room_count = UITheme.text_label("房间列表（0）", UITheme.TEXT, 14)
	lv.add_child(lobby_room_count)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(scroll)
	lobby_room_box = VBoxContainer.new()
	lobby_room_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_room_box.add_theme_constant_override("separation", 6)
	scroll.add_child(lobby_room_box)

	# 右：创建房间
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.add_theme_stylebox_override("panel", UITheme.panel_box())
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	rv.add_child(UITheme.text_label("创建房间", UITheme.TEXT, 14))
	rv.add_child(UITheme.text_label("创建后等待对手加入，双方准备后开始决斗", UITheme.TEXT_DIM, 12, true))
	create_name_edit = LineEdit.new()
	create_name_edit.placeholder_text = "房间名（留空自动生成）"
	create_name_edit.custom_minimum_size = Vector2(0, 40)
	create_name_edit.max_length = 20
	UITheme.style_line_edit(create_name_edit)
	create_name_edit.text_submitted.connect(func(_t): _do_create_room())
	rv.add_child(create_name_edit)
	var create_btn := Button.new()
	create_btn.text = "创建房间"
	create_btn.custom_minimum_size = Vector2(0, 42)
	UITheme.style_button(create_btn, true)
	create_btn.pressed.connect(_do_create_room)
	rv.add_child(create_btn)
	lobby_hint = UITheme.text_label("", UITheme.YELLOW, 12, true)
	lobby_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(lobby_hint)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(sp2)
	rv.add_child(UITheme.text_label("提示：同一服务器上的玩家才能互相加入房间", UITheme.TEXT_DIM, 12, true))


func _build_room_page() -> void:
	room_page = Control.new()
	room_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(room_page)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	room_page.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# 顶栏
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG_PANEL, UITheme.BORDER, 12, 1, 12))
	root.add_child(top)
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 12)
	top.add_child(top_h)
	var leave_btn := Button.new()
	leave_btn.text = "← 离开房间"
	UITheme.style_button(leave_btn)
	leave_btn.pressed.connect(_do_leave)
	top_h.add_child(leave_btn)
	room_title = UITheme.text_label("房间", UITheme.TEXT, 17)
	top_h.add_child(room_title)
	room_badge_panel = PanelContainer.new()
	room_badge_panel.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG_PANEL_LIGHT, UITheme.BORDER, 6, 1, 5))
	top_h.add_child(room_badge_panel)
	room_badge = UITheme.text_label("等待中", UITheme.BLUE, 12)
	room_badge_panel.add_child(room_badge)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_h.add_child(sp)
	room_server_label = UITheme.text_label("", UITheme.TEXT_DIM, 12, true)
	top_h.add_child(room_server_label)

	# 对战区：左侧「对手场地（上）+ 我方场地（下）」+ 右侧房间栏（准备/操作/动态）
	var arena := PanelContainer.new()
	arena.add_theme_stylebox_override("panel", UITheme.panel_box())
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(arena)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	arena.add_child(body)

	# 左侧场地区：上方对手场地（显示对手怪兽，点击作为攻击目标）+ 下方我方场地（出牌操作）
	var field_col := VBoxContainer.new()
	field_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_col.add_theme_constant_override("separation", 8)
	body.add_child(field_col)

	enemy_panel = preload("res://scenes/enemy_panel.tscn").instantiate()
	enemy_panel.custom_minimum_size = Vector2(0, 168)
	field_col.add_child(enemy_panel)
	enemy_panel.attack_drop.connect(_on_attack_drop)
	enemy_panel.card_detail_requested.connect(_on_enemy_card_detail)

	my_field = preload("res://scenes/my_field.tscn").instantiate()
	my_field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field_col.add_child(my_field)
	my_field.summon_drop.connect(_on_summon_drop)
	my_field.circle_clicked.connect(_on_circle_clicked)
	# 对战操作按钮位于我方场地右下角：结束回合（查看列表走场地右侧三个圆区）
	my_field.end_turn_requested.connect(_on_end_turn)

	# 右侧栏：准备按钮 / 提示 / 房间动态（默认收起；点击右下角固定按钮展开，展开时占右列宽度）
	var side_wrap := HBoxContainer.new()
	side_wrap.add_theme_constant_override("separation", 8)
	side_wrap.visible = false
	room_side_wrap = side_wrap
	body.add_child(side_wrap)

	room_side_box = VBoxContainer.new()
	room_side_box.custom_minimum_size = Vector2(316, 0)
	room_side_box.add_theme_constant_override("separation", 10)
	side_wrap.add_child(room_side_box)

	# 我的卡包：选择开战后使用的牌组来源（进房自动上传，切换即重新上传）
	room_side_box.add_child(UITheme.text_label("我的卡包（开战使用的牌组）", UITheme.TEXT_DIM, 12, true))
	pack_select = OptionButton.new()
	pack_select.custom_minimum_size = Vector2(0, 42)
	pack_select.add_theme_font_size_override("font_size", 14)
	pack_select.add_theme_color_override("font_color", UITheme.TEXT)
	pack_select.add_theme_color_override("font_hover_color", Color.WHITE)
	pack_select.add_theme_color_override("font_pressed_color", Color.WHITE)
	pack_select.add_theme_stylebox_override("normal", UITheme.sb(Color("111122"), UITheme.BORDER, 7, 1, 8))
	pack_select.add_theme_stylebox_override("hover", UITheme.sb(Color("111122"), UITheme.ACCENT, 7, 1, 8))
	pack_select.add_theme_stylebox_override("pressed", UITheme.sb(Color("111122"), UITheme.ACCENT, 7, 1, 8))
	pack_select.add_theme_stylebox_override("disabled", UITheme.sb(Color("16161f"), UITheme.BORDER, 7, 1, 8))
	pack_select.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var pop := pack_select.get_popup()
	pop.add_theme_stylebox_override("panel", UITheme.sb(Color("1c1c2e"), UITheme.BORDER, 7, 1, 6))
	pop.add_theme_color_override("font_color", UITheme.TEXT)
	pop.add_theme_font_size_override("font_size", 13)
	pack_select.item_selected.connect(_on_pack_selected)
	room_side_box.add_child(pack_select)

	ready_btn = Button.new()
	ready_btn.text = "准备"
	ready_btn.custom_minimum_size = Vector2(0, 44)
	UITheme.style_button(ready_btn, true)
	ready_btn.pressed.connect(_do_toggle_ready)
	room_side_box.add_child(ready_btn)

	room_hint = UITheme.text_label("等待对手加入…", UITheme.TEXT_DIM, 12, true)
	room_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room_side_box.add_child(room_hint)

	room_side_box.add_child(UITheme.text_label("房间动态", UITheme.TEXT_DIM, 12, true))
	# 日志：套一层普通 Control 外框，避免 RichTextLabel 的最小宽度撑宽右栏
	var log_holder := Control.new()
	log_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_holder.clip_contents = true
	room_side_box.add_child(log_holder)
	room_log = RichTextLabel.new()
	room_log.bbcode_enabled = true
	room_log.scroll_following = true
	room_log.set_anchors_preset(Control.PRESET_FULL_RECT)
	room_log.add_theme_font_size_override("normal_font_size", 13)
	room_log.add_theme_stylebox_override("normal", UITheme.sb(Color("111122"), UITheme.BORDER, 8, 1, 8))
	log_holder.add_child(room_log)

	# 右下角固定按钮：展开 / 收起右侧栏（不再占用右上角把手，收起时场地占满）
	room_side_btn = Button.new()
	room_side_btn.text = "房间动态"
	room_side_btn.custom_minimum_size = Vector2(120, 40)
	room_side_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	room_side_btn.offset_left = -134
	room_side_btn.offset_top = -192
	room_side_btn.offset_right = -14
	room_side_btn.offset_bottom = -152
	room_side_btn.tooltip_text = "展开右侧栏（卡包 / 准备 / 房间动态）"
	room_side_btn.add_theme_font_size_override("font_size", 13)
	room_side_btn.pressed.connect(_toggle_side_box)
	room_page.add_child(room_side_btn)


func _build_toast() -> void:
	toast_box = PanelContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_box.position = Vector2(0, 24)
	toast_box.visible = false
	toast_box.add_theme_stylebox_override("panel", UITheme.sb(Color("2a2450"), UITheme.ACCENT, 10, 1, 12))
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_box)
	toast_label = UITheme.text_label("", UITheme.TEXT, 13)
	toast_box.add_child(toast_label)


# ================= 页面切换 =================

func _show_page(p: String) -> void:
	page = p
	login_page.visible = p == "login"
	lobby_page.visible = p == "lobby"
	room_page.visible = p == "room"


func _toast(text: String) -> void:
	toast_label.text = text
	toast_box.visible = true
	toast_box.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(toast_box, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func(): toast_box.visible = false)


# ================= 用户操作 =================

func _do_login() -> void:
	var nick := nick_edit.text.strip_edges()
	if nick == "":
		login_status.text = "请输入昵称"
		return
	var addr := addr_edit.text.strip_edges()
	var idx := addr.rfind(":")
	if idx <= 0:
		login_status.text = "地址格式应为 IP:端口，如 127.0.0.1:9000"
		return
	var host := addr.substr(0, idx)
	var port := int(addr.substr(idx + 1))
	if port <= 0 or port > 65535:
		login_status.text = "端口号无效"
		return
	pending_nick = nick
	login_btn.disabled = true
	login_status.text = "正在连接 %s …" % addr
	login_status.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	ClientNet.connect_to(host, port)


func _do_create_room() -> void:
	if page != "lobby":
		return
	var name := create_name_edit.text.strip_edges()
	ClientNet.send("create_room", {"name": name, "max_players": 2})


func _do_join_room(room_id: String) -> void:
	ClientNet.send("join_room", {"room_id": room_id})


# ================= 观战 =================

func _do_watch_room(room_id: String, room_name: String) -> void:
	if watching_id == room_id and watch_page.visible:
		return
	watching_id = room_id
	watching_name = room_name
	ClientNet.send("watch_room", {"room_id": room_id})
	watch_page.open(room_name, "服务器 %s" % ClientNet.my_server)


func _do_stop_watch() -> void:
	if watching_id != "":
		ClientNet.send("unwatch_room", {"room_id": watching_id})
	watching_id = ""
	watching_name = ""
	watch_page.close_view()


# ================= 卡包 / 卡片管理 =================

func _open_pack_page() -> void:
	if pack_page == null:
		return
	watch_page.close_view()
	card_manager.visible = false
	pack_page.open()


func _open_pack_manager(pack_id: String) -> void:
	pack_page.visible = false
	card_manager.open(pack_id)
	print("[客户端] 打开卡片管理：编辑卡包「%s」的牌组" % card_manager.name_text())


func _close_pack_manager() -> void:
	card_manager.visible = false
	pack_page.open()


func _on_watch_snapshot(room: Dictionary) -> void:
	if watch_page.visible:
		watch_page.update_view(room)


func _on_watch_ended(reason: String) -> void:
	watching_id = ""
	watching_name = ""
	watch_page.close_view()
	_toast("观战已结束（%s）" % reason)


func _do_toggle_ready() -> void:
	ClientNet.send("set_ready", {"ready": not my_ready})


# ================= 真人对战操作（召唤 / 攻击 / 结束回合） =================

## 从房间数据里取我方 / 对手的玩家条目
func _player_of(room: Dictionary, want_mine: bool) -> Dictionary:
	var plist = room.get("players", [])
	if not (plist is Array):
		return {}
	for p in plist:
		if p is Dictionary and (str(p.get("id", "")) == ClientNet.my_id) == want_mine:
			return p
	return {}


## 当前是否轮到我操作（对战中且回合属于我）
func _is_my_turn() -> bool:
	return str(current_room.get("state", "")) == "dueling" \
		and str(current_room.get("active_pid", "")) == ClientNet.my_id


## 对手场上怪兽列表（攻击目标）
func _enemy_field_list() -> Array:
	var e := _player_of(current_room, false)
	var fc = e.get("field_cards", [])
	return fc if fc is Array else []


## 本回合已攻击过的怪兽卡 id 列表
## （注意：房间数据经 JSON 传输，数字都是 float；统一转 int 再比较，否则 has() 恒为 false）
func _attacked_ids() -> Array:
	var out: Array = []
	for v in current_room.get("attacked", []):
		out.append(int(v))
	return out


## 刷新对战操作面板（位于我方场地右下角）：按房间状态刷新提示与按钮可用态
func _update_duel_ui() -> void:
	var state := str(current_room.get("state", "waiting"))
	if state != "dueling" and enemy_panel != null:
		enemy_panel.set_targeting(false)
	if my_field == null:
		return
	my_field.update_duel_actions({
		"state": state,
		"my_turn": _is_my_turn(),
		"summon_used": bool(current_room.get("summon_used", false)),
		"spell_used": bool(current_room.get("spell_used", false)),
		"attacked": _attacked_ids(),
	})


## 对手场上怪兽列表（过滤空位 {}）
func _enemy_monsters() -> Array:
	var out: Array = []
	for f in _enemy_field_list():
		if f is Dictionary and not (f as Dictionary).is_empty():
			out.append(f)
	return out


## 我方第一个空怪兽格（0-4；无空位返回 -1）（field_cards 含空位 {}）
func _first_empty_slot(p: Dictionary) -> int:
	var fc = p.get("field_cards", [])
	var arr: Array = fc if fc is Array else []
	for i in 5:
		if i >= arr.size():
			return i
		var f = arr[i]
		if not (f is Dictionary) or (f as Dictionary).is_empty():
			return i
	return -1


## 拖动手牌怪兽到怪兽区空位 → 召唤（main_ui 校验回合 / 召唤次数 / 卡类型后上报服务端）
func _on_summon_drop(card_id: int, hand_index: int, pos: int) -> void:
	if card_id <= 0:
		return
	if str(current_room.get("state", "")) != "dueling":
		_toast("对战开始后才能出牌")
		return
	if not _is_my_turn():
		_toast("现在是对方的回合")
		return
	# 按卡类型分流校验：怪兽 = 召唤（每回合 1 次）；魔法/陷阱 = 放置魔陷区（每回合 1 次）
	var kind := ""
	if card_db != null:
		kind = str(card_db.get_card(card_id).get("kind", ""))
	if kind == "monster":
		if bool(current_room.get("summon_used", false)):
			_toast("本回合已经召唤过怪兽了")
			return
	elif kind == "spell" or kind == "trap":
		if bool(current_room.get("spell_used", false)):
			_toast("本回合已经放置过魔法 / 陷阱卡了")
			return
	elif kind != "":
		_toast("这张卡无法使用")
		return
	ClientNet.send("duel_action", {"action": "summon", "card_id": card_id, "hand_slot": hand_index, "pos": pos})


## 拖动我方怪兽到对手条 → 攻击（target = 对手怪兽 id；0 = 直接攻击玩家）
func _on_attack_drop(attacker_id: int, target_id: int) -> void:
	if attacker_id <= 0:
		return
	if not _is_my_turn():
		_toast("现在是对方的回合")
		return
	var attacked := _attacked_ids()
	if attacked.has(attacker_id):
		_toast("该怪兽本回合已经攻击过了")
		return
	if target_id <= 0 and not _enemy_monsters().is_empty():
		_toast("对方场上有怪兽，请拖到对方怪兽上攻击")
		return
	ClientNet.send("duel_action", {"action": "attack", "card_id": attacker_id, "target": target_id})
	_update_duel_ui()


## 单击对手怪兽 → 在我方详情面板展示（临时预览）
func _on_enemy_card_detail(info: Dictionary) -> void:
	my_field.show_detail_info(info)


## 「结束回合」：把操作权交给对方
func _on_end_turn() -> void:
	if not _is_my_turn():
		return
	ClientNet.send("duel_action", {"action": "end_turn"})
	_update_duel_ui()


# ================= 卡片列表面板（卡组 / 墓地 / 额外卡组，右侧停靠） =================

## 我方圆区点击（额外卡组 / 墓地 / 卡组）→ 打开对应列表弹窗
func _on_circle_clicked(kind: String) -> void:
	_open_card_list(kind)


## 自测（--list-demo）：优先合成点击对应圆区（走真实链路），未命中则直接打开弹窗
func _trigger_list_demo() -> void:
	if my_field != null and my_field.demo_click_circle(list_demo_kind):
		print("[自测] 合成点击圆区：%s" % list_demo_kind)
	else:
		print("[自测] 圆区点击未命中，直接打开弹窗：%s" % list_demo_kind)
		_open_card_list(list_demo_kind)


## 打开卡片列表面板：kind = "deck"（卡组）/ "grave"（墓地）/ "extra"（额外卡组）
## V4.2：贴右缘的整高停靠面板，单列大卡（一行一张）；点击左侧暗罩 / ✕ 按钮收起；
## 已打开时再点其他列表会先关闭再按新类型重建（切换内容）
func _open_card_list(kind: String) -> void:
	_close_card_list()
	var mine := _player_of(current_room, true)
	var title := ""
	var cards: Array = []
	var empty_text := ""
	match kind:
		"grave":
			var gc = mine.get("grave_cards", [])
			cards = gc if gc is Array else []
			title = "墓地 · %d 张" % cards.size()
			empty_text = "墓地暂无卡片（被破坏的怪兽会进入墓地）"
		"extra":
			var ec = mine.get("extra_deck", [])
			cards = ec if ec is Array else []
			title = "额外卡组 · %d 张" % cards.size()
			empty_text = "未配置额外卡组（可在卡包管理页构筑）"
		_:
			var dc = mine.get("deck_cards", [])
			cards = dc if dc is Array else []
			title = "我的卡组 · 剩余 %d 张" % cards.size()
			empty_text = "卡组暂无数据（对战开始后可查看）"

	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_card_list_layer = layer

	# 遮罩（单击关闭；列表面板叠在其上层）
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_close_card_list()
	)
	layer.add_child(dim)

	# 右侧停靠面板：贴右缘、上下左右留边、整高窄幅（约 366px）
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -378.0
	panel.offset_right = -12.0
	panel.offset_top = 12.0
	panel.offset_bottom = -12.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG_PANEL, UITheme.ACCENT_DEEP, 14, 1, 14))
	layer.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var title_l := UITheme.text_label(title, UITheme.TEXT, 15)
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(title_l)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.tooltip_text = "关闭列表"
	close_btn.custom_minimum_size = Vector2(40, 34)
	UITheme.style_button(close_btn, false, true)
	close_btn.pressed.connect(_close_card_list)
	top.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	if cards.is_empty():
		var empty := UITheme.text_label(empty_text, UITheme.TEXT_DIM, 13, true)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(0, 200)
		scroll.add_child(empty)
	else:
		var grid := GridContainer.new()
		grid.columns = 1   # 单列：一行一张，卡图放大显示
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)
		for item in cards:
			if item is Dictionary:
				grid.add_child(_deck_card_cell(item))


## 列表中的一张卡（单列大卡：卡图占满面板宽 + 名称小字）
func _deck_card_cell(info: Dictionary) -> Control:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 3)
	var tex := TextureRect.new()
	tex.custom_minimum_size = Vector2(0, 250)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var t2: Texture2D = card_db.texture_of(int(info.get("id", 0))) if card_db != null else null
	tex.texture = t2 if t2 != null else preload("res://assets/card_back.png")
	vb.add_child(tex)
	var nl := UITheme.text_label(str(info.get("name", "")), UITheme.TEXT_DIM, 12, true)
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(nl)
	return vb


## 关闭卡片列表弹窗（离房 / 断线时也会自动调用）
func _close_card_list() -> void:
	if _card_list_layer != null and is_instance_valid(_card_list_layer):
		_card_list_layer.queue_free()
	_card_list_layer = null


# ================= 自测：--auto-join / --auto-duel（真人对战联调） =================

## 自动加入大厅里第一个可加入的房间（--auto-join）
func _auto_join_tick() -> void:
	if page == "lobby" and not _auto_joined:
		ClientNet.send("list_rooms")
		get_tree().create_timer(1.2).timeout.connect(_auto_join_tick)


## 自动对战循环（--auto-duel）：轮到我时按 召唤 → 攻击 → 结束回合 的顺序自动操作
func _auto_duel_loop() -> void:
	if auto_duel and page == "room" and _is_my_turn():
		_auto_duel_step()
	get_tree().create_timer(1.6).timeout.connect(_auto_duel_loop)


func _auto_duel_step() -> void:
	var mine := _player_of(current_room, true)
	# 0) 放置魔法/陷阱：手牌里有魔陷卡且本回合未放置（放到魔陷区第一个空位）
	if not bool(current_room.get("spell_used", false)) and card_db != null:
		var hc = mine.get("hand_cards", [])
		if hc is Array:
			for i in range((hc as Array).size() - 1, -1, -1):
				var info = (hc as Array)[i]
				if info is Dictionary:
					var kid := int((info as Dictionary).get("id", 0))
					var k := str(card_db.get_card(kid).get("kind", ""))
					if k == "spell" or k == "trap":
						print("[自测] 自动对战：放置%s「%s」→ 魔陷区空位 0" % ["魔法卡" if k == "spell" else "陷阱卡", str((info as Dictionary).get("name", ""))])
						ClientNet.send("duel_action", {"action": "summon", "card_id": kid, "hand_slot": i, "pos": 0})
						return
	# 1) 召唤：手牌里有怪兽且本回合未召唤（放到第一个空位）
	if not bool(current_room.get("summon_used", false)) and card_db != null:
		var pos := _first_empty_slot(mine)
		var hc = mine.get("hand_cards", [])
		if pos >= 0 and hc is Array:
			for i in range((hc as Array).size() - 1, -1, -1):
				var info = (hc as Array)[i]
				if info is Dictionary:
					var cid := int((info as Dictionary).get("id", 0))
					if str(card_db.get_card(cid).get("kind", "")) == "monster":
						print("[自测] 自动对战：召唤「%s」→ 空位 %d" % [str((info as Dictionary).get("name", "")), pos])
						ClientNet.send("duel_action", {"action": "summon", "card_id": cid, "hand_slot": i, "pos": pos})
						return
	# 2) 攻击：找一只本回合未攻击过的我方怪兽，优先打对面怪兽，否则直接攻击
	var attacked := _attacked_ids()
	var fc = mine.get("field_cards", [])
	if fc is Array:
		for f in fc:
			if f is Dictionary and not (f as Dictionary).is_empty():
				var cid2 := int((f as Dictionary).get("id", 0))
				if cid2 > 0 and not attacked.has(cid2):
					var e_list := _enemy_monsters()
					var target := int((e_list[0] as Dictionary).get("id", 0)) if not e_list.is_empty() else 0
					print("[自测] 自动对战：攻击（%d → 目标 %d）" % [cid2, target])
					ClientNet.send("duel_action", {"action": "attack", "card_id": cid2, "target": target})
					return
	# 3) 结束回合
	print("[自测] 自动对战：结束回合")
	ClientNet.send("duel_action", {"action": "end_turn"})


## UI 拖放链路自动对战（--duel-ui-demo）：用合成鼠标事件拖动卡牌 / 点击按钮，
## 走完整交互链路（拖动 → 引擎拖放 →信号 → main_ui 校验 → 上报服务端）
func _duel_ui_demo_loop() -> void:
	if duel_ui_demo and page == "room" and _is_my_turn():
		_duel_ui_demo_step()
	get_tree().create_timer(2.0).timeout.connect(_duel_ui_demo_loop)


func _duel_ui_demo_step() -> void:
	var mine := _player_of(current_room, true)
	# 1) 拖动召唤：把手牌里的第一张怪兽拖到第一个空位
	if not bool(current_room.get("summon_used", false)) and card_db != null:
		var pos := _first_empty_slot(mine)
		var hc = mine.get("hand_cards", [])
		if pos >= 0 and hc is Array:
			for i in range((hc as Array).size() - 1, -1, -1):
				var info = (hc as Array)[i]
				if info is Dictionary and str(card_db.get_card(int((info as Dictionary).get("id", 0))).get("kind", "")) == "monster":
					var cid := int((info as Dictionary).get("id", 0))
					print("[自测] UI链路：拖动手牌召唤「%s」→ 空位 %d" % [str((info as Dictionary).get("name", "")), pos])
					my_field.demo_drag_hand_to_slot(cid, pos)
					return
	# 2) 拖动攻击：找一只未攻击过的我方怪兽，拖向对手怪兽（无怪兽则拖向对手条空白 = 直接攻击）
	var attacked := _attacked_ids()
	var fc = mine.get("field_cards", [])
	if fc is Array:
		for f in fc:
			if f is Dictionary and not (f as Dictionary).is_empty():
				var cid2 := int((f as Dictionary).get("id", 0))
				if cid2 > 0 and not attacked.has(cid2):
					var e_list := _enemy_monsters()
					var target := int((e_list[0] as Dictionary).get("id", 0)) if not e_list.is_empty() else 0
					print("[自测] UI链路：拖动怪兽 %d 攻击（目标 %s）" % [cid2, str(target) if target > 0 else "直接攻击"])
					var data = my_field.demo_make_attack_data(cid2)
					if data != null:
						enemy_panel.demo_drop_attack(data, target)
					return
	# 3) 结束回合（点右下角面板里的按钮）
	print("[自测] UI链路：点击「结束回合」按钮")
	my_field.end_turn_btn.pressed.emit()


# ================= 我的卡包（对战牌组选择） =================

## 刷新「我的卡包」下拉：默认项 + 所有已构筑牌组的卡包
## keep_id 不为空时尝试保持该选择；否则默认选中第一个有牌组的卡包
func _refresh_pack_select(keep_id := "") -> void:
	if pack_select == null or pack_db == null:
		return
	pack_select.clear()
	_pack_option_ids = []
	pack_select.add_item("默认卡组（随机 40 张）")
	_pack_option_ids.append("")
	var want := 0   # 默认选第一项；有已构筑卡包时改为第一个卡包
	for p in pack_db.packs:
		var deck: Array = p.get("deck", [])
		var extra: Array = p.get("extra", [])
		if deck.is_empty() and extra.is_empty():
			continue  # 未构筑的卡包不列出（选了也只能用默认卡组，容易误解）
		var pid := str(p.get("id", ""))
		pack_select.add_item("%s（%d+%d）" % [str(p.get("name", "卡包")), deck.size(), extra.size()])
		_pack_option_ids.append(pid)
		if want == 0:
			want = _pack_option_ids.size() - 1
	# 恢复上次选择（该卡包仍在列表中时优先）
	if keep_id != "":
		var ki := _pack_option_ids.find(keep_id)
		if ki > 0:
			want = ki
	pack_select.selected = want


## 当前下拉选中项对应的卡包 id（"" = 默认卡组）
func _selected_pack_id() -> String:
	if pack_select == null or pack_select.selected < 0 or pack_select.selected >= _pack_option_ids.size():
		return ""
	return str(_pack_option_ids[pack_select.selected])


## 上传当前选择的卡包牌组给服务端（进房 / 切换选择时调用）
## 服务端开战时用该牌组构建卡组；未选/牌组为空则用默认随机构筑
func _upload_pack_choice() -> void:
	if pack_select == null:
		return
	var pid := _selected_pack_id()
	my_pack_id = pid
	if pid == "":
		ClientNet.send("select_pack", {"name": "", "deck": [], "extra": []})
		return
	var p := pack_db.get_pack(pid)
	if p.is_empty():
		ClientNet.send("select_pack", {"name": "", "deck": [], "extra": []})
		return
	ClientNet.send("select_pack", {
		"name": str(p.get("name", "")),
		"deck": p.get("deck", []),
		"extra": p.get("extra", []),
	})


func _on_pack_selected(_idx: int) -> void:
	if pack_select == null or pack_select.disabled:
		return
	_upload_pack_choice()
	_toast("已选择卡包：%s" % pack_select.get_item_text(pack_select.selected))


## 收起 / 展开右侧动态栏（收起后对战区自动占满剩余宽度）
func _toggle_side_box() -> void:
	_set_side_visible(_side_collapsed)


## 显式设置右侧栏展开 / 收起（v = 是否展开；按钮固定右下角，展开时整组左移避让右栏）
func _set_side_visible(v: bool) -> void:
	_side_collapsed = not v
	room_side_wrap.visible = v
	room_side_btn.text = "收起面板" if v else "房间动态"
	room_side_btn.tooltip_text = "收起右侧栏" if v else "展开右侧栏（卡包 / 准备 / 房间动态）"
	if v:
		room_side_btn.offset_left = -464
		room_side_btn.offset_right = -344
	else:
		room_side_btn.offset_left = -134
		room_side_btn.offset_right = -14


## 自测：每秒尝试双击展示一张卡牌详情（触发左侧放大显示），持续一段时间
func _try_preview_demo() -> void:
	if not preview_demo:
		return
	if page == "room" and my_field != null:
		my_field.demo_show_detail()
	_preview_demo_tries += 1
	if _preview_demo_tries < 45:
		get_tree().create_timer(1.0).timeout.connect(_try_preview_demo)


func _do_leave() -> void:
	_close_card_list()
	ClientNet.send("leave_room")
	_show_page("lobby")


func _do_logout() -> void:
	_do_stop_watch()
	ClientNet.logout()
	login_btn.disabled = false
	login_status.text = ""
	_show_page("login")


# ================= 网络事件 =================

func _on_connected() -> void:
	login_status.text = "已连接，正在登录…"
	ClientNet.send("login", {"nickname": pending_nick})


func _on_connect_failed(message: String) -> void:
	login_btn.disabled = false
	login_status.add_theme_color_override("font_color", UITheme.RED)
	login_status.text = message


func _on_login_ok(_player_id: String, nickname: String) -> void:
	login_btn.disabled = false
	lobby_user_label.text = "玩家：%s" % nickname
	lobby_server_label.text = "服务器：%s" % ClientNet.my_server
	room_server_label.text = ClientNet.my_server
	_show_page("lobby")
	_toast("欢迎，%s！" % nickname)
	print("[客户端] 登录成功：%s @ %s" % [nickname, ClientNet.my_server])
	if auto_addr != "" and not auto_watch:
		if auto_join:
			# 联调：自动加入第一个可加入房间（不建房）
			get_tree().create_timer(1.5).timeout.connect(_auto_join_tick)
		else:
			get_tree().create_timer(1.5).timeout.connect(_auto_create_room)


func _auto_create_room() -> void:
	if page == "lobby" and auto_addr != "":
		print("[自测] 自动创建房间")
		ClientNet.send("create_room", {"name": "自动测试房间", "max_players": 2})


func _auto_ready() -> void:
	if page == "room" and auto_addr != "":
		print("[自测] 自动准备")
		ClientNet.send("set_ready", {"ready": true})


func _on_room_list(rooms: Array) -> void:
	lobby_hint.text = ""
	for c in lobby_room_box.get_children():
		c.queue_free()
	lobby_room_count.text = "房间列表（%d）" % rooms.size()
	if rooms.is_empty():
		var l := UITheme.text_label("暂无房间，可在右侧创建", UITheme.TEXT_DIM, 13, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(0, 80)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lobby_room_box.add_child(l)
		return
	lobby_room_box.add_child(_table_header())
	for r in rooms:
		if r is Dictionary:
			lobby_room_box.add_child(_row_card(_lobby_room_row(r)))
	# 联调：自动加入第一个可加入房间（--auto-join）
	if auto_join and page == "lobby" and not _auto_joined:
		for r in rooms:
			if r is Dictionary and bool(r.get("joinable", false)):
				_auto_joined = true
				print("[自测] 自动加入房间：%s" % str(r.get("name", "")))
				ClientNet.send("join_room", {"room_id": str(r.get("id", ""))})
				break
	# 自动观战：优先选择对战中房间
	if auto_watch and page == "lobby" and watching_id == "":
		var target := {}
		for r in rooms:
			if r is Dictionary and str(r.get("state", "")) == "dueling":
				target = r
				break
		if target.is_empty() and not rooms.is_empty() and rooms[0] is Dictionary:
			target = rooms[0]
		if not target.is_empty():
			print("[自测] 自动观战房间：%s" % str(target.get("name", "")))
			_do_watch_room(str(target.get("id", "")), str(target.get("name", "房间")))


func _table_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cells := [["房间名", 0.0], ["房主", 110.0], ["人数", 50.0], ["状态", 60.0], ["", 64.0], ["", 64.0]]
	for c in cells:
		var l := UITheme.text_label(str(c[0]), UITheme.TEXT_DIM, 12, true)
		if float(c[1]) <= 0.0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size = Vector2(float(c[1]), 0)
		row.add_child(l)
	return row


func _lobby_room_row(r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var n := UITheme.text_label(str(r.get("name", "房间")), UITheme.TEXT, 13)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(n)

	var o := UITheme.text_label(str(r.get("owner_name", "")), UITheme.TEXT_DIM, 12, true)
	o.custom_minimum_size = Vector2(110, 0)
	o.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(o)

	var c := UITheme.text_label("%d/%d" % [int(r.get("member_count", 0)), int(r.get("max_players", 2))], UITheme.TEXT_DIM, 12, true)
	c.custom_minimum_size = Vector2(50, 0)
	row.add_child(c)

	var state := str(r.get("state", "waiting"))
	var st := UITheme.text_label(_state_text(state), _state_color(state), 12, true)
	st.custom_minimum_size = Vector2(60, 0)
	row.add_child(st)

	var watch := Button.new()
	watch.text = "观战"
	watch.custom_minimum_size = Vector2(64, 26)
	UITheme.style_button(watch, false, true)
	var rid := str(r.get("id", ""))
	var rname := str(r.get("name", "房间"))
	watch.pressed.connect(func(): _do_watch_room(rid, rname))
	row.add_child(watch)

	var join := Button.new()
	join.text = "加入"
	join.custom_minimum_size = Vector2(64, 26)
	UITheme.style_button(join, false, true)
	join.disabled = not bool(r.get("joinable", false))
	join.pressed.connect(func(): _do_join_room(rid))
	row.add_child(join)
	return row


func _row_card(child: Control) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.sb(Color("20203a"), Color("26264a"), 7, 1, 7))
	p.add_child(child)
	return p


func _on_room_joined(room: Dictionary) -> void:
	current_room = room
	if watching_id != "":
		# 加入房间后不再是观战者
		watching_id = ""
		watching_name = ""
		watch_page.close_view()
	_show_page("room")
	_render_room(room)
	# 进房：刷新卡包选择（保持上次选择）并上传给服务端（新房间需重新上报）
	if pack_db != null:
		_refresh_pack_select(my_pack_id)
		_upload_pack_choice()
	_toast("已加入房间")
	print("[客户端] 已进入房间：%s" % str(room.get("name", "")))
	if auto_addr != "":
		get_tree().create_timer(2.0).timeout.connect(_auto_ready)
	if auto_collapse_side:
		get_tree().create_timer(1.0).timeout.connect(_set_side_visible.bind(false))
	if preview_demo:
		get_tree().create_timer(1.5).timeout.connect(_try_preview_demo)
	if auto_duel and not _auto_duel_running:
		_auto_duel_running = true
		_auto_duel_loop()
	if duel_ui_demo and not _duel_ui_demo_running:
		_duel_ui_demo_running = true
		_duel_ui_demo_loop()
	if hand_demo > 0 and not _hand_demo_running:
		_hand_demo_running = true
		_hand_demo_loop()


## 自测（--hand-demo=N）：周期性用假手牌填充手牌区（对抗 room_update 覆盖），截图验证多张布局
func _hand_demo_loop() -> void:
	if hand_demo > 0 and page == "room":
		my_field.demo_show_fake_hand(hand_demo)
	get_tree().create_timer(0.8).timeout.connect(_hand_demo_loop)


func _on_room_update(room: Dictionary) -> void:
	current_room = room
	if page == "room":
		_render_room(room)
	# 自测：对战中自动点击圆区打开卡片列表弹窗（--list-demo=deck|grave|extra，截图验收）
	if list_demo_kind != "" and not _deck_demo_done and str(room.get("state", "")) == "dueling":
		_deck_demo_done = true
		get_tree().create_timer(2.5).timeout.connect(_trigger_list_demo)
	if auto_addr != "":
		var ps = room.get("players", [])
		var lp_txt := ""
		if ps is Array:
			for p in ps:
				if p is Dictionary:
					lp_txt += "%s(LP%s,手牌%s,准备%s) " % [str(p.get("nickname", "?")), str(p.get("lp", "-")), str(p.get("hand", "-")), str(p.get("ready", "-"))]
		print("[自测] 房间更新 state=%s turn=%s | %s" % [str(room.get("state", "?")), str(room.get("turn", "?")), lp_txt])


func _render_room(room: Dictionary) -> void:
	room_title.text = str(room.get("name", "房间"))
	var state := str(room.get("state", "waiting"))
	_set_badge(_state_text(state), _state_color(state))

	var plist = room.get("players", [])
	var ps: Array = plist if plist is Array else []
	var mine := _player_of(room, true)
	var enemy := _player_of(room, false)
	my_ready = bool(mine.get("ready", false))

	# 我方场地 / 对手场地（背景随房间状态切换：等待=青眼白龙，对战=决斗场地）
	my_field.set_dueling(state == "dueling")
	my_field.update_view(mine, room)
	enemy_panel.update_view(enemy, room)

	# 卡包选择仅等待阶段可改（对战中锁定）
	if pack_select != null:
		pack_select.disabled = state != "waiting"

	if state == "dueling":
		ready_btn.visible = false
		room_hint.text = "对战进行中，双方轮流操作"
	elif state == "finished":
		ready_btn.visible = false
		room_hint.text = "本场决斗已结束"
	else:
		ready_btn.visible = true
		ready_btn.text = "取消准备" if my_ready else "准备"
		if ps.size() >= 2:
			room_hint.text = "双方均准备后自动开始决斗"
		else:
			room_hint.text = "等待对手加入…"

	# 对战操作区（提示 / 直接攻击 / 结束回合）状态刷新
	_update_duel_ui()

	var logs = room.get("logs", [])
	var txt := ""
	if logs is Array:
		for line in logs:
			txt += "[color=#%s]· %s[/color]\n" % [UITheme.TEXT.to_html(false), str(line)]
	room_log.text = txt


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
	room_badge.text = text
	room_badge.add_theme_color_override("font_color", color)
	room_badge_panel.add_theme_stylebox_override("panel", UITheme.sb(color.darkened(0.75), color.darkened(0.25), 6, 1, 5))


func _on_room_closed(reason: String) -> void:
	_close_card_list()
	_toast("房间已关闭（%s）" % reason)
	_show_page("lobby")
	lobby_hint.text = "房间已关闭：%s" % reason


func _on_kicked(reason: String) -> void:
	_do_stop_watch()
	_close_card_list()
	_toast("你已被移出服务器（%s）" % reason)
	login_btn.disabled = false
	_show_page("login")
	login_status.add_theme_color_override("font_color", UITheme.RED)
	login_status.text = "你已被管理员移出服务器"


func _on_net_error(message: String) -> void:
	if watching_id != "":
		# 观战请求失败（房间不存在等）→ 退出观战页
		_do_stop_watch()
	if page == "lobby":
		lobby_hint.text = message
	else:
		_toast(message)


func _on_broadcast(message: String) -> void:
	_toast("【主服务公告】%s" % message)


func _on_disconnected(reason: String) -> void:
	_do_stop_watch()
	_close_card_list()
	_toast(reason)
	login_btn.disabled = false
	login_status.add_theme_color_override("font_color", UITheme.RED)
	login_status.text = reason
	_show_page("login")
