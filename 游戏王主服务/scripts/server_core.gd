extends Node
## 服务端核心（Autoload: ServerCore）
## 玩家服务 + 房间系统 + 真人对战（双方玩家轮流操作出牌）全部在本服务内
## 管理界面直接读取本地数据（观战无需网络转发），客户端直连本服务

signal state_changed
signal players_changed
signal rooms_changed
signal log_emitted(text: String, color: Color)

# ---------- 配置 ----------
var port := 9000

# ---------- 卡片数据库 ----------
var card_db: CardDB = null     # 启动时加载 assets/cards.json + cards_raw 卡图
var pack_db: PackDB = null     # 卡包数据（卡包页面 / 卡片管理页面用，持久化 user://packs.json）

# ---------- 运行状态 ----------
var started_at := 0.0
var player_tcp := TCPServer.new()
var running := false
var players := {}              # player_id -> Player
var rooms := {}                # room_id -> Room
var log_history: Array = []
var _next_player := 1
var _next_room := 1
var test_duration := 0.0       # 自测参数 --test-duration=秒
var force_field_id := 0        # 自测参数 --force-field=密码id：开战时该卡直接上场（验证 3D 模型展示）

# ---------- 观战推送 ----------
const WATCH_INTERVAL := 0.5    # 观战快照推送间隔（秒）
var watch_accum := 0.0


func _ready() -> void:
	_parse_args()
	started_at = Time.get_unix_time_from_system()
	_load_card_db()
	start()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.trim_prefix("--port="))
		elif a.begins_with("--test-duration="):
			test_duration = float(a.trim_prefix("--test-duration="))
		elif a.begins_with("--force-field="):
			force_field_id = int(a.trim_prefix("--force-field="))


func _load_card_db() -> void:
	var db := CardDB.new()
	if db.load_all():
		card_db = db
		log_line("卡片数据库加载完成：%s" % db.stats_text(), UITheme.GOLD)
		# 卡包数据（预置 6 个卡包，生成卡片池；已有存档则直接读取）
		pack_db = PackDB.new()
		pack_db.setup(db)
		log_line("卡包数据就绪：%s" % pack_db.stats_text(), UITheme.GOLD)
	else:
		log_line("卡片数据库加载失败（assets/cards.json），对战模拟将退回占位卡名", UITheme.RED)


func card_stats_text() -> String:
	return card_db.stats_text() if card_db != null else "未加载"


func start() -> void:
	var err := player_tcp.listen(port, "*")
	if err == OK:
		running = true
		log_line("服务端启动成功，监听端口 %d，等待玩家连接…" % port, UITheme.GREEN)
	else:
		log_line("服务端启动失败：端口 %d 不可用（错误码 %d），可能已被占用" % [port, err], UITheme.RED)


func log_line(text: String, color: Color = UITheme.TEXT) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), text]
	print(line)
	log_history.append({"text": line, "color": color})
	if log_history.size() > 300:
		log_history = log_history.slice(log_history.size() - 300)
	log_emitted.emit(line, color)


func _process(delta: float) -> void:
	if test_duration > 0.0 and Time.get_unix_time_from_system() - started_at > test_duration:
		print("[自测] 到达测试时长，自动退出")
		get_tree().quit()
		return
	if not running:
		return
	# 接受新玩家连接
	while player_tcp.is_connection_available():
		var peer := player_tcp.take_connection()
		if peer == null:
			break
		_accept_player(peer)
	# 轮询玩家消息
	for pid in players.keys():
		var p: Player = players[pid]
		var msgs := p.conn.poll_messages()
		if p.conn.closed:
			_remove_player(p, "连接断开")
			continue
		for m in msgs:
			_handle_player_msg(p, m)
	# 观战快照周期推送
	watch_accum += delta
	if watch_accum >= WATCH_INTERVAL:
		watch_accum = 0.0
		_push_watch_snapshots()


# ==================== 玩家连接 ====================

func _accept_player(peer: StreamPeerTCP) -> void:
	var p := Player.new()
	p.conn = NetConn.new(peer)
	p.ip = peer.get_connected_host()
	p.id = "p%d" % _next_player
	_next_player += 1
	players[p.id] = p
	state_changed.emit()


func _send_to(p: Player, type: String, data: Dictionary = {}) -> void:
	if p.conn != null and not p.conn.closed:
		p.conn.send(type, data)


