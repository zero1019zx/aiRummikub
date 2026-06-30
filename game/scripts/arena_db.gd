## 资产注册表 / 加载组件
## 把 data/*.json (bosses / relics / skills / arena_balance) 读进来, 校验, 暴露查询接口。
## 用法: var DB := ArenaDB.new(); DB.load_all(); var b := DB.boss_for_layer(3)
## 改平衡只改 JSON; 这层只负责加载与查询, 不写死任何数值。
class_name ArenaDB
extends RefCounted

const DATA_DIR := "res://data/"

var balance: Dictionary = {}
var bosses: Array = []          # 顺序保留
var bosses_by_id: Dictionary = {}
var relics: Array = []
var relics_by_id: Dictionary = {}
var skills: Array = []
var skills_by_id: Dictionary = {}

var errors: Array = []          # 加载/校验问题, 便于开发期排查

func load_all() -> bool:
	errors.clear()
	balance = _dict(_load_json("arena_balance.json", {}))
	bosses = _arr(_load_json("bosses.json", {}), "bosses")
	relics = _arr(_load_json("relics.json", {}), "relics")
	skills = _arr(_load_json("skills.json", {}), "skills")
	_index()
	_validate()
	if errors.is_empty():
		print("ArenaDB OK: bosses=%d relics=%d skills=%d" % [bosses.size(), relics.size(), skills.size()])
	else:
		push_warning("ArenaDB 加载问题: " + str(errors))
	return errors.is_empty()

func _dict(v) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}

func _arr(v, key: String) -> Array:
	if v is Dictionary and v.has(key) and v[key] is Array:
		var a: Array = v[key]
		return a
	return []

func _load_json(fname: String, fallback):
	var path := DATA_DIR + fname
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("打不开 %s (err %d)" % [fname, FileAccess.get_open_error()])
		return fallback
	var txt := f.get_as_text()
	var data = JSON.parse_string(txt)
	if data == null:
		errors.append("%s 解析失败(JSON)" % fname)
		return fallback
	return data

func _index() -> void:
	bosses_by_id.clear(); relics_by_id.clear(); skills_by_id.clear()
	for b in bosses:
		bosses_by_id[b.get("id", "")] = b
	for r in relics:
		relics_by_id[r.get("id", "")] = r
	for s in skills:
		skills_by_id[s.get("id", "")] = s

# ---------- 查询 ----------

## 该层可投放的 boss 列表(按 role 可再筛选)
func bosses_for_layer(layer: int, role := "") -> Array:
	var out: Array = []
	for b in bosses:
		var hit := false
		for L in b.get("layers", []):
			if int(L) == layer:   # 兼容JSON把数字解析成float的情况
				hit = true
				break
		if hit and (role == "" or String(b.get("role", "")) == role):
			out.append(b)
	return out

func boss(id: String) -> Dictionary:
	return bosses_by_id.get(id, {})

## boss 总血量(支持 hp 或 hp_segments)
func boss_total_hp(b: Dictionary) -> int:
	if b.has("hp_segments"):
		var s := 0
		for h in b["hp_segments"]:
			s += int(h)
		return s
	return int(b.get("hp", 0))

## 把 phases 的 hp_share 转成具体血量边界(用于阶段门)
func boss_phase_floors(b: Dictionary) -> Array:
	var total := boss_total_hp(b)
	var floors: Array = []
	var acc := 0.0
	var phs: Array = b.get("phases", [])
	# floors[i] = 打完第i阶段后 boss 剩余血量(阶段门: 本阶段单击不可击穿到下一阶段)
	for i in range(phs.size()):
		acc += float(phs[i].get("hp_share", 1.0 / max(phs.size(), 1)))
		floors.append(int(round(total * (1.0 - acc))))
	if not floors.is_empty():
		floors[floors.size() - 1] = 0
	return floors

## 适用某模式的遗物(商店配池用); 可按 category 再筛
func relics_for_mode(mode: String, category := "") -> Array:
	var out: Array = []
	for r in relics:
		if r.get("modes", []).has(mode) and (category == "" or r.get("category", "") == category):
			out.append(r)
	return out

func relic(id: String) -> Dictionary:
	return relics_by_id.get(id, {})

func skills_for_mode(mode: String) -> Array:
	var out: Array = []
	for s in skills:
		if s.get("modes", []).has(mode):
			out.append(s)
	return out

func skill(id: String) -> Dictionary:
	return skills_by_id.get(id, {})

func player_cfg() -> Dictionary:
	return balance.get("player", {})

func shape_score_table() -> Dictionary:
	return balance.get("scoring", {}).get("shape_score", {})

# ---------- 校验(开发期) ----------

func _validate() -> void:
	var known_mech := ["resist", "armor", "cap_hit_pct", "ban_pair", "nullify_shape",
		"shape_mod", "dirty_color", "freeze_chain", "charge", "overflow_reflect",
		"pollute_deck", "single_target_no_splash", "summon"]
	for b in bosses:
		if not b.has("hp") and not b.has("hp_segments"):
			errors.append("boss缺血量: " + str(b.get("id", "?")))
		var share := 0.0
		for ph in b.get("phases", []):
			share += float(ph.get("hp_share", 0.0))
			for m in ph.get("mechanics", []):
				if not known_mech.has(m.get("type", "")):
					errors.append("未知机制 '%s' @ boss %s" % [m.get("type", ""), b.get("id", "?")])
		if not b.get("phases", []).is_empty() and abs(share - 1.0) > 0.001:
			errors.append("boss阶段hp_share合计!=1: %s (%.2f)" % [b.get("id", "?"), share])
	for r in relics:
		if not r.has("hook"):
			errors.append("遗物缺hook: " + str(r.get("id", "?")))
	for s in skills:
		if not s.get("effect", {}).has("type"):
			errors.append("技能缺effect.type: " + str(s.get("id", "?")))
