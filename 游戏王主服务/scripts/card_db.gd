class_name CardDB
extends RefCounted
## 卡片数据库：解析 assets/cards.json（14342 张卡片），按需从 assets/cards_raw/ 加载卡图
## 卡图目录带 .gdignore：不让 Godot 导入 1.4 万张图（那会拖慢编辑器/导出），
## 改为运行时直接读取原始 webp 文件解码为纹理（带 LRU 缓存）。
## 导出 exe 说明：.gdignore 目录不会被打包，程序会自动改读「与 exe 同目录的
## assets/cards_raw/*.webp」（保持该文件夹与 exe 放在一起即可）；找不到时回退卡背。

const CARDS_PATH := "res://assets/cards.json"
const IMG_DIR := "res://assets/cards_raw/"
const IMG_EXT := ".webp"
const EXTERNAL_DIR := "assets/cards_raw/"   # 导出版：与 exe 同目录的外置卡图文件夹
const TEX_CACHE_MAX := 300    # 纹理 LRU 上限（200x290 RGBA 约 230KB/张）

var loaded := false
var card_count := 0           # 成功解析的卡片数
var image_count := 0          # 卡图目录中的 .webp 文件数
var load_ms := 0              # 解析耗时（毫秒）
var cards := {}               # str(id) -> 精简卡片字典
var ids: Array = []           # 全部有效卡片 id（int）
var monster_ids: Array = []   # 主卡组怪兽 id（可召唤：有 ATK、非额外卡组、排除 id=0）
var low_monster_ids: Array = []  # 4 星及以下怪兽 id

var _textures := {}           # str(id) -> Texture2D
var _tex_order: Array = []    # LRU 访问顺序（末尾最新）
var _failed := {}             # str(id) -> true（缺图/解码失败，避免重复读盘）


## 解析卡库。返回是否成功；成功后 loaded = true。
func load_all() -> bool:
	var t0 := Time.get_ticks_msec()
	if not FileAccess.file_exists(CARDS_PATH):
		push_warning("卡片数据库缺失：%s" % CARDS_PATH)
		return false
	var f := FileAccess.open(CARDS_PATH, FileAccess.READ)
	if f == null:
		push_warning("卡片数据库无法打开：%s" % CARDS_PATH)
		return false
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if not (raw is Dictionary):
		push_warning("卡片数据库格式错误（应为 JSON 对象）")
		return false

	var src: Dictionary = raw
	for key in src.keys():
		var c = src[key]
		if not (c is Dictionary):
			continue
		var v: Dictionary = c
		var pid := int(v.get("id", 0))
		if pid <= 0:
			continue    # id=0 为占位数据（无卡图）
		var t_any = v.get("text", {})
		var text: Dictionary = t_any if t_any is Dictionary else {}
		var d_any = v.get("data", {})
		var tdata: Dictionary = d_any if d_any is Dictionary else {}
		var types := str(text.get("types", ""))
		var kind := "other"
		if "[怪兽" in types:
			kind = "monster"
		elif "[魔法" in types:
			kind = "spell"
		elif "[陷阱" in types:
			kind = "trap"
		var atk := int(tdata.get("atk", -1))
		var def := int(tdata.get("def", -1))
		var level := int(tdata.get("level", 0))
		cards[str(pid)] = {
			"id": pid,
			"cid": int(v.get("cid", 0)),
			"name": _pick_name(v),
			"en_name": str(v.get("en_name", "")),
			"jp_name": str(v.get("jp_name", "")),
			"types": types,
			"desc": str(text.get("desc", "")),
			"atk": atk,
			"def": def,
			"level": level,
			"race": int(tdata.get("race", 0)),
			"attribute": int(tdata.get("attribute", 0)),
			"kind": kind,
		}
		ids.append(pid)
		if kind == "monster" and atk >= 0:
			# 排除融合/同调/超量/连接（额外卡组，模拟不涉及）；只保留主卡组怪兽
			var head := types.split("\n")[0] if "\n" in types else types
			var is_extra := ("融合" in head) or ("同调" in head) or ("超量" in head) or ("连接" in head)
			if not is_extra:
				monster_ids.append(pid)
				if level >= 1 and level <= 4:
					low_monster_ids.append(pid)

	card_count = cards.size()
	image_count = _count_images()
	loaded = true
	load_ms = Time.get_ticks_msec() - t0
	return true