func _handle_player_msg(p: Player, msg: Dictionary) -> void:
	var type := str(msg.get("type", ""))
	var raw = msg.get("data", {})
	var d: Dictionary = raw if raw is Dictionary else {}
	match type:
		"login":
			_do_login(p, str(d.get("nickname", "")))
		"list_rooms":
			if p.is_logged():
				_send_to(p, "room_list", {"rooms": _room_list_for_lobby()})
		"create_room":
			_do_create_room(p, str(d.get("name", "")), int(d.get("max_players", 2)))
		"join_room":
			_do_join_room(p, str(d.get("room_id", "")))
		"leave_room":
			_do_leave_room(p, "主动离开")
		"set_ready":
			_do_set_ready(p, bool(d.get("ready", false)))
		"select_pack":
			_do_select_pack(p, d)
		"duel_action":
			_do_duel_action(p, d)
		"watch_room":
			_do_watch_room(p, str(d.get("room_id", "")))
		"unwatch_room":
			_do_unwatch_room(p)
		"logout":
			_remove_player(p, "主动退出")


func _do_login(p: Player, nickname: String) -> void:
	if p.is_logged():
		return
	nickname = nickname.strip_edges()
	if nickname == "":
		nickname = "玩家%d" % (randi() % 9000 + 1000)
	var final := nickname
	var seq := 2
	while _nickname_taken(final):
		final = "%s#%d" % [nickname, seq]
		seq += 1
	p.nickname = final
	p.login_at = Time.get_unix_time_from_system()
	_send_to(p, "login_ok", {
		"player_id": p.id,
		"nickname": p.nickname,
		"server_name": "服务端",
	})
	log_line("玩家「%s」登录（%s）" % [p.nickname, p.ip], UITheme.BLUE)
	_broadcast_lobby()
	players_changed.emit()


func _nickname_taken(nick: String) -> bool:
	for pid in players.keys():
		var p: Player = players[pid]
		if p.nickname == nick:
			return true
	return false


func _remove_player(p: Player, reason: String) -> void:
	if p.room_id != "":
		_do_leave_room(p, reason)
	players.erase(p.id)
	if p.is_logged():
		log_line("玩家「%s」下线（%s）" % [p.nickname, reason], UITheme.TEXT_DIM)
	if p.conn != null:
		p.conn.close()
	players_changed.emit()
	_broadcast_lobby()


# ==================== 房间逻辑 ====================

func _do_create_room(p: Player, room_name: String, max_players: int) -> void:
	if not p.is_logged():
		_send_to(p, "error", {"message": "请先登录"})
		return
	if p.room_id != "":
		_send_to(p, "error", {"message": "你已在房间中"})
		return
	var r := Room.new()
	r.id = "r%d" % _next_room
	_next_room += 1
	r.name = room_name.strip_edges()
	if r.name == "":
		r.name = "%s 的决斗场" % p.nickname
	r.owner_id = p.id
	r.max_players = 2
	r.created_at = Time.get_unix_time_from_system()
	r.members.append(p.id)
	r.ready[p.id] = false
	r.lp[p.id] = 8000
	r.hand[p.id] = 0
	r.add_log("「%s」创建了房间" % p.nickname)
	rooms[r.id] = r
	p.room_id = r.id
	p.watch_room_id = ""
	_send_to(p, "room_joined", {"room": room_view(r.id)})
	log_line("房间「%s」创建（房主：%s）" % [r.name, p.nickname], UITheme.GOLD)
	_broadcast_lobby()
	rooms_changed.emit()


func _do_join_room(p: Player, room_id: String) -> void:
	if not p.is_logged():
		_send_to(p, "error", {"message": "请先登录"})
		return
	if p.room_id != "":
		_send_to(p, "error", {"message": "你已在房间中"})
		return
	var r: Room = rooms.get(room_id)
	if r == null:
		_send_to(p, "error", {"message": "房间不存在"})
		return
	if r.state != "waiting":
		_send_to(p, "error", {"message": "房间已开始对战"})
		return
	if r.members.size() >= r.max_players:
		_send_to(p, "error", {"message": "房间已满"})
		return
	r.members.append(p.id)
	r.ready[p.id] = false
	r.lp[p.id] = 8000
	r.hand[p.id] = 0
	p.room_id = r.id
	p.watch_room_id = ""
	r.add_log("「%s」加入了房间" % p.nickname)
	_send_to(p, "room_joined", {"room": room_view(r.id)})
	_broadcast_room(r)
	log_line("玩家「%s」加入房间「%s」" % [p.nickname, r.name], UITheme.BLUE)
	_broadcast_lobby()
	rooms_changed.emit()


