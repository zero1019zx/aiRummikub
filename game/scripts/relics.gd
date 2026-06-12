## 遗物系统: 数据驱动的被动效果集合
## 持有状态存ids, 各挂载点由main在对应时机查询本管理器
class_name RelicManager
extends RefCounted

## 全部遗物定义: id -> {name, short(图标字), desc, price}
const DEFS := {
	"orange_fever": {"name": "橙色狂热", "short": "橙", "desc": "橙色牌按双倍chips结算", "price": 6},
	"iron_group": {"name": "铁刻印", "short": "刻", "desc": "打出含新牌的刻子额外+10 chips", "price": 5},
	"half_pair": {"name": "半价对子", "short": "对", "desc": "对子按半值计chips(原本为0)", "price": 5},
	"demolisher": {"name": "拆迁办", "short": "拆", "desc": "重组系数 0.5x → 0.8x", "price": 8},
	"land_flag": {"name": "夺地旗", "short": "旗", "desc": "重组对手铺的牌, 每张额外+0.3x", "price": 7},
	"wood_shield": {"name": "木盾", "short": "盾", "desc": "敌方每回合伤害-2", "price": 5},
	"vampire_fang": {"name": "吸血牙", "short": "牙", "desc": "你造成伤害的20%转为体力", "price": 7},
	"greedy_hand": {"name": "贪婪之手", "short": "手", "desc": "每回合多摸1张牌", "price": 6},
	"recycler": {"name": "回收商", "short": "收", "desc": "换走的牌返还50%面值, 计入下回合chips", "price": 5},
	"smoke_bomb": {"name": "烟雾弹", "short": "烟", "desc": "敌方摸牌有25%概率落空", "price": 6},
	"double_pair": {"name": "双对执照", "short": "双", "desc": "每回合可打出2个对子", "price": 4},
	"piggy_bank": {"name": "存钱罐", "short": "罐", "desc": "过层时每5金存款产1利息(上限5)", "price": 5},
}

var owned: Array = [] # 持有的遗物id

func has(id: String) -> bool:
	return owned.has(id)

func add(id: String) -> void:
	if not owned.has(id):
		owned.append(id)

## 商店供货: 未持有的遗物中随机取n个
func shop_offers(n: int) -> Array:
	var pool: Array = []
	for id in DEFS.keys():
		if not owned.has(id):
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, min(n, pool.size()))

# ============ 挂载点 ============

## A: 单个牌组的chips(只计新牌)。对子默认0, 半价对子按半值。
func chips_for_set(kind: String, values: Array, new_flags: Array, defs: Array) -> int:
	var c := 0
	var any_new := false
	for i in defs.size():
		if not new_flags[i]:
			continue
		any_new = true
		var v := int(values[i])
		if has("orange_fever") and not defs[i].joker and defs[i].color == 2:
			v *= 2
		if kind == "pair":
			v = int(v / 2.0) if has("half_pair") else 0
		c += v
	if kind == "group" and any_new and has("iron_group"):
		c += 10
	return c

## B: 重组系数
func mult_step() -> float:
	return 0.8 if has("demolisher") else 0.5

## B: 重组对手牌的额外倍率
func enemy_reorg_bonus(n: int) -> float:
	return 0.3 * n if has("land_flag") else 0.0

## C: 敌方对我方的伤害修正
func modify_enemy_damage(dmg: int) -> int:
	if has("wood_shield"):
		return max(0, dmg - 2)
	return dmg

## C: 吸血回体
func lifesteal(dealt: int) -> int:
	return int(dealt * 0.2) if has("vampire_fang") else 0

## D: 每回合摸牌数
func draw_count(base: int) -> int:
	return base + (1 if has("greedy_hand") else 0)

## D: 换牌返还chips
func exchange_refund(defs: Array) -> int:
	if not has("recycler"):
		return 0
	var s := 0
	for d in defs:
		if not d.joker:
			s += int(d.num)
	return int(s / 2.0)

## E: 敌方摸牌是否落空
func enemy_draw_blocked() -> bool:
	return has("smoke_bomb") and randf() < 0.25

## F: 每回合对子上限
func pair_limit() -> int:
	return 2 if has("double_pair") else 1

## G: 过层利息
func interest(gold: int) -> int:
	if not has("piggy_bank"):
		return 0
	return min(5, int(gold / 5.0))
