class_name MonsterModelDB
extends RefCounted
## 3D 怪兽模型绑定表（仅服务端使用）
## 密码 id（passcode）→ 3D 模型配置：观战页中该卡位于怪兽区时，
## 在对应的「卡片格子上方」显示 3D 怪兽模型（全息投影效果）。
##
## 新增一个怪兽模型的方法：
##   1. 把 .fbx / .glb 放进 assets/models/ 目录，跑一次 Godot 导入
##      （编辑器会自动导入；命令行可执行 --headless --import）；
##   2. 在下方 BINDINGS 里加一条：密码id → {配置}。
## 配置字段说明：
##   name   显示名（日志/提示用）
##   path   res:// 资源路径（.fbx / .glb / .tscn 均可）
##   yaw    朝向修正（度）：模型背对镜头时设 180
##   scale  额外缩放（模型自身比例异常时微调，一般为 1.0）
##   fit    取景系数：1.0 默认框满，越大留白越多（0.9 更满）
##   offset 取景中心微调（相对包围盒尺寸的倍数，如 Vector3(0, 0.08, 0) 整体上移）

const BINDINGS := {
	38033121: {   # 黑魔导女孩（Dark Magician Girl），ATK 2000 / DEF 1700
		"name": "黑魔导女孩",
		"path": "res://assets/models/dm_girl.fbx",
		"yaw": 0.0,
		"scale": 1.0,
		"fit": 1.0,
		"offset": Vector3.ZERO,
	},
}


## 查询某张卡（密码 id）的模型绑定；无绑定返回空字典
static func binding_for(card_id: int) -> Dictionary:
	var v = BINDINGS.get(card_id)
	return v if v is Dictionary else {}


## 某张卡是否绑定了 3D 模型
static func has_binding(card_id: int) -> bool:
	return BINDINGS.has(card_id)


## 绑定数量（管理界面显示用）
static func binding_count() -> int:
	return BINDINGS.size()