func _do_leave_room(p: Player, reason: String) -> void:
	var r: Room = rooms.get(p.room_id)
	p.room_id = ""
	if r == null:
		return
	if r.owner_id == p.id:
		_close_room(r, "房主已离开")
		return
	if r.members.has(p.id):
		var was_dueling := r.state == "dueling"
		r.members.erase(p.id)
		r.ready.erase(p.id)
		r.lp.erase(p.id)
		r.hand.erase(p.id)
		r.pack_choice.erase(p.id)
		r.deck_cards.erase(p.id)
		r.hand_cards.erase(p.id)
		r.field_monsters.erase(p.id)
		r.field_spells.erase(p.id)
		r.grave_cards.erase(p.id)
		r.extra_deck.erase(p.id)
		r.add_log("「%s」离开了房间" % p.nickname)
		# 对战中中途离开 → 对方获胜（真人对战：一人退出即判负）
		if was_dueling and r.members.size() == 1:
			var left_id := str(r.members[0])
			r.state = "finished"
			r.phase = "决斗结束"
			r.active_pid = left_id
			r.add_log("「%s」中途离开对战，判负；「%s」获得胜利！" % [p.nickname, _name_of(left_id)])
			log_line("玩家「%s」在对战中离开房间「%s」，判「%s」获胜" % [p.nickname, r.name, _name_of(left_id)], UITheme.YELLOW)
		_broadcast_room(r)
		log_line("玩家「%s」离开房间「%s」（%s）" % [p.nickname, r.name, reason], UITheme.TEXT_DIM)
		_send_to(p, "lobby", {"rooms": _room_list_for_lobby()})
		rooms_changed.emit()


func _do_set_ready(p: Player, value: bool) -> void:
	var r: Room = rooms.get(p.room_id)
	if r == null or r.state != "waiting":
		return
	r.ready[p.id] = value
	r.add_log("「%s」%s" % [p.nickname, "已准备" if value else "取消准备"])
	_broadcast_room(r)
	_check_start_duel(r)


## 客户端选择对战卡包：直接上传牌组内容（两端卡包存档各自独立，无法只传 pack_id）
## data: {name:String, deck:[卡id], extra:[卡id]}；deck/extra 均为空表示用默认卡组
func _do_select_pack(p: Player, d: Dictionary) -> void:
	var r: Room = rooms.get(p.room_id)
	if r == null or r.state != "waiting":
		return
	var pack_name := str(d.get("name", "")).strip_edges()
	var deck := _clean_id_arr(d.get("deck", []), 60)
	var extra := _clean_id_arr(d.get("extra", []), 15)
	if deck.is_empty() and extra.is_empty():
		if r.pack_choice.has(p.id):
			r.pack_choice.erase(p.id)
			r.add_log("「%s」改用了默认卡组" % p.nickname)
	else:
		r.pack_choice[p.id] = {"name": pack_name, "deck": deck, "extra": extra}
		var shown := pack_name if pack_name != "" else "自定义牌组"
		r.add_log("「%s」选择了卡包「%s」（主牌组 %d 张 + 额外 %d 张）" % [p.nickname, shown, deck.size(), extra.size()])
		log_line("玩家「%s」选择对战卡包「%s」（主牌组 %d + 额外 %d）" % [p.nickname, shown, deck.size(), extra.size()], UITheme.ACCENT)
	_broadcast_room(r)


## 清洗客户端上传的卡 id 数组：转 int、过滤非法值、限制上限
func _clean_id_arr(a, limit: int) -> Array:
	var out: Array = []
	if a is Array:
		for v in a:
			var cid := int(v)
			if cid > 0:
				out.append(cid)
			if out.size() >= limit:
				break
	return out


# ==================== 客户端观战 ====================

func _do_watch_room(p: Player, room_id: String) -> void:
	if not p.is_logged():
		_send_to(p, "error", {"message": "请先登录"})
		return
	var r: Room = rooms.get(room_id)
	if r == null:
		_send_to(p, "error", {"message": "房间不存在，无法观战"})
		return
	p.watch_room_id = room_id
	_send_to(p, "watch_snapshot", {"room": room_view(room_id)})
	log_line("玩家「%s」开始观战房间「%s」" % [p.nickname, r.name], UITheme.ACCENT)


func _do_unwatch_room(p: Player) -> void:
	p.watch_room_id = ""


func _push_watch_snapshots() -> void:
	for pid in players.keys():
		var p: Player = players[pid]
		if p.watch_room_id == "" or not p.is_logged():
			continue
		var view := room_view(p.watch_room_id)
		if view.is_empty():
			# 房间已不存在（关闭/结束清理）
			p.watch_room_id = ""
			_send_to(p, "watch_ended", {"reason": "房间已关闭或已解散"})
			continue
		_send_to(p, "watch_snapshot", {"room": view})


