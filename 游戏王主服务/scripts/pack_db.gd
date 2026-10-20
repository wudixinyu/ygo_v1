class_name PackDB
extends RefCounted
## 卡包数据库（服务端）：管理「卡包」列表（预置 6 个 + 可新建），持久化到 user://packs.json
## 每个卡包含：名称 / 主题色 / 代表卡封面 / 卡片池（供卡片管理页展示与构筑） / 编辑中的牌组
## setup() 注入 CardDB 后生成卡片池（按关键词取样 + 随机补足）；卡库缺失时生成空池兜底

const SAVE_PATH := "user://packs.json"
const POOL_SIZE := 80          # 每个卡包的卡片池数量
const DECK_SIZE := 40          # 自动构筑：主牌组张数
const EXTRA_SIZE := 5          # 自动构筑：额外牌组张数
const MAX_COPY := 3            # 卡片管理页：同名卡最多加入张数

## 预置卡包：名称 / 主题色 / 取样关键词（同时决定封面代表卡）
const DEFAULT_PACKS := [
	{"name": "深红力量", "color": "b03a2e", "kw": ["真红眼", "恶魔"]},
	{"name": "青眼MAX", "color": "3f6ed8", "kw": ["青眼", "白龙"]},
	{"name": "Deck", "color": "c0473c", "kw": []},
	{"name": "深蓝之怒", "color": "2f66b0", "kw": ["海龙", "冰", "水"]},
	{"name": "英雄联合", "color": "c9a86a", "kw": ["英雄"]},
	{"name": "黑魔术爆破", "color": "7d3fb8", "kw": ["黑魔"]},
]

const NEW_COLORS := ["4a5fa8", "2e8b6a", "8a4fb0", "b07a3a", "3a7ab0", "a04a5f"]

var db: CardDB = null
var packs: Array = []      # [{id, name, color, cover_id:int, cards:Array[int], deck:Array[int], extra:Array[int]}]


## 注入卡库并加载（无存档时生成预置卡包）
func setup(card_db: CardDB) -> void:
	db = card_db
	if _load_file():
		return
	_init_defaults()
	save()


# ================= 构建 / 持久化 =================

func _init_defaults() -> void:
	packs = []
	for i in DEFAULT_PACKS.size():
		var d: Dictionary = DEFAULT_PACKS[i]
		packs.append(_make_pack("pack%d" % (i + 1), str(d.get("name", "卡包")), str(d.get("color", "3f6ed8")), d.get("kw", [])))


## 生成一个卡包：卡片池（关键词取样 + 随机补足）+ 封面代表卡
func _make_pack(pid: String, pack_name: String, color: String, keywords: Array) -> Dictionary:
	var cards := _build_pool(keywords)
	return {
		"id": pid,
		"name": pack_name,
		"color": color,
		"cover_id": _find_cover(keywords, cards),
		"cards": cards,
		"deck": [],
		"extra": [],
	}


## 卡片池：先取名称命中关键词的怪兽（最多 48 张），再从全卡库随机补足到 POOL_SIZE
func _build_pool(keywords: Array) -> Array:
	var pool: Array = []
	var seen := {}
	if db == null:
		return pool
	if not keywords.is_empty():
		for key in db.cards.keys():
			if pool.size() >= 48:
				break
			var c: Dictionary = db.cards[key]
			if str(c.get("kind", "")) != "monster":
				continue
			var nm := str(c.get("name", ""))
			for k in keywords:
				if nm.find(str(k)) >= 0:
					seen[key] = true
					pool.append(int(c.get("id", 0)))
					break
	var all_ids := db.ids.duplicate()
	all_ids.shuffle()
	for cid in all_ids:
		if pool.size() >= POOL_SIZE:
			break
		var k2 := str(cid)
		if seen.has(k2):
			continue
		seen[k2] = true
		pool.append(int(cid))
	pool.shuffle()
	return pool


## 封面代表卡：优先取名称命中关键词的怪兽；否则取池中第一只怪兽
func _find_cover(keywords: Array, pool: Array) -> int:
	if db == null:
		return 0
	for k in keywords:
		for key in db.cards.keys():
			var c: Dictionary = db.cards[key]
			if str(c.get("kind", "")) == "monster" and str(c.get("name", "")).find(str(k)) >= 0:
				return int(c.get("id", 0))
	for cid in pool:
		if str(db.get_card(cid).get("kind", "")) == "monster":
			return int(cid)
	return 0


func _load_file() -> bool:
	var arr := _read_packs()
	if arr.is_empty():
		return false
	packs = arr
	return true


## 读取并规范化磁盘存档（返回 [] 表示无有效存档）
func _read_packs() -> Array:
	if not FileAccess.file_exists(SAVE_PATH):
		return []
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return []
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if not (raw is Dictionary):
		return []
	var arr = (raw as Dictionary).get("packs", [])
	if not (arr is Array):
		return []
	var out: Array = []
	for it in arr:
		if it is Dictionary and not (it as Dictionary).is_empty():
			out.append(_norm_pack(it))
	return out


