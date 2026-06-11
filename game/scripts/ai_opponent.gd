## 对战模式的贪心AI (v0)
## 能力: 打出手牌中的刻子/顺子、接龙已有顺子两端、补对子成刻子;
## 实在无动作时打1个对子排水。暂不会重组桌面(后续版本加)。Joker留手不打。
class_name AiOpponent
extends RefCounted

## hand: 敌方手牌defs; groups: [{kind, values, defs, ...}] 当前桌面合法牌组
## 返回 {sets: [[def...]], exts: [{def, gi, side}], pairs: [[def,def]]}
static func plan(hand: Array, groups: Array) -> Dictionary:
	var work: Array = []
	for d in hand:
		if not d.joker:
			work.append(d)

	# 1) 反复找手牌中的三张组
	var sets: Array = []
	var found := true
	while found:
		found = false
		var n := work.size()
		for a in n:
			if found:
				break
			for b in range(a + 1, n):
				if found:
					break
				for c in range(b + 1, n):
					var combo := _order_set([work[a], work[b], work[c]])
					if not combo.is_empty():
						sets.append(combo)
						work.remove_at(c)
						work.remove_at(b)
						work.remove_at(a)
						found = true
						break

	# 2) 接龙: 顺子两端 / 对子补成刻子
	var exts: Array = []
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		if g.kind == "run":
			var vals: Array = g.values
			if vals.size() < 2:
				continue
			var step: int = 1 if vals[1] > vals[0] else -1
			var color := -1
			for d in g.defs:
				if not d.joker:
					color = d.color
					break
			if color == -1:
				continue
			for st in [["left", int(vals[0]) - step], ["right", int(vals[vals.size() - 1]) + step]]:
				var tnum: int = st[1]
				if tnum < Rules.MIN_NUM or tnum > Rules.MAX_NUM:
					continue
				var idx := _find_tile(work, color, tnum)
				if idx >= 0:
					exts.append({"def": work[idx], "gi": gi, "side": st[0]})
					work.remove_at(idx)
		elif g.kind == "pair":
			var d0: Dictionary = g.defs[0]
			var d1: Dictionary = g.defs[1]
			if d0.joker or d1.joker or d0.color == d1.color:
				continue # 同色对/含Joker的对子无法补成刻子
			var missing: int = 3 - int(d0.color) - int(d1.color)
			var idx2 := _find_tile(work, missing, int(d0.num))
			if idx2 >= 0:
				exts.append({"def": work[idx2], "gi": gi, "side": "right"})
				work.remove_at(idx2)

	# 3) 无任何动作时: 打1个对子排水(优先小数字)
	var pairs: Array = []
	if sets.is_empty() and exts.is_empty():
		work.sort_custom(func (x, y): return x.num < y.num)
		for a in work.size():
			if not pairs.is_empty():
				break
			for b in range(a + 1, work.size()):
				if work[a].num == work[b].num:
					pairs.append([work[a], work[b]])
					break
	return {"sets": sets, "exts": exts, "pairs": pairs}

## 三张是否成组; 顺子返回升序排列后的defs, 刻子原序, 不合法返回空数组
static func _order_set(combo: Array) -> Array:
	if combo[0].num == combo[1].num and combo[1].num == combo[2].num:
		if combo[0].color != combo[1].color and combo[1].color != combo[2].color \
				and combo[0].color != combo[2].color:
			return combo
		return []
	if combo[0].color == combo[1].color and combo[1].color == combo[2].color:
		var s := combo.duplicate()
		s.sort_custom(func (x, y): return x.num < y.num)
		if s[1].num == s[0].num + 1 and s[2].num == s[1].num + 1:
			return s
	return []

static func _find_tile(work: Array, color: int, num: int) -> int:
	for i in work.size():
		if not work[i].joker and work[i].color == color and work[i].num == num:
			return i
	return -1