func _check_start_duel(r: Room) -> void:
	if r.state != "waiting":
		return
	if r.members.size() < r.max_players:
		return
	for pid in r.members:
		if not bool(r.ready.get(pid, false)):
			return
	# 全员准备 → 开始对战（真人对战：双方轮流操作出牌）
	r.state = "dueling"
	r.turn = 1
	r.phase = "抽卡阶段"
	for pid in r.members:
		r.lp[pid] = 8000
		_init_player_deck(r, pid)
	# 自测：指定卡直接上场（用于验证 3D 怪兽模型展示）
	if force_field_id > 0 and card_db != null and not r.members.is_empty():
		var fp := str(r.members[0])
		var ff: Array = r.field_monsters.get(fp, [])
		var fslot := _first_empty_slot(ff)
		if not card_db.get_card(force_field_id).is_empty() and fslot >= 0:
			ff[fslot] = force_field_id
			r.add_log("「%s」的「%s」（密码 id %d）直接上场" % [_name_of(fp), card_db.name_of(force_field_id), force_field_id])
	# 随机决定先手，先手回合开始抽卡
	r.active_pid = str(r.members[randi() % r.members.size()])
	r.add_log("双方已准备，决斗开始！")
	if card_db != null:
		r.add_log("初始手牌各 5 张，卡组以双方选择的卡包为准")
	r.add_log("「%s」先攻！轮到自己的回合时：召唤 / 攻击 / 结束回合" % _name_of(r.active_pid))
	_begin_turn(r)
	_broadcast_room(r)
	log_line("房间「%s」进入对战（先攻：%s）" % [r.name, _name_of(r.active_pid)], UITheme.GOLD)
	rooms_changed.emit()


## 回合开始：当前回合玩家抽一张（卡组空则跳过），重置召唤/放置/攻击计数
func _begin_turn(r: Room) -> void:
	var pid := r.active_pid
	r.summon_used = false
	r.spell_used = false
	r.attacked = []
	if card_db == null:
		r.phase = "主要阶段"
		return
	var cid := _draw_from_deck(r, pid)
	if cid > 0:
		r.hand_cards[pid].append(cid)
		r.hand[pid] = r.hand_cards[pid].size()
		r.add_log("「%s」回合开始，抽到了「%s」（手牌 %d 张）" % [_name_of(pid), card_db.name_of(cid), r.hand[pid]])
	else:
		r.add_log("「%s」回合开始，卡组已空无法抽卡" % _name_of(pid))
	r.phase = "主要阶段"


## 开战初始化：构建卡组、抽 5 张初始手牌
## 玩家选了卡包 → 主牌组 / 额外牌组各自独立（抽卡只从主牌组抽，额外牌组不并入卡组）；
## 未选卡包或主牌组为空 → 随机构筑 40 张默认卡组（默认卡组本身不含额外怪兽）
func _init_player_deck(r: Room, pid: String) -> void:
	r.deck_cards[pid] = []
	r.hand_cards[pid] = []
	r.field_monsters[pid] = [0, 0, 0, 0, 0]   # 固定 5 格，0 = 空位
	r.field_spells[pid] = [0, 0, 0, 0, 0]     # 魔陷区固定 5 格，0 = 空位
	r.grave_cards[pid] = []
	if card_db == null:
		r.hand[pid] = 5
		return
	var deck_list: Array = []
	var extra_show: Array = []
	var choice: Dictionary = r.pack_choice.get(pid, {})
	if not choice.is_empty():
		# 校验卡 id 在卡库中存在；主牌组单独洗切，额外牌组独立存放（抽卡只抽主牌组）
		for cid in choice.get("deck", []):
			if not card_db.get_card(int(cid)).is_empty():
				deck_list.append(int(cid))
		for cid in choice.get("extra", []):
			var eci := int(cid)
			if not card_db.get_card(eci).is_empty():
				extra_show.append(eci)
		deck_list.shuffle()
		extra_show.shuffle()
	r.extra_deck[pid] = extra_show
	if deck_list.is_empty():
		deck_list = card_db.make_deck(40)
		log_line("「%s」使用默认随机卡组 40 张" % _name_of(pid), UITheme.TEXT_DIM)
	else:
		log_line("「%s」使用卡包牌组构筑卡组：主牌组 %d 张（额外 %d 张独立存放，不参与抽卡）" % [_name_of(pid), deck_list.size(), extra_show.size()], UITheme.GOLD)
	r.deck_cards[pid] = deck_list
	for i in 5:
		var cid := _draw_from_deck(r, pid)
		if cid > 0:
			r.hand_cards[pid].append(cid)
	r.hand[pid] = r.hand_cards[pid].size()


