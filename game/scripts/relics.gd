## 肉鸽成长系统接口(为后续爬塔循环预留)
## 遗物 = 永久被动, 通过hook修改对局数值; 消耗品 = 一次性主动效果
class_name RelicManager
extends RefCounted

var relics: Array = []      # 持有的遗物 [{id, name, desc, hooks...}]
var consumables: Array = [] # 持有的消耗品

## Hook: 回合计分后调用, 可修改得分。返回修改后的分数。
func on_turn_scored(base_score: int, context: Dictionary) -> int:
	var s := base_score
	for r in relics:
		if r.has("modify_score"):
			s = r.modify_score.call(s, context)
	return s

## Hook: 抽牌数修改
func draw_count(base: int) -> int:
	var n := base
	for r in relics:
		if r.has("modify_draw"):
			n = r.modify_draw.call(n)
	return n

## 示例遗物(暂未接入商店, 供后续爬塔层奖励使用)
static func sample_relics() -> Array:
	var run_master := {"id": "run_master", "name": "顺子大师", "desc": "顺子计分 x1.5"}
	run_master["modify_score"] = func (s: int, ctx: Dictionary) -> int:
		return int(s * 1.5) if ctx.get("has_run", false) else s
	var greedy_hand := {"id": "greedy_hand", "name": "贪婪之手", "desc": "每回合多抽1张"}
	greedy_hand["modify_draw"] = func (n: int) -> int:
		return n + 1
	return [run_master, greedy_hand]
