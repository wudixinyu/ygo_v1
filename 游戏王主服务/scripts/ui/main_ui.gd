extends Control
## 服务端管理界面
## 左栏：服务器控制台（状态 + 演示自测）；中栏：玩家总览 / 房间总览；底栏：事件日志；观战覆盖层

var player_list_box: VBoxContainer
var room_list_box: VBoxContainer
var player_title: Label
var room_title: Label
var center_title: Label
var log_label: RichTextLabel
var chip_status: Label
var chip_players: Label
var chip_rooms: Label
var uptime_label: Label
var watch_page: WatchPage
var pack_page: PackPage
var card_manager: CardManagerPage

var _dirty := false
var _accum := 0.0
var screenshot_delay := 0.0   # 自测参数 --screenshot=秒：延迟截图后自动退出
var auto_watch := false       # 自测参数 --watch-first：自动观战第一个创建的房间
var demo_packs := false       # 自测参数 --packs-demo：直接打开卡包页面
var demo_cards := false       # 自测参数 --cards-demo：打开第一个卡包的卡片管理页（空态）
var demo_build := false       # 自测参数 --cards-demo-build：打开后延迟自动构筑（验收牌组渲染）
var demo_select := false      # 自测参数 --cards-demo-select：打开后选中第一张卡（验收左侧详情面板）
var build_packs := false      # 自测参数 --build-packs：为所有空牌组卡包批量构筑后退出


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			screenshot_delay = float(a.trim_prefix("--screenshot="))
		elif a == "--watch-first":
			auto_watch = true
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
		elif a == "--build-packs":
			build_packs = true
	get_window().title = "游戏王 · 服务端（端口 %d）" % ServerCore.port
	get_window().min_size = Vector2i(1120, 700)
	_build_ui()
	ServerCore.state_changed.connect(_mark_dirty)
	ServerCore.players_changed.connect(_mark_dirty)
	ServerCore.rooms_changed.connect(_mark_dirty)
	ServerCore.log_emitted.connect(_on_log)
	# 回放启动阶段的日志
	for entry in ServerCore.log_history:
		_on_log(str(entry.get("text", "")), entry.get("color", UITheme.TEXT))
	_refresh_all()
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
	if build_packs:
		get_tree().create_timer(1.0).timeout.connect(_run_build_packs)
	if screenshot_delay > 0.0:
		get_tree().create_timer(screenshot_delay).timeout.connect(_take_screenshot)


## 自测/运维：为所有空牌组卡包批量构建牌组（与卡包页「构建全部」等效），完成后退出
func _run_build_packs() -> void:
	if ServerCore.pack_db != null:
		var r: Array = ServerCore.pack_db.build_empty_packs()
		ServerCore.log_line("批量构建卡包：已构建 %d 个，跳过 %d 个（已有牌组）" % [int(r[0]), int(r[1])], UITheme.GOLD)
	get_tree().quit()


func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("user://screenshot.png")
	print("[截图] 结果=%d 文件=%s" % [err, ProjectSettings.globalize_path("user://screenshot.png")])
	get_tree().quit()


func _process(delta: float) -> void:
	if not _dirty:
		_accum = 0.0
		return
	_accum += delta
	if _accum >= 0.4:
		_dirty = false
		_accum = 0.0
		_refresh_all()


func _mark_dirty() -> void:
	_dirty = true


# ================= 界面构建 =================

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_build_topbar(root)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_build_left(body)
	_build_center(body)
	_build_log(root)

	watch_page = preload("res://scenes/watch_page.tscn").instantiate()
	watch_page.db = ServerCore.card_db   # 注入卡片库：观战页显示真实卡图
	add_child(watch_page)
	watch_page.exit_requested.connect(func():
		if watch_page.visible:
			watch_page.close_view()
	)
	watch_page.close_room_requested.connect(func(room_id: String): ServerCore.close_room(room_id))

	# 卡包页面（点击卡包 → 卡片管理）
	pack_page = preload("res://scenes/pack_page.tscn").instantiate()
	pack_page.card_db = ServerCore.card_db
	pack_page.pack_db = ServerCore.pack_db
	add_child(pack_page)
	pack_page.pack_opened.connect(_open_pack_manager)

	# 卡片管理页面（牌组编辑）
	card_manager = preload("res://scenes/card_manager_page.tscn").instantiate()
	card_manager.card_db = ServerCore.card_db
	card_manager.pack_db = ServerCore.pack_db
	add_child(card_manager)
	card_manager.back_requested.connect(_close_pack_manager)