## 从卡组顶抽一张，返回卡片 id（卡组空返回 0）
func _draw_from_deck(r: Room, pid: String) -> int:
	var d: Array = r.deck_cards.get(pid, [])
	if d.is_empty():
		return 0
	var cid: int = d.pop_front()
	return cid


func _close_room(r: Room, reason: String) -> void:
	rooms.erase(r.id)
	for pid in r.members.duplicate():
		var p: Player = players.get(pid)
		if p == null:
			continue
		p.room_id = ""
		_send_to(p, "room_closed", {"reason": reason})
		_send_to(p, "lobby", {"rooms": _room_list_for_lobby()})
	log_line("房间「%s」关闭（%s）" % [r.name, reason], UITheme.TEXT_DIM)
	_broadcast_lobby()
	rooms_changed.emit()


# ==================== 真人对战操作（双方玩家轮流出牌） ====================

## 客户端对战操作入口：
##   summon    {action, card_id, hand_slot}  从手牌召唤一只怪兽（每回合 1 次）
##   attack    {action, card_id, target}     card_id 攻击；target=对方怪兽卡 id，0 表示直接攻击
##   end_turn  {action}                      结束回合，把操作权交给对方
func _do_duel_action(p: Player, d: Dictionary) -> void:
	var r: Room = rooms.get(p.room_id)
	if r == null or r.state != "dueling":
		_send_to(p, "error", {"message": "当前不在对战中"})
		return
	if p.id != r.active_pid:
		_send_to(p, "error", {"message": "现在是对方的回合，请等待"})
		return
	if card_db == null:
		_send_to(p, "error", {"message": "卡片库未加载，无法操作"})
		return
	match str(d.get("action", "")):
		"summon":
			_act_summon(r, p, int(d.get("card_id", 0)), int(d.get("hand_slot", -1)), int(d.get("pos", -1)))
		"attack":
			_act_attack(r, p, int(d.get("card_id", 0)), int(d.get("target", 0)))
		"end_turn":
			_act_end_turn(r, p)
		_:
			_send_to(p, "error", {"message": "未知的对战操作"})


## 使用手牌卡（客户端动作统一为 summon，服务端按卡类型分流）：
##   怪兽卡 → 召唤到己方怪兽区（每回合 1 次，summon_used）
##   魔法/陷阱卡 → 放置到己方魔陷区（每回合 1 次，spell_used；V1 仅上场展示，不结算效果）
## hand_slot 为客户端手牌里的原始下标（优先按它定位，避免同名卡移除错位）；
## pos 为拖拽目标格（0-4；非法或已被占则自动放到第一个空位）
func _act_summon(r: Room, p: Player, card_id: int, hand_slot: int, pos: int) -> void:
	var hand: Array = r.hand_cards.get(p.id, [])
	if hand.is_empty():
		_send_to(p, "error", {"message": "手牌已空"})
		return
	var idx := -1
	if hand_slot >= 0 and hand_slot < hand.size() and int(hand[hand_slot]) == card_id:
		idx = hand_slot
	else:
		idx = hand.find(card_id)
	if idx < 0:
		_send_to(p, "error", {"message": "手牌中没有这张卡"})
		return
	var c := card_db.get_card(card_id)
	var kind := str(c.get("kind", ""))
	if kind == "monster":
		_summon_monster(r, p, c, hand, idx, pos)
	elif kind == "spell" or kind == "trap":
		_place_spell(r, p, c, hand, idx, pos)
	else:
		_send_to(p, "error", {"message": "这张卡无法使用"})


## 召唤怪兽：放到己方怪兽区空位（每回合 1 次）
func _summon_monster(r: Room, p: Player, c: Dictionary, hand: Array, idx: int, pos: int) -> void:
	if r.summon_used:
		_send_to(p, "error", {"message": "本回合已经召唤过怪兽了"})
		return
	var field: Array = r.field_monsters.get(p.id, [])
	var slot := pos
	if slot < 0 or slot >= field.size() or int(field[slot]) != 0:
		slot = _first_empty_slot(field)
	if slot < 0:
		_send_to(p, "error", {"message": "怪兽区已满（5 张），无法再召唤"})
		return
	var card_id := int(c.get("id", 0))
	hand.remove_at(idx)
	field[slot] = card_id
	r.hand[p.id] = hand.size()
	r.summon_used = true
	r.add_log("「%s」召唤了「%s」（ATK %d／DEF %d）" % [p.nickname, str(c.get("name", "?")), int(c.get("atk", 0)), int(c.get("def", 0))])
	_broadcast_room(r)
	rooms_changed.emit()


