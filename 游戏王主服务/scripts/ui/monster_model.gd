class_name MonsterModelDisplay
extends Control
## 3D 怪兽全息投影显示（服务端观战页专用）
## 内部是一个透明背景的 SubViewport（独立 3D 世界：相机 + 灯光 + 环境光），
## 把绑定的 3D 怪兽模型渲染成带透明通道的纹理贴在观战页 UI 上，
## 位置由观战页负责摆放到「对应卡片格子上方」。
## 相机根据模型包围盒自动取景——任意来源的模型（缩放/原点不一）都能自动框好。
##
## 用法：new() → 设置 position/size → add_child 到舞台 → set_card(密码id)。

const VIEW_W := 270.0   # 设计稿显示尺寸（1920x1080 坐标系）
const VIEW_H := 310.0
const RENDER_SCALE := 2.0   # SubViewport 渲染倍率（观战页缩放后仍保持清晰）

## 模型资源缓存：path -> PackedScene（多个槽位、多次召唤共用同一份）
static var _scene_cache := {}
## 加载失败缓存：path -> true（避免每 0.4s 反复读盘/刷警告）
static var _failed := {}

var _viewport: SubViewport
var _cam: Camera3D
var _pivot: Node3D          # 模型挂点（浮动动画作用于此）
var _model: Node3D = null   # 当前模型实例
var _card_id := 0           # 当前显示的卡片（密码 id）
var _t := 0.0
var _bob_amp := 0.0         # 上下浮动幅度（按模型高度自适应）


func _init() -> void:
	size = Vector2(VIEW_W, VIEW_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(int(VIEW_W * RENDER_SCALE), int(VIEW_H * RENDER_SCALE))
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true   # 每个显示实例独立 3D 世界（多模型互不串扰）
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR   # 配合 transparent_bg：背景全透明
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.88, 0.92, 1.0)
	env.ambient_light_energy = 0.75
	we.environment = env
	_viewport.add_child(we)

	var key := DirectionalLight3D.new()   # 主光：左上前方
	key.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	key.light_energy = 1.15
	_viewport.add_child(key)

	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.current = true
	_viewport.add_child(_cam)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)

	var tr := TextureRect.new()
	tr.texture = _viewport.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(tr)

	set_process(false)


## 设置显示的卡片（按密码 id 查绑定表）。无绑定/加载失败时自动隐藏。
func set_card(card_id: int) -> void:
	var b := MonsterModelDB.binding_for(card_id)
	if b.is_empty():
		hide_model()
		return
	if card_id == _card_id and _model != null:
		visible = true
		set_process(true)
		return
	if not _load_model(b):
		hide_model()
		return
	_card_id = card_id
	_t = 0.0
	visible = true
	set_process(true)


## 隐藏（保留模型实例，便于再次召唤时零开销复用）
func hide_model() -> void:
	visible = false
	_card_id = 0
	set_process(false)


func is_hidden() -> bool:
	return not visible


# ================= 模型加载与取景 =================

func _load_model(b: Dictionary) -> bool:
	var path := str(b.get("path", ""))
	if path == "" or _failed.has(path):
		return false
	if not ResourceLoader.exists(path):
		_failed[path] = true
		push_warning("3D 怪兽模型缺失：%s（请确认已导入）" % path)
		return false
	var scene: PackedScene = _scene_cache.get(path)
	if scene == null:
		var res := load(path)
		if res is PackedScene:
			scene = res
			_scene_cache[path] = scene
	if scene == null:
		_failed[path] = true
		push_warning("3D 怪兽模型加载失败：%s" % path)
		return false
	if _model != null:
		_model.queue_free()
		_model = null
	_model = scene.instantiate()
	_pivot.add_child(_model)
	_model.rotation_degrees.y = float(b.get("yaw", 0.0))
	var sc := float(b.get("scale", 1.0))
	if not is_equal_approx(sc, 1.0):
		_model.scale = Vector3.ONE * sc
	_pivot.position = Vector3.ZERO
	_frame_camera(b, sc)
	return true


## 根据模型包围盒自动取景：相机正对包围盒中心，按竖直/水平视场取更远距离
func _frame_camera(b: Dictionary, extra_scale: float) -> void:
	var box := _model_aabb(_model)
	if box.size.length() < 0.0001:
		return
	if not is_equal_approx(extra_scale, 1.0):
		box.position *= extra_scale
		box.size *= extra_scale
	var off: Vector3 = b.get("offset", Vector3.ZERO)
	var center := box.get_center() + off * box.size
	var half_h := box.size.y * 0.5
	var half_w := maxf(box.size.x, box.size.z) * 0.5
	var margin := 1.12 * float(b.get("fit", 1.0))
	var tan_half := tan(deg_to_rad(_cam.fov * 0.5))
	var aspect := VIEW_W / VIEW_H
	var dist := maxf((half_h * margin) / tan_half, (half_w * margin) / (tan_half * aspect))
	dist = maxf(dist, 0.001)
	_cam.near = maxf(dist * 0.02, 0.001)
	_cam.far = dist * 8.0 + box.size.length()
	_cam.position = center + Vector3(0.0, 0.0, dist)
	_cam.look_at(center, Vector3.UP)
	_bob_amp = maxf(box.size.y * 0.012, box.size.length() * 0.004)


## 合并模型内部全部网格的包围盒（在模型根节点坐标系中）
func _model_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			var mi := cur as MeshInstance3D
			var local := mi.get_aabb()
			var xf := _relative_transform(root, mi)
			for i in 8:
				var p: Vector3 = xf * local.get_endpoint(i)
				if first:
					box = AABB(p, Vector3.ZERO)
					first = false
				else:
					box = box.expand(p)
		for ch in cur.get_children():
			stack.push_back(ch)
	return box


## 节点相对于 root 的变换（累积到 root 之下，不含 root 自身变换）
func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		var n3 := cur as Node3D
		if n3 != null:
			xf = n3.transform * xf
		cur = cur.get_parent()
	return xf


# ================= 全息浮动动画 =================

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	# 轻微上下浮动 + 缓慢左右摇摆，营造悬浮全息感
	_pivot.position.y = sin(_t * 1.7) * _bob_amp
	_pivot.rotation_degrees.y = sin(_t * 0.8) * 5.0