# ================= 卡包 / 卡片管理页面 =================

func _open_pack_page() -> void:
	if pack_page == null:
		return
	watch_page.close_view()
	card_manager.visible = false
	pack_page.open()


func _open_pack_manager(pack_id: String) -> void:
	pack_page.visible = false
	card_manager.open(pack_id)
	ServerCore.log_line("打开卡片管理：编辑卡包「%s」的牌组" % card_manager.name_text(), UITheme.ACCENT)


func _close_pack_manager() -> void:
	card_manager.visible = false
	pack_page.open()


func _build_topbar(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG_PANEL, UITheme.BORDER, 12, 1, 12))
	root.add_child(panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	panel.add_child(h)

	var title := UITheme.text_label("游戏王 · 服务端", UITheme.GOLD, 18)
	h.add_child(title)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)

	chip_status = _make_chip(h, "运行中 · 端口 %d" % ServerCore.port, UITheme.GREEN)
	chip_status.add_theme_color_override("font_color", UITheme.GREEN)
	chip_players = _make_chip(h, "在线玩家 0")
	chip_rooms = _make_chip(h, "房间 0")

	var bc := Button.new()
	bc.text = "广播通知"
	UITheme.style_button(bc, true)
	bc.pressed.connect(_show_broadcast_dialog)
	h.add_child(bc)

	var pk := Button.new()
	pk.text = "卡包管理"
	UITheme.style_button(pk, true)
	pk.pressed.connect(_open_pack_page)
	h.add_child(pk)


func _make_chip(parent: Control, text: String, dot_color := Color(0, 0, 0, 0)) -> Label:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG_PANEL_LIGHT, UITheme.BORDER, 8, 1, 8))
	parent.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	if dot_color.a > 0.0:
		h.add_child(UITheme.dot_label(dot_color))
	var l := UITheme.text_label(text, UITheme.TEXT, 12)
	h.add_child(l)
	return l


func _build_left(body: Control) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(290, 0)
	panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	body.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	v.add_child(UITheme.text_label("服务器控制台", UITheme.TEXT, 15))

	# 服务器信息
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG_PANEL_LIGHT, UITheme.BORDER, 9, 1, 10))
	v.add_child(info)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 6)
	info.add_child(iv)
	iv.add_child(UITheme.text_label("监听端口  :%d" % ServerCore.port, UITheme.TEXT, 13))
	var db_text := "未加载"
	if ServerCore.card_db != null:
		db_text = "卡库 %d 张 · 卡图 %d 张" % [ServerCore.card_db.card_count, ServerCore.card_db.image_count]
	iv.add_child(UITheme.text_label("卡片库  %s" % db_text, UITheme.TEXT_DIM, 12, true))
	if ServerCore.pack_db != null:
		iv.add_child(UITheme.text_label("卡包  %s（顶栏「卡包管理」进入）" % ServerCore.pack_db.stats_text(), UITheme.TEXT_DIM, 12, true))
	iv.add_child(UITheme.text_label("3D 怪兽模型  已绑定 %d 个" % MonsterModelDB.binding_count(), UITheme.TEXT_DIM, 12, true))
	uptime_label = UITheme.text_label("运行时长  00:00:00", UITheme.TEXT_DIM, 12, true)
	iv.add_child(uptime_label)

	v.add_child(UITheme.text_label("演示 / 自测", UITheme.TEXT, 14))
	var b5 := Button.new()
	b5.text = "演示：3D 怪兽上场"
	UITheme.style_button(b5, true)
	b5.pressed.connect(_demo_place_bound_monster)
	v.add_child(b5)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)

	var hint := UITheme.text_label("真人对战：两名玩家分别在各自客户端建房 / 加入，双方准备后轮流操作出牌（召唤 / 攻击 / 结束回合），可在右侧房间总览点「进入观看」旁观。\n「演示：3D 怪兽上场」：把已绑定 3D 模型的怪兽直接放到对战中玩家场上（观战页卡片格子上方显示模型）。", UITheme.TEXT_DIM, 12, true)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)