## 放置魔法/陷阱卡：放到己方魔陷区空位（每回合 1 次；V1 仅上场展示，不结算效果、不参与战斗）
func _place_spell(r: Room, p: Player, c: Dictionary, hand: Array, idx: int, pos: int) -> void:
	if r.spell_used:
		_send_to(p, "error", {"message": "本回合已经放置过魔法 / 陷阱卡了"})
		return
	var field: Array = r.field_spells.get(p.id, [])
	var slot := pos
	if slot < 0 or slot >= field.size() or int(field[slot]) != 0:
		slot = _first_empty_slot(field)
	if slot < 0:
		_send_to(p, "error", {"message": "魔陷区已满（5 张），无法再放置"})
		return
	var card_id := int(c.get("id", 0))
	hand.remove_at(idx)
	field[slot] = card_id
	r.hand[p.id] = hand.size()
	r.spell_used = true
	var is_spell := str(c.get("kind", "")) == "spell"
	r.add_log("「%s」%s了%s「%s」" % [p.nickname, "发动" if is_spell else "放置", "魔法卡" if is_spell else "陷阱卡", str(c.get("name", "?"))])
	_broadcast_room(r)
	rooms_changed.emit()


## 攻击：自己的怪兽攻击对方；target=0 为直接攻击（对方场上无怪兽时），否则攻击对方指定怪兽
func _act_attack(r: Room, p: Player, card_id: int, target: int) -> void:
	var field: Array = r.field_monsters.get(p.id, [])
	if not field.has(card_id):
		_send_to(p, "error", {"message": "该怪兽不在你的场上"})
		return
	if r.attacked.has(card_id):
		_send_to(p, "error", {"message": "该怪兽本回合已经攻击过了"})
		return
	var opp_id := _opponent_of(r, p.id)
	if opp_id == "":
		return
	var o_name := _name_of(opp_id)
	var a_name := card_db.name_of(card_id)
	var a_atk := int(card_db.get_card(card_id).get("atk", 0))
	var opp_lp := int(r.lp.get(opp_id, 8000))
	var tfield: Array = r.field_monsters.get(opp_id, [])
	if target <= 0:
		# 直接攻击：对方场上无怪兽才允许
		if _field_count(tfield) > 0:
			_send_to(p, "error", {"message": "对方场上有怪兽，不能直接攻击"})
			return
		r.attacked.append(card_id)
		var lp := maxi(0, opp_lp - a_atk)
		r.lp[opp_id] = lp
		r.add_log("「%s」的「%s」（ATK %d）直接攻击！「%s」受到 %d 点伤害（剩余 LP %d）" % [p.nickname, a_name, a_atk, o_name, a_atk, lp])
		_check_finish(r, opp_id, o_name)
	else:
		var ti := tfield.find(target)
		if ti < 0:
			_send_to(p, "error", {"message": "对方场上没有这张卡"})
			return
		r.attacked.append(card_id)
		var d_id: int = tfield[ti]
		var t_name := card_db.name_of(d_id)
		var t_atk := int(card_db.get_card(d_id).get("atk", 0))
		if a_atk > t_atk:
			var dmg := a_atk - t_atk
			tfield[ti] = 0
			r.grave_cards[opp_id].append(d_id)
			var lp2 := maxi(0, opp_lp - dmg)
			r.lp[opp_id] = lp2
			r.add_log("「%s」的「%s」（ATK %d）击破了「%s」的「%s」（ATK %d），「%s」受到 %d 点伤害（剩余 LP %d）" % [p.nickname, a_name, a_atk, o_name, t_name, t_atk, o_name, dmg, lp2])
			_check_finish(r, opp_id, o_name)
		elif a_atk < t_atk:
			var dmg2 := t_atk - a_atk
			field[field.find(card_id)] = 0
			r.grave_cards[p.id].append(card_id)
			var lp3 := maxi(0, int(r.lp.get(p.id, 8000)) - dmg2)
			r.lp[p.id] = lp3
			r.add_log("「%s」的「%s」（ATK %d）攻击「%s」的「%s」（ATK %d）反被击破，「%s」受到 %d 点伤害（剩余 LP %d）" % [p.nickname, a_name, a_atk, o_name, t_name, t_atk, p.nickname, dmg2, lp3])
			_check_finish(r, p.id, p.nickname)
		else:
			field[field.find(card_id)] = 0
			tfield[ti] = 0
			r.grave_cards[p.id].append(card_id)
			r.grave_cards[opp_id].append(d_id)
			r.add_log("「%s」的「%s」与「%s」的「%s」同归于尽（ATK %d）" % [p.nickname, a_name, o_name, t_name, a_atk])
	_broadcast_room(r)
	rooms_changed.emit()


