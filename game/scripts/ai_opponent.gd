## 对战模式AI (v1: 分档人格)
## cfg: {pulls: bool 会拆桌面组拿倍率, joker: bool 会用鬼牌}
## 能力: 出刻子/顺子 → (老手+)拆组重组 → 接龙/补刻 → (精英+)鬼牌成组 → 对子排水
class_name AiOpponent
extends RefCounted

## 返回 {sets: [[def...]], exts: [{def,gi,side}], pairs: [[d,d]], pulls: [{gi, take_def, new_defs}]}
static func plan(hand: Array, groups: Array, cfg: Dictionary = {}) -> Dictionary:
	var use_pulls: bool = cfg.get("pulls", false)
	var use_joker: bool = cfg.get("joker", false)
	var work: Array = []
	var jokers: Array = []
	for d in hand:
		if d.joker:
			jokers.append(d)
		else:
			work.append(d)

	# 1) 拆组: 从桌面刻子拉一张配手牌成顺子 / 从长顺子(>=4)拉端牌配手牌成刻子
	var pulls: Array = []
	if use_pulls:
		for gi in groups.size():
			var g: Dictionary = groups[gi]
			if g.kind == "group" and g.defs.size() == 3:
				var done := false
				for m in g.defs:
					if m.joker:
						continue
					for pat in [[m.num - 2, m.num - 1], [m.num - 1, m.num + 1], [m.num + 1, m.num + 2]]:
						var a: int = pat[0]
						var b: int = pat[1]
						if a < Rules.MIN_NUM or b > Rules.MAX_NUM:
							continue
						var ia := _find_tile(work, m.color, a)
						var ib := _find_tile(work, m.color, b)
						if ia >= 0 and ib >= 0 and ia != ib:
							var ta: Dictionary = work[ia]
							var tb: Dictionary = work[ib]
							work.erase(ta)
							work.erase(tb)
							pulls.append({"gi": gi, "take_def": m, "new_defs": [ta, tb]})
							done = true
							break
					if done:
						break
			elif g.kind == "run" and g.defs.size() >= 4:
				for e in [g.defs[0], g.defs[g.defs.size() - 1]]:
					if e.joker:
						continue
					var mates: Array = []
					for t in work:
						if t.num == e.num and t.color != e.color:
							var dup := false
							for x in mates:
								if x.color == t.color:
									dup = true
							if not dup:
								mates.append(t)
					if mates.size() >= 2:
						work.erase(mates[0])
						work.erase(mates[1])
						pulls.append({"gi": gi, "take_def": e, "new_defs": [mates[0], mates[1]]})
						break

	# 2) 手牌三张组(反复提取)
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
	# 2b) 鬼牌成组(精英+): 两张+鬼牌
	if use_joker and not jokers.is_empty():
		var js := _joker_set(work, jokers[0])
		if not js.is_empty():
			sets.append(js)
			for d in js:
				if not d.joker:
					work.erase(d)
			jokers.clear()

	# 3) 接龙扩展
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
				continue
			var missing: int = 3 - int(d0.color) - int(d1.color)
			var idx2 := _find_tile(work, missing, int(d0.num))
			if idx2 >= 0:
				exts.append({"def": work[idx2], "gi": gi, "side": "right"})
				work.remove_at(idx2)

	# 4) 无任何动作: 打1个对子排水
	var pairs: Array = []
	if sets.is_empty() and exts.is_empty() and pulls.is_empty():
		work.sort_custom(func (x, y): return x.num < y.num)
		for a in work.size():
			if not pairs.is_empty():
				break
			for b in range(a + 1, work.size()):
				if work[a].num == work[b].num:
					pairs.append([work[a], work[b]])
					break
	return {"sets": sets, "exts": exts, "pairs": pairs, "pulls": pulls}

## 意图预告文案(用当前局面预演下回合)
static func intent_text(hand: Array, groups: Array, cfg: Dictionary) -> String:
	var p := plan(hand.duplicate(), groups, cfg)
	if not p.pulls.is_empty():
		return "预兆: 酝酿重组突袭!"
	var cnt := 0
	for s in p.sets:
		cnt += s.size()
	cnt += p.exts.size()
	if cnt > 0:
		return "预兆: 准备出牌%d张" % cnt
	if not p.pairs.is_empty():
		return "预兆: 铺垫对子"
	return "预兆: 摸牌观望"

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

## 两张牌+鬼牌凑组: 同色邻近差1/2 或 同数异色
static func _joker_set(work: Array, jk: Dictionary) -> Array:
	for a in work.size():
		for b in range(a + 1, work.size()):
			var x: Dictionary = work[a]
			var y: Dictionary = work[b]
			if x.color == y.color:
				var lo: Dictionary = x if x.num < y.num else y
				var hi: Dictionary = y if x.num < y.num else x
				if hi.num - lo.num == 1: # 鬼牌接端
					if hi.num + 1 <= Rules.MAX_NUM:
						return [lo, hi, jk]
					if lo.num - 1 >= Rules.MIN_NUM:
						return [jk, lo, hi]
				elif hi.num - lo.num == 2: # 鬼牌补中
					return [lo, jk, hi]
			elif x.num == y.num and x.color != y.color:
				return [x, y, jk]
	return []

static func _find_tile(work: Array, color: int, num: int) -> int:
	for i in work.size():
		if not work[i].joker and work[i].color == color and work[i].num == num:
			return i
	return -1