## 演示：把第一个已绑定 3D 模型的怪兽直接放到对战中的怪兽区
func _demo_place_bound_monster() -> void:
	for cid in MonsterModelDB.BINDINGS.keys():
		var msg := ServerCore.demo_place_card(int(cid))
		var col: Color = UITheme.ACCENT if msg.begins_with("已放置") else UITheme.YELLOW
		ServerCore.log_line("演示操作：%s" % msg, col)
		return
	ServerCore.log_line("没有已绑定的 3D 怪兽模型", UITheme.YELLOW)


func _build_center(body: Control) -> void:
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 10)
	body.add_child(center)

	center_title = UITheme.text_label("服务器总览", UITheme.TEXT, 15)
	center.add_child(center_title)

	# 玩家总览
	var p_panel := PanelContainer.new()
	p_panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	p_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p_panel.size_flags_stretch_ratio = 1.0
	center.add_child(p_panel)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	p_panel.add_child(pv)

	player_title = UITheme.text_label("玩家总览（0）", UITheme.TEXT, 14)
	pv.add_child(player_title)

	var p_scroll := ScrollContainer.new()
	p_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p_scroll.custom_minimum_size = Vector2(0, 150)
	pv.add_child(p_scroll)

	player_list_box = VBoxContainer.new()
	player_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_list_box.add_theme_constant_override("separation", 6)
	p_scroll.add_child(player_list_box)

	# 房间总览
	var r_panel := PanelContainer.new()
	r_panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	r_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_panel.size_flags_stretch_ratio = 1.2
	center.add_child(r_panel)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	r_panel.add_child(rv)

	room_title = UITheme.text_label("房间总览（0）", UITheme.TEXT, 14)
	rv.add_child(room_title)

	var r_scroll := ScrollContainer.new()
	r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	r_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_scroll.custom_minimum_size = Vector2(0, 170)
	rv.add_child(r_scroll)

	room_list_box = VBoxContainer.new()
	room_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_list_box.add_theme_constant_override("separation", 6)
	r_scroll.add_child(room_list_box)


func _build_log(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 150)
	panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	root.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_child(UITheme.text_label("事件日志", UITheme.TEXT, 14))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var clr := Button.new()
	clr.text = "清空"
	UITheme.style_button(clr, false, true)
	clr.pressed.connect(func(): log_label.text = "")
	top.add_child(clr)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_font_size_override("normal_font_size", 12)
	log_label.add_theme_stylebox_override("normal", UITheme.sb(Color("111122"), UITheme.BORDER, 8, 1, 8))
	v.add_child(log_label)


# ================= 刷新 =================

func _refresh_all() -> void:
	_rebuild_players()
	_rebuild_rooms()
	_update_chips()
	_update_watch()
	# 自动观战模式下，出现第一个房间即进入观战
	if auto_watch and not watch_page.visible and not ServerCore.rooms.is_empty():
		var r0: Room = ServerCore.rooms.values()[0]
		_enter_room(r0.id, r0.name)


func _update_chips() -> void:
	chip_players.text = "在线玩家 %d" % ServerCore.logged_player_count()
	chip_rooms.text = "房间 %d" % ServerCore.total_room_count()
	uptime_label.text = "运行时长  %s" % ServerCore.uptime_text()


func _rebuild_players() -> void:
	for c in player_list_box.get_children():
		c.queue_free()
	var list := ServerCore.players.values()
	player_title.text = "玩家总览（%d）" % list.size()
	if list.is_empty():
		player_list_box.add_child(_empty_hint("暂无在线玩家\n等待客户端连接…", 60))
		return
	player_list_box.add_child(_table_header(["昵称", "IP", "状态", "操作"], [0.0, 120.0, 70.0, 56.0]))
	for p in list:
		player_list_box.add_child(_row_card(_player_row(p)))


func _player_row(p: Player) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var n := UITheme.text_label(p.nickname if p.is_logged() else "（未登录）", UITheme.TEXT, 13)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(n)

	var ip := UITheme.text_label(p.ip, UITheme.TEXT_DIM, 12, true)
	ip.custom_minimum_size = Vector2(120, 0)
	row.add_child(ip)

	var st := "大厅" if p.room_id == "" else "房间中"
	var st_l := UITheme.text_label(st, UITheme.TEXT_DIM, 12, true)
	st_l.custom_minimum_size = Vector2(70, 0)
	row.add_child(st_l)

	var kick := Button.new()
	kick.text = "踢出"
	kick.custom_minimum_size = Vector2(56, 26)
	UITheme.style_button_danger(kick)
	var pid := p.id
	kick.pressed.connect(func(): ServerCore.kick_player(pid))
	row.add_child(kick)
	return row