## 结束回合：操作权交给对方，对方回合开始抽卡
func _act_end_turn(r: Room, p: Player) -> void:
	r.add_log("「%s」结束回合" % p.nickname)
	var opp_id := _opponent_of(r, p.id)
	if opp_id == "":
		return
	r.turn += 1
	r.active_pid = opp_id
	_begin_turn(r)
	_broadcast_room(r)
	rooms_changed.emit()


## 取房间里除 pid 外的另一方（1v1）
func _opponent_of(r: Room, pid: String) -> String:
	for m in r.members:
		if str(m) != pid:
			return str(m)
	return ""


## 场上怪兽数量（5 格数组中非 0 的个数）
func _field_count(arr: Array) -> int:
	var n := 0
	for v in arr:
		if int(v) > 0:
			n += 1
	return n


## 场上第一个空格位（无空位返回 -1）
func _first_empty_slot(arr: Array) -> int:
	for i in arr.size():
		if int(arr[i]) == 0:
			return i
	return -1


## 胜负检查：LP 归零即结束
func _check_finish(r: Room, dead_pid: String, dead_name: String) -> void:
	if int(r.lp.get(dead_pid, 8000)) > 0:
		return
	r.state = "finished"
	r.phase = "决斗结束"
	var winner := _opponent_of(r, dead_pid)
	r.add_log("「%s」的 LP 归零，「%s」获得胜利！" % [dead_name, _name_of(winner)])


# ==================== 管理操作（本地调用） ====================

func kick_player(player_id: String) -> void:
	var p: Player = players.get(player_id)
	if p == null:
		return
	log_line("管理员踢出玩家「%s」" % p.nickname, UITheme.YELLOW)
	_send_to(p, "kicked", {"reason": "被管理员移出服务器"})
	_remove_player(p, "被管理员踢出")


func close_room(room_id: String) -> void:
	var r: Room = rooms.get(room_id)
	if r == null:
		return
	log_line("管理员关闭了房间「%s」" % r.name, UITheme.YELLOW)
	_close_room(r, "被管理员关闭")


func broadcast(text: String) -> void:
	if text.strip_edges() == "":
		return
	log_line("向所有玩家广播：「%s」" % text, UITheme.ACCENT)
	for pid in players.keys():
		var p: Player = players[pid]
		if p.is_logged():
			_send_to(p, "broadcast", {"message": text})


## 演示/自测：把指定卡（按密码 id）直接放到对战中房间的怪兽区（默认第一个玩家）。
## 用于一键查看绑定 3D 模型的怪兽在观战页「卡片格子上方」的展示效果。返回操作结果文案。
func demo_place_card(card_id: int) -> String:
	if card_db == null:
		return "卡片库未加载，无法演示"
	var c := card_db.get_card(card_id)
	if c.is_empty():
		return "卡片库中不存在密码 id %d" % card_id
	var cname := str(c.get("name", "?"))
	for rid in rooms.keys():
		var r: Room = rooms[rid]
		if r.state != "dueling" or r.members.is_empty():
			continue
		var pid := str(r.members[0])
		var field: Array = r.field_monsters.get(pid, [])
		if field.has(card_id):
			return "「%s」已在「%s」的场上" % [cname, _name_of(pid)]
		var slot := _first_empty_slot(field)
		if slot < 0:
			return "「%s」的怪兽区已满（5 张）" % _name_of(pid)
		field[slot] = card_id
		r.field_monsters[pid] = field
		r.add_log("「%s」的「%s」（密码 id %d）直接上场" % [_name_of(pid), cname, card_id])
		_broadcast_room(r)
		rooms_changed.emit()
		return "已放置「%s」到「%s」的怪兽区（观战页卡片格子上方可见 3D 模型）" % [cname, _name_of(pid)]
	return "当前没有对战中的房间：请等双方玩家进入房间、全部准备开始对战后重试"


# ==================== 数据视图 ====================