## 卡名优先顺序：简中 > 中文 > 常用名 > 日文 > 英文
func _pick_name(v: Dictionary) -> String:
	for k in ["cn_name", "sc_name", "md_name", "nwbbs_n", "cnocg_n", "jp_name", "en_name"]:
		if v.has(k) and str(v[k]) != "":
			return str(v[k])
	return "未知卡片"


func _count_images() -> int:
	var d := DirAccess.open(IMG_DIR)
	if d == null:
		return 0
	var n := 0
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if fn.ends_with(".webp"):
			n += 1
		fn = d.get_next()
	d.list_dir_end()
	return n


# ================= 查询 =================

func get_card(pid) -> Dictionary:
	var c = cards.get(str(pid))
	return c if c is Dictionary else {}


func name_of(pid) -> String:
	var c := get_card(pid)
	return str(c.get("name", "卡片#%s" % str(pid)))


## 观战/协议用精简信息：{id, name, atk, def}
func brief(pid) -> Dictionary:
	var c := get_card(pid)
	if c.is_empty():
		return {}
	return {
		"id": int(c.get("id", 0)),
		"name": str(c.get("name", "")),
		"atk": int(c.get("atk", -1)),
		"def": int(c.get("def", -1)),
	}


func stats_text() -> String:
	return "卡库 %d 张 · 卡图 %d 张（%.0f ms）" % [card_count, image_count, float(load_ms)]


# ================= 卡图 =================

## 按需加载卡图（带 LRU 缓存）；缺图/解码失败返回 null（调用方自行回退卡背）
func texture_of(pid) -> Texture2D:
	var key := str(pid)
	if key == "" or key == "0":
		return null
	if _textures.has(key):
		_touch(key)
		return _textures[key]
	if _failed.has(key):
		return null
	var img := _decode_card(key)
	var tex: Texture2D = null
	if img != null:
		tex = ImageTexture.create_from_image(img)
	if tex == null:
		_failed[key] = true
		return null
	_textures[key] = tex
	_tex_order.append(key)
	if _tex_order.size() > TEX_CACHE_MAX:
		var old: String = _tex_order.pop_front()
		_textures.erase(old)
	return tex


## 读取并解码一张卡图（依次尝试：res:// 原始文件 → exe 同目录外置文件夹）
func _decode_card(key: String) -> Image:
	var path := IMG_DIR + key + IMG_EXT
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		var ext := _external_path(key)
		if FileAccess.file_exists(ext):
			bytes = FileAccess.get_file_as_bytes(ext)
	if not bytes.is_empty():
		var img := Image.new()
		if img.has_method("load_webp_from_buffer"):
			if img.load_webp_from_buffer(bytes) == OK and img.get_width() > 0:
				return img
	# 兜底：按路径直接读盘
	for p in [path, _external_path(key)]:
		if FileAccess.file_exists(p):
			var alt := Image.load_from_file(p)
			if alt != null and alt.get_width() > 0:
				return alt
	return null


## 与 exe（源码运行时为 Godot 可执行文件）同目录的外置卡图路径
func _external_path(key: String) -> String:
	return OS.get_executable_path().get_base_dir().path_join(EXTERNAL_DIR + key + IMG_EXT)


func _touch(key: String) -> void:
	var i := _tex_order.find(key)
	if i >= 0:
		_tex_order.remove_at(i)
	_tex_order.append(key)


# ================= 卡组构建 =================

func random_monster_id(low_only := false) -> int:
	var pool: Array = low_monster_ids if (low_only and not low_monster_ids.is_empty()) else monster_ids
	if pool.is_empty():
		return 0
	return pool[randi() % pool.size()]


## 生成一副卡组（模拟对战用：全怪兽，70% 4 星以下便于召唤）
func make_deck(count := 40) -> Array:
	var out: Array = []
	if monster_ids.is_empty():
		return out
	for i in count:
		var pid := random_monster_id(randf() < 0.7)
		if pid > 0:
			out.append(pid)
	return out