## 写入前把磁盘最新数据合并进内存（多实例并存时避免旧数据覆盖新数据）
## 规则：同 id 卡包原地同步字段；新卡包追加；own_pack_id 的牌组字段由调用方写入、不做覆盖
func _sync_from_disk(own_pack_id := "") -> void:
	var fresh := _read_packs()
	if fresh.is_empty():
		return
	for fp in fresh:
		var fid := str(fp.get("id", ""))
		var mine := get_pack(fid)
		if mine.is_empty():
			packs.append(fp)
			continue
		mine["cards"] = fp["cards"]
		mine["cover_id"] = fp["cover_id"]
		mine["name"] = fp["name"]
		mine["color"] = fp["color"]
		if fid != own_pack_id:
			mine["deck"] = fp["deck"]
			mine["extra"] = fp["extra"]


func _norm_pack(p: Dictionary) -> Dictionary:
	return {
		"id": str(p.get("id", "pack0")),
		"name": str(p.get("name", "卡包")),
		"color": str(p.get("color", "3f6ed8")),
		"cover_id": int(p.get("cover_id", 0)),
		"cards": _int_arr(p.get("cards", [])),
		"deck": _int_arr(p.get("deck", [])),
		"extra": _int_arr(p.get("extra", [])),
	}


static func _int_arr(a) -> Array:
	var out: Array = []
	if a is Array:
		for v in a:
			out.append(int(v))
	return out


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"packs": packs}))
	f.close()


# ================= 查询 / 修改 =================

func get_pack(pack_id: String) -> Dictionary:
	for p in packs:
		if str(p.get("id", "")) == pack_id:
			return p
	return {}


## 新建卡包（随机卡片池）；返回新卡包字典
func create_pack(pack_name := "") -> Dictionary:
	_sync_from_disk()
	var seq := 1
	var used := {}
	for p in packs:
		used[str(p.get("id", ""))] = true
	while used.has("pack%d" % seq):
		seq += 1
	var nm := pack_name.strip_edges()
	if nm == "":
		nm = "新卡包 %d" % seq
	var color: String = NEW_COLORS[(seq - 1) % NEW_COLORS.size()]
	var p := _make_pack("pack%d" % seq, nm, color, [])
	packs.append(p)
	save()
	return p


func rename_pack(pack_id: String, new_name: String) -> void:
	new_name = new_name.strip_edges()
	if new_name == "":
		return
	_sync_from_disk(pack_id)
	var p := get_pack(pack_id)
	if p.is_empty():
		return
	p["name"] = new_name
	save()


## 保存编辑中的牌组（主牌组 + 额外牌组）
func set_deck(pack_id: String, deck: Array, extra: Array) -> void:
	_sync_from_disk(pack_id)
	var p := get_pack(pack_id)
	if p.is_empty():
		return
	p["deck"] = deck.duplicate()
	p["extra"] = extra.duplicate()
	save()


func stats_text() -> String:
	return "卡包 %d 个" % packs.size()


# ================= 批量构建 =================

## 为「还没有牌组」的卡包批量自动构筑（40 主牌组 + 5 额外牌组）；已有牌组的卡包跳过
## 返回 [已构建数量, 跳过数量]
func build_empty_packs() -> Array:
	_sync_from_disk()
	var built := 0
	var skipped := 0
	for p in packs:
		var deck: Array = p.get("deck", [])
		var extra: Array = p.get("extra", [])
		if not deck.is_empty() or not extra.is_empty():
			skipped += 1
			continue
		var r := build_deck_lists(_int_arr(p.get("cards", [])))
		p["deck"] = r[0]
		p["extra"] = r[1]
		built += 1
	if built > 0:
		save()
	return [built, skipped]


## 从卡片池构筑牌组：额外怪兽（融合/同调/超量/连接）进额外牌组，其余进主牌组
## 返回 [主牌组, 额外牌组]
func build_deck_lists(pool: Array) -> Array:
	var deck: Array = []
	var extra: Array = []
	if db == null:
		return [deck, extra]
	var arr := pool.duplicate()
	arr.shuffle()
	for cid in arr:
		var c := db.get_card(cid)
		if c.is_empty():
			continue
		if is_extra_monster(c):
			if extra.size() < EXTRA_SIZE:
				extra.append(int(cid))
		elif deck.size() < DECK_SIZE:
			deck.append(int(cid))
		if deck.size() >= DECK_SIZE and extra.size() >= EXTRA_SIZE:
			break
	return [deck, extra]


## 判断卡是否为额外卡组怪兽（融合/同调/超量/连接）
static func is_extra_monster(c: Dictionary) -> bool:
	var types := str(c.get("types", ""))
	var head := types
	if "\n" in types:
		head = types.split("\n")[0]
	return ("融合" in head) or ("同调" in head) or ("超量" in head) or ("连接" in head)