## 房间完整视图（供客户端同步和本机观战共用）
func room_view(room_id: String) -> Dictionary:
	var r: Room = rooms.get(room_id)
	if r == null:
		return {}
	var plist := []
	for pid in r.members:
		var p: Player = players.get(pid)
		if p == null:
			continue
		var deck_list = r.deck_cards.get(pid, [])
		var hand_list = r.hand_cards.get(pid, [])
		var field_list = r.field_monsters.get(pid, [])
		var spell_list = r.field_spells.get(pid, [])
		var grave_list = r.grave_cards.get(pid, [])
		var pc: Dictionary = r.pack_choice.get(pid, {})
		plist.append({
			"id": p.id,
			"nickname": p.nickname,
			"ready": bool(r.ready.get(pid, false)),
			"lp": int(r.lp.get(pid, 8000)),
			"hand": int(r.hand.get(pid, 0)),
			"is_owner": pid == r.owner_id,
			# ---- 自选卡包（未选/默认时为空串）----
			"pack_name": str(pc.get("name", "")) if not pc.is_empty() else "",
			# ---- 真实卡牌数据（观战渲染用）----
			"deck_count": deck_list.size() if deck_list is Array else 0,
			"deck_cards": _brief_list(deck_list),
			"hand_cards": _brief_list(hand_list),
			"field_cards": _field_brief(field_list),
			"spell_cards": _field_brief(spell_list),
			"grave_top": _brief_last(grave_list),
			"grave_cards": _brief_list(grave_list),
			"extra_deck": _brief_list(r.extra_deck.get(pid, [])),
		})
	return {
		"id": r.id,
		"name": r.name,
		"owner_id": r.owner_id,
		"owner_name": _name_of(r.owner_id),
		"state": r.state,
		"max_players": r.max_players,
		"member_count": r.members.size(),
		"turn": r.turn,
		"phase": r.phase,
		# ---- 真人对战回合状态（客户端操作界面用）----
		"active_pid": r.active_pid,
		"summon_used": r.summon_used,
		"spell_used": r.spell_used,
		"attacked": r.attacked.duplicate(),
		"players": plist,
		"logs": r.logs.duplicate(),
	}


func _room_list_for_lobby() -> Array:
	var out := []
	for rid in rooms.keys():
		var r: Room = rooms[rid]
		out.append({
			"id": r.id,
			"name": r.name,
			"owner_name": _name_of(r.owner_id),
			"member_count": r.members.size(),
			"max_players": r.max_players,
			"state": r.state,
			"joinable": r.state == "waiting" and r.members.size() < r.max_players,
		})
	return out


func _broadcast_room(r: Room) -> void:
	for pid in r.members:
		var p: Player = players.get(pid)
		if p != null and p.is_logged():
			_send_to(p, "room_update", {"room": room_view(r.id)})


func _broadcast_lobby() -> void:
	var payload := _room_list_for_lobby()
	for pid in players.keys():
		var p: Player = players[pid]
		if p.is_logged() and p.room_id == "":
			_send_to(p, "room_list", {"rooms": payload})


func _name_of(pid: String) -> String:
	var p: Player = players.get(pid)
	return p.nickname if p != null else "未知玩家"


## 卡片 id 数组 → 精简信息数组（观战协议用）
func _brief_list(arr_ids: Array) -> Array:
	var out := []
	if card_db == null:
		return out
	for cid in arr_ids:
		var b := card_db.brief(cid)
		if not b.is_empty():
			out.append(b)
	return out


## 场上怪兽 → 精简信息数组（固定 5 格；空位为 {}，供界面按格位渲染 / 拖放目标定位）
func _field_brief(arr_ids: Array) -> Array:
	var out := []
	for i in 5:
		if i < arr_ids.size() and int(arr_ids[i]) > 0:
			out.append(card_db.brief(int(arr_ids[i])) if card_db != null else {})
		else:
			out.append({})
	return out


## 取数组末尾卡片（墓地最上一张）的精简信息
func _brief_last(arr_ids: Array) -> Dictionary:
	if card_db == null or arr_ids.is_empty():
		return {}
	return card_db.brief(arr_ids[arr_ids.size() - 1])


# ==================== 统计辅助 ====================

func logged_player_count() -> int:
	var n := 0
	for pid in players.keys():
		if players[pid].is_logged():
			n += 1
	return n


func total_room_count() -> int:
	return rooms.size()


func uptime_text() -> String:
	var secs := int(Time.get_unix_time_from_system() - started_at)
	return "%02d:%02d:%02d" % [secs / 3600, (secs % 3600) / 60, secs % 60]