func _rebuild_rooms() -> void:
	for c in room_list_box.get_children():
		c.queue_free()
	var list := ServerCore.rooms.values()
	room_title.text = "房间总览（%d）" % list.size()
	if list.is_empty():
		room_list_box.add_child(_empty_hint("暂无房间\n等待玩家建房…", 60))
		return
	room_list_box.add_child(_table_header(["房间名", "房主", "人数", "状态", "操作", ""], [0.0, 100.0, 52.0, 64.0, 84.0, 56.0]))
	for r in list:
		room_list_box.add_child(_row_card(_room_row(r)))


func _room_row(r: Room) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var n := UITheme.text_label(r.name, UITheme.TEXT, 13)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(n)

	var o := UITheme.text_label(ServerCore._name_of(r.owner_id), UITheme.TEXT_DIM, 12, true)
	o.custom_minimum_size = Vector2(100, 0)
	o.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(o)

	var c := UITheme.text_label("%d/%d" % [r.members.size(), r.max_players], UITheme.TEXT_DIM, 12, true)
	c.custom_minimum_size = Vector2(52, 0)
	row.add_child(c)

	var st := UITheme.text_label(_room_state_text(r.state), _room_state_color(r.state), 12, true)
	st.custom_minimum_size = Vector2(64, 0)
	row.add_child(st)

	var enter := Button.new()
	enter.text = "进入观看"
	enter.custom_minimum_size = Vector2(84, 26)
	UITheme.style_button(enter, false, true)
	var rid := r.id
	var rname := r.name
	enter.pressed.connect(func(): _enter_room(rid, rname))
	row.add_child(enter)

	var closeb := Button.new()
	closeb.text = "关闭"
	closeb.custom_minimum_size = Vector2(56, 26)
	UITheme.style_button_danger(closeb)
	closeb.pressed.connect(func(): ServerCore.close_room(rid))
	row.add_child(closeb)
	return row


func _room_state_text(state: String) -> String:
	match state:
		"waiting":
			return "等待中"
		"dueling":
			return "对战中"
		"finished":
			return "已结束"
	return state


func _room_state_color(state: String) -> Color:
	match state:
		"waiting":
			return UITheme.BLUE
		"dueling":
			return UITheme.GOLD
	return UITheme.TEXT_DIM


func _enter_room(room_id: String, room_name: String) -> void:
	watch_page.open(room_id, room_name, "服务端 · 端口 :%d" % ServerCore.port)
	_update_watch()


## 观战视图本地实时刷新（数据直读，无需网络）
func _update_watch() -> void:
	if not watch_page.visible:
		return
	var v := ServerCore.room_view(watch_page.room_id)
	if v.is_empty():
		watch_page.close_view()
		return
	watch_page.update_view(v)


# ================= 通用小部件 =================

func _empty_hint(text: String, min_height := 60) -> Control:
	var l := UITheme.text_label(text, UITheme.TEXT_DIM, 13, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(0, min_height)
	return l


func _table_header(cells: Array, widths: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for i in cells.size():
		var l := UITheme.text_label(str(cells[i]), UITheme.TEXT_DIM, 12, true)
		var w := float(widths[i])
		if w <= 0.0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size = Vector2(w, 0)
		row.add_child(l)
	return row


func _row_card(child: Control) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.sb(Color("20203a"), Color("26264a"), 7, 1, 7))
	p.add_child(child)
	return p


# ================= 信号处理 =================

func _on_log(text: String, color: Color) -> void:
	log_label.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text])


func _show_broadcast_dialog() -> void:
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
	panel.custom_minimum_size = Vector2(440, 0)
	panel.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG_PANEL, UITheme.ACCENT_DEEP, 12, 1, 16))
	cc.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UITheme.text_label("向所有在线玩家广播", UITheme.TEXT, 15))

	var edit := LineEdit.new()
	edit.placeholder_text = "输入广播内容…"
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
	cancel.pressed.connect(func(): layer.queue_free())
	btns.add_child(cancel)

	var send := Button.new()
	send.text = "发送广播"
	UITheme.style_button(send, true)
	send.pressed.connect(func():
		ServerCore.broadcast(edit.text)
		layer.queue_free()
	)
	btns.add_child(send)

	edit.text_submitted.connect(func(t: String):
		ServerCore.broadcast(t)
		layer.queue_free()
	)
	edit.grab_focus()
