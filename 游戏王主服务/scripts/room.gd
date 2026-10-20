class_name Room
extends RefCounted

## 服务端上的一个决斗房间（1v1 真人对战：双方玩家轮流操作）

var id := ""
var name := ""
var owner_id := ""
var max_players := 2
var state := "waiting"        # waiting / dueling / finished
var members: Array = []       # [player_id]
var created_at := 0.0
var turn := 0
var phase := "等待玩家"
var logs: Array = []
var ready := {}               # player_id -> bool
var lp := {}                  # player_id -> int
var hand := {}                # player_id -> int（手牌数量，兼容旧视图）

# ---- 真人对战回合状态（由玩家操作推进）----
var active_pid := ""          # 当前回合玩家 id（当前轮到操作的一方）
var summon_used := false      # 当前回合玩家是否已通常召唤（每回合 1 次）
var spell_used := false       # 当前回合玩家是否已放置魔法/陷阱卡（每回合 1 次）
var attacked: Array = []      # 当前回合玩家已攻击过的怪兽卡 id（每只怪兽每回合 1 次）

# ---- 真实卡牌数据（CardDB 提供卡图与属性）----
var deck_cards := {}          # player_id -> Array[int] 剩余卡组（[0] 为牌顶）
var hand_cards := {}          # player_id -> Array[int] 手牌
var field_monsters := {}      # player_id -> Array[int] 场上怪兽（固定 5 格，0 = 空位）
var field_spells := {}        # player_id -> Array[int] 魔陷区（固定 5 格，0 = 空位；魔法/陷阱放置后展示，不参与战斗结算）
var grave_cards := {}         # player_id -> Array[int] 墓地（末尾为最上一张）
var extra_deck := {}          # player_id -> Array[int] 额外卡组（独立存放，不并入主卡组、不参与抽卡）

# ---- 玩家自选卡包（客户端上传的牌组内容，开战时优先使用）----
var pack_choice := {}         # player_id -> {name:String, deck:Array[int], extra:Array[int]}


func add_log(text: String) -> void:
	logs.append(text)
	if logs.size() > 40:
		logs = logs.slice(logs.size() - 40)
