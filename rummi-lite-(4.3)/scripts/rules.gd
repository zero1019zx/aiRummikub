## 纯规则逻辑(无UI依赖,可headless单测)
## 牌的数据结构: Dictionary { "color": int(0红/1蓝/2橙), "num": int(1-7), "joker": bool }
class_name Rules
extends RefCounted

const NUM_COLORS := 3
const MIN_NUM := 1
const MAX_NUM := 7
const COPIES := 2
const MIN_SET := 3

## 生成43张轻量牌池: 1-7 x 3色 x 2份 + 1 Joker
static func build_deck() -> Array:
	var deck: Array = []
	for c in NUM_COLORS:
		for n in range(MIN_NUM, MAX_NUM + 1):
			for _i in COPIES:
				deck.append({"color": c, "num": n, "joker": false})
	deck.append({"color": -1, "num": 0, "joker": true})
	deck.shuffle()
	return deck

## 校验一组连续摆放的牌是否为合法牌组
## 返回 { "valid": bool, "kind": "run"/"group"/"", "values": Array[int] 每张牌的计分值(Joker取代表值) }
static func check_set(tiles: Array) -> Dictionary:
	var bad := {"valid": false, "kind": "", "values": []}
	if tiles.size() < MIN_SET:
		return bad
	var g := _check_group(tiles)
	if g.valid:
		return g
	var r := _check_run(tiles)
	if r.valid:
		return r
	return bad

## 刻子: 同数字不同颜色(3色下恰好3张), Joker补任意色
static func _check_group(tiles: Array) -> Dictionary:
	if tiles.size() != NUM_COLORS:
		return {"valid": false}
	var num := -1
	var colors := {}
	for t in tiles:
		if t.joker:
			continue
		if num == -1:
			num = t.num
		elif t.num != num:
			return {"valid": false}
		if colors.has(t.color):
			return {"valid": false}
		colors[t.color] = true
	if num == -1:
		return {"valid": false} # 全是Joker(本牌池只有1张,不可能)
	var values: Array = []
	for t in tiles:
		values.append(num)
	return {"valid": true, "kind": "group", "values": values}

## 顺子: 同色连续数字,按摆放顺序(升序或降序均可), Joker按位置取隐含值
static func _check_run(tiles: Array) -> Dictionary:
	if tiles.size() > MAX_NUM - MIN_NUM + 1:
		return {"valid": false}
	for dir in [1, -1]:
		var res := _check_run_dir(tiles, dir)
		if res.valid:
			return res
	return {"valid": false}

static func _check_run_dir(tiles: Array, dir: int) -> Dictionary:
	var color := -1
	var anchor_idx := -1
	var anchor_num := 0
	for i in tiles.size():
		var t: Dictionary = tiles[i]
		if t.joker:
			continue
		if color == -1:
			color = t.color
			anchor_idx = i
			anchor_num = t.num
		elif t.color != color:
			return {"valid": false}
	if anchor_idx == -1:
		return {"valid": false}
	var values: Array = []
	for i in tiles.size():
		var expected := anchor_num + (i - anchor_idx) * dir
		if expected < MIN_NUM or expected > MAX_NUM:
			return {"valid": false}
		var t: Dictionary = tiles[i]
		if not t.joker and t.num != expected:
			return {"valid": false}
		values.append(expected)
	return {"valid": true, "kind": "run", "values": values}

## 计分: 新打出的牌按面值计分(Joker取代表值), 牌组每超过3张额外+2
## sets: Array of { "tiles": Array, "values": Array, "new_flags": Array[bool] }
static func score_sets(sets: Array) -> int:
	var total := 0
	for s in sets:
		var has_new := false
		for i in s.tiles.size():
			if s.new_flags[i]:
				has_new = true
				total += int(s.values[i])
		if has_new and s.tiles.size() > MIN_SET:
			total += (s.tiles.size() - MIN_SET) * 2
	return total

## 在手牌中寻找一组可直接打出的牌(提示用)
## 返回手牌下标数组(长度3), 找不到返回空数组
static func find_hint(hand: Array) -> Array:
	var n := hand.size()
	for a in n:
		for b in range(a + 1, n):
			for c in range(b + 1, n):
				var combo := [hand[a], hand[b], hand[c]]
				if check_set(combo).valid:
					return [a, b, c]
				# 顺子可能需要重排顺序再试
				for perm in [[0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]:
					var p := [combo[perm[0]], combo[perm[1]], combo[perm[2]]]
					if check_set(p).valid:
						return [a, b, c]
	return []
