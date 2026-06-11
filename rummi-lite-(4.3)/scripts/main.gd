## 主场景: 分数挑战模式单局 (Balatro式)
## 在限定回合内, 通过出牌+桌面自由重组凑分, 达到目标分数即获胜
extends Control

# ---------- 布局常量 (720x1280 竖屏) ----------
const TILE_SIZE := Vector2(70, 94)
const SX := 76.0
const SY := 104.0
const TABLE_COLS := 9
const TABLE_ROWS := 6
const RACK_COLS := 9
const RACK_ROWS := 2
const TABLE_ORIGIN := Vector2(21, 170)
const RACK_ORIGIN := Vector2(21, 845)
const DROP_RADIUS := 70.0

# ---------- 对局常量 ----------
const HAND_START := 8
const MAX_TURNS := 10
const TARGET_SCORE := 90
const EMPTY_HAND_BONUS := 20
const HINTS_TOTAL := 3

# ---------- 配色 ----------
const COL_BG := Color("#f7ead2")
const COL_FELT := Color("#3f8f4f")
const COL_FELT_SLOT := Color("#357a43")
const COL_WOOD := Color("#8b5a2b")
const COL_WOOD_SLOT := Color("#7a4d22")
const COL_TOPBAR := Color("#2e7d44")
const COL_BTN_PLAY := Color("#2ecc71")
const COL_BTN_SORT := Color("#3498db")
const COL_BTN_HINT := Color("#f1c40f")
const COL_BTN_UNDO := Color("#e67e22")

# ---------- 状态 ----------
var deck: Array = []
var table_grid: Array = [] # [row][col] -> TileNode 或 null
var rack_grid: Array = []
var score := 0
var turn := 1
var hints_left := HINTS_TOTAL
var sort_by_color := true
var game_over := false
var snapshot: Array = []
var relic_mgr := RelicManager.new()

# ---------- UI 引用 ----------
var tiles_layer: Control
var lbl_turn: Label
var lbl_score: Label
var lbl_target: Label
var lbl_deck: Label
var lbl_hint_count: Label
var toast_label: Label
var btn_play: Button

func _ready() -> void:
	_build_static_ui()
	_start_game()

# ============================================================
# 静态UI搭建
# ============================================================
func _build_static_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 顶栏
	var topbar := _rounded_panel(Rect2(10, 12, 700, 126), COL_TOPBAR, 18)
	add_child(topbar)
	lbl_turn = _make_label("回合 1/%d" % MAX_TURNS, 30, Color.WHITE)
	lbl_turn.position = Vector2(36, 26)
	topbar.add_child(lbl_turn)
	lbl_deck = _make_label("牌库 0", 30, Color("#cfe8d4"))
	lbl_deck.position = Vector2(36, 70)
	topbar.add_child(lbl_deck)
	lbl_score = _make_label("0", 56, Color("#ffe27a"))
	lbl_score.position = Vector2(0, 22)
	lbl_score.size = Vector2(700, 64)
	lbl_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	topbar.add_child(lbl_score)
	var score_cap := _make_label("得分", 22, Color("#cfe8d4"))
	score_cap.position = Vector2(0, 88)
	score_cap.size = Vector2(700, 28)
	score_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	topbar.add_child(score_cap)
	lbl_target = _make_label("目标 %d" % TARGET_SCORE, 30, Color.WHITE)
	lbl_target.position = Vector2(520, 26)
	topbar.add_child(lbl_target)

	# 桌面 (绿绒)
	var felt := _rounded_panel(Rect2(10, 152, 700, 666), COL_FELT, 18)
	add_child(felt)
	for r in TABLE_ROWS:
		for c in TABLE_COLS:
			var slot := _rounded_panel(Rect2(_slot_pos("table", r, c) - felt.position, TILE_SIZE), COL_FELT_SLOT, 10)
			felt.add_child(slot)

	# 牌架 (木质)
	var rackp := _rounded_panel(Rect2(10, 828, 700, 232), COL_WOOD, 18)
	add_child(rackp)
	for r in RACK_ROWS:
		for c in RACK_COLS:
			var slot := _rounded_panel(Rect2(_slot_pos("rack", r, c) - rackp.position, TILE_SIZE), COL_WOOD_SLOT, 10)
			rackp.add_child(slot)

	# 按钮行
	btn_play = _make_button("出牌", COL_BTN_PLAY, Rect2(12, 1086, 222, 84))
	btn_play.pressed.connect(_on_end_turn)
	add_child(btn_play)
	var btn_sort := _make_button("整理", COL_BTN_SORT, Rect2(248, 1086, 146, 84))
	btn_sort.pressed.connect(_on_sort)
	add_child(btn_sort)
	var btn_hint := _make_button("提示", COL_BTN_HINT, Rect2(408, 1086, 146, 84))
	btn_hint.pressed.connect(_on_hint)
	add_child(btn_hint)
	lbl_hint_count = _make_label(str(HINTS_TOTAL), 22, Color.WHITE)
	lbl_hint_count.position = Vector2(118, 6)
	var hint_badge := _rounded_panel(Rect2(112, -8, 34, 34), Color("#e74c3c"), 17)
	lbl_hint_count.position = Vector2(0, 2)
	lbl_hint_count.size = Vector2(34, 30)
	lbl_hint_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_badge.add_child(lbl_hint_count)
	btn_hint.add_child(hint_badge)
	var btn_undo := _make_button("撤回", COL_BTN_UNDO, Rect2(568, 1086, 140, 84))
	btn_undo.pressed.connect(_on_undo)
	add_child(btn_undo)

	# 提示文字层
	toast_label = _make_label("", 30, Color.WHITE)
	toast_label.size = Vector2(640, 60)
	toast_label.position = Vector2(40, 1190)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_outline_color", Color("#5b3a14"))
	toast_label.add_theme_constant_override("outline_size", 8)
	add_child(toast_label)

	# 牌的容器层(置顶)
	tiles_layer = Control.new()
	tiles_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	tiles_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tiles_layer)

func _rounded_panel(rect: Rect2, color: Color, radius: int) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _make_button(text: String, color: Color, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(16)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 3)
	b.add_theme_stylebox_override("normal", sb)
	var sb2: StyleBoxFlat = sb.duplicate()
	sb2.bg_color = color.darkened(0.15)
	b.add_theme_stylebox_override("pressed", sb2)
	b.add_theme_stylebox_override("hover", sb)
	return b

# ============================================================
# 对局流程
# ============================================================
func _start_game() -> void:
	deck = Rules.build_deck()
	table_grid = []
	for r in TABLE_ROWS:
		table_grid.append([])
		for c in TABLE_COLS:
			table_grid[r].append(null)
	rack_grid = []
	for r in RACK_ROWS:
		rack_grid.append([])
		for c in RACK_COLS:
			rack_grid[r].append(null)
	for _i in HAND_START:
		_draw_to_rack()
	_take_snapshot()
	_update_hud()

func _draw_to_rack() -> bool:
	if deck.is_empty():
		return false
	for r in RACK_ROWS:
		for c in RACK_COLS:
			if rack_grid[r][c] == null:
				var def: Dictionary = deck.pop_back()
				var tile := _create_tile(def, "rack", r, c)
				rack_grid[r][c] = tile
				return true
	return false # 牌架已满

func _create_tile(def: Dictionary, zone: String, row: int, col: int) -> TileNode:
	var tile := TileNode.new()
	tile.setup(def, TILE_SIZE)
	tile.zone = zone
	tile.home_zone = zone
	tile.row = row
	tile.col = col
	tile.position = _slot_pos(zone, row, col)
	tile.pick_started.connect(_on_tile_picked)
	tile.drop_attempt.connect(_on_tile_dropped)
	tiles_layer.add_child(tile)
	return tile

func _slot_pos(zone: String, r: int, c: int) -> Vector2:
	var origin := TABLE_ORIGIN if zone == "table" else RACK_ORIGIN
	return origin + Vector2(c * SX, r * SY)

func _grid_of(zone: String) -> Array:
	return table_grid if zone == "table" else rack_grid

# ---------- 拖拽 ----------
func _on_tile_picked(tile: TileNode) -> void:
	tiles_layer.move_child(tile, tiles_layer.get_child_count() - 1)

func _on_tile_dropped(tile: TileNode, global_pos: Vector2) -> void:
	var center: Vector2 = global_pos + TILE_SIZE / 2.0
	var best_zone := ""
	var best_r := -1
	var best_c := -1
	var best_dist := DROP_RADIUS
	var zones: Array = ["table"] if tile.home_zone == "table" else ["table", "rack"]
	for z in zones:
		var grid := _grid_of(z)
		var rows: int = TABLE_ROWS if z == "table" else RACK_ROWS
		var cols: int = TABLE_COLS if z == "table" else RACK_COLS
		for r in rows:
			for c in cols:
				var occupied = grid[r][c]
				if occupied != null and occupied != tile:
					continue
				var slot_center: Vector2 = _slot_pos(z, r, c) + TILE_SIZE / 2.0
				var d := center.distance_to(slot_center)
				if d < best_dist:
					best_dist = d
					best_zone = z
					best_r = r
					best_c = c
	if best_zone == "":
		_animate_to_slot(tile, tile.zone, tile.row, tile.col) # 弹回原位
		return
	# 落位
	_grid_of(tile.zone)[tile.row][tile.col] = null
	_grid_of(best_zone)[best_r][best_c] = tile
	tile.zone = best_zone
	tile.row = best_r
	tile.col = best_c
	tile.set_new_highlight(best_zone == "table" and tile.home_zone == "rack")
	_animate_to_slot(tile, best_zone, best_r, best_c)

func _animate_to_slot(tile: TileNode, zone: String, r: int, c: int) -> void:
	var tw := create_tween()
	tw.tween_property(tile, "position", _slot_pos(zone, r, c), 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ---------- 回合结算 ----------
func _on_end_turn() -> void:
	if game_over:
		return
	var groups := _parse_table_groups()
	var checked: Array = []
	var all_valid := true
	for g in groups:
		var defs: Array = []
		for t in g:
			defs.append(t.def)
		var res := Rules.check_set(defs)
		if not res.valid:
			all_valid = false
			for t in g:
				t.flash_bad()
		else:
			checked.append({"tiles": g, "res": res})
	if not all_valid:
		_toast("桌面有不合法的牌组!")
		return

	var new_count := 0
	for row in table_grid:
		for t in row:
			if t != null and t.is_new:
				new_count += 1

	if new_count == 0:
		_toast("本回合未出牌, 摸1张")
	else:
		var sets_arg: Array = []
		var has_new_run := false
		for entry in checked:
			var flags: Array = []
			var defs2: Array = []
			var entry_has_new := false
			for t in entry.tiles:
				flags.append(t.is_new)
				defs2.append(t.def)
				if t.is_new:
					entry_has_new = true
			if entry_has_new and entry.res.kind == "run":
				has_new_run = true
			sets_arg.append({"tiles": defs2, "values": entry.res.values, "new_flags": flags})
		var gained := Rules.score_sets(sets_arg)
		gained = relic_mgr.on_turn_scored(gained, {"has_run": has_new_run})
		score += gained
		_toast("+%d 分!" % gained)

	# 锁定桌面牌
	for row in table_grid:
		for t in row:
			if t != null:
				t.home_zone = "table"
				t.set_new_highlight(false)

	# 空手奖励
	if _rack_count() == 0:
		score += EMPTY_HAND_BONUS
		_toast("手牌打空! 奖励 +%d, 补5张" % EMPTY_HAND_BONUS)
		for _i in 5:
			_draw_to_rack()

	if score >= TARGET_SCORE:
		_update_hud()
		_show_result(true)
		return

	var draws := relic_mgr.draw_count(1)
	for _i in draws:
		_draw_to_rack()

	if turn >= MAX_TURNS:
		_update_hud()
		_show_result(false)
		return

	turn += 1
	_take_snapshot()
	_update_hud()

## 按行扫描, 连续相邻的牌为一组
func _parse_table_groups() -> Array:
	var groups: Array = []
	for r in TABLE_ROWS:
		var current: Array = []
		for c in TABLE_COLS:
			var t = table_grid[r][c]
			if t != null:
				current.append(t)
			elif not current.is_empty():
				groups.append(current)
				current = []
		if not current.is_empty():
			groups.append(current)
	return groups

func _rack_count() -> int:
	var n := 0
	for row in rack_grid:
		for t in row:
			if t != null:
				n += 1
	return n

# ---------- 整理 / 提示 / 撤回 ----------
@warning_ignore("integer_division")
func _on_sort() -> void:
	if game_over:
		return
	var tiles: Array = []
	for row in rack_grid:
		for t in row:
			if t != null:
				tiles.append(t)
	if sort_by_color:
		tiles.sort_custom(func (a, b):
			if a.def.joker != b.def.joker:
				return b.def.joker
			if a.def.color != b.def.color:
				return a.def.color < b.def.color
			return a.def.num < b.def.num)
	else:
		tiles.sort_custom(func (a, b):
			if a.def.joker != b.def.joker:
				return b.def.joker
			if a.def.num != b.def.num:
				return a.def.num < b.def.num
			return a.def.color < b.def.color)
	sort_by_color = not sort_by_color
	for r in RACK_ROWS:
		for c in RACK_COLS:
			rack_grid[r][c] = null
	var i := 0
	for t in tiles:
		var r := i / RACK_COLS
		var c := i % RACK_COLS
		rack_grid[r][c] = t
		t.zone = "rack"
		t.row = r
		t.col = c
		_animate_to_slot(t, "rack", r, c)
		i += 1

func _on_hint() -> void:
	if game_over:
		return
	if hints_left <= 0:
		_toast("提示次数已用完")
		return
	var hand_tiles: Array = []
	for row in rack_grid:
		for t in row:
			if t != null:
				hand_tiles.append(t)
	var defs: Array = []
	for t in hand_tiles:
		defs.append(t.def)
	var idx := Rules.find_hint(defs)
	if idx.is_empty():
		_toast("手牌中没有可直接组成的牌组")
		return
	hints_left -= 1
	lbl_hint_count.text = str(hints_left)
	for i in idx:
		hand_tiles[i].flash_hint()

func _on_undo() -> void:
	if game_over:
		return
	_restore_snapshot()
	_toast("已撤回到回合开始")

func _take_snapshot() -> void:
	snapshot = []
	for zone in ["table", "rack"]:
		var grid := _grid_of(zone)
		for r in grid.size():
			for c in grid[r].size():
				var t = grid[r][c]
				if t != null:
					snapshot.append({"def": t.def, "zone": zone, "row": r, "col": c})

func _restore_snapshot() -> void:
	for child in tiles_layer.get_children():
		child.queue_free()
	for r in TABLE_ROWS:
		for c in TABLE_COLS:
			table_grid[r][c] = null
	for r in RACK_ROWS:
		for c in RACK_COLS:
			rack_grid[r][c] = null
	for rec in snapshot:
		var tile := _create_tile(rec.def, rec.zone, rec.row, rec.col)
		_grid_of(rec.zone)[rec.row][rec.col] = tile

# ---------- HUD / 结算 ----------
func _update_hud() -> void:
	lbl_turn.text = "回合 %d/%d" % [turn, MAX_TURNS]
	lbl_score.text = str(score)
	lbl_deck.text = "牌库 %d" % deck.size()

func _toast(msg: String) -> void:
	toast_label.text = msg
	toast_label.modulate = Color.WHITE
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(toast_label, "modulate:a", 0.0, 0.5)

func _show_result(win: bool) -> void:
	game_over = true
	for child in tiles_layer.get_children():
		if child is TileNode:
			(child as TileNode).draggable = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := _rounded_panel(Rect2(80, 420, 560, 400), Color("#fdf6e8"), 24)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var title := _make_label("胜利!" if win else "挑战失败", 56, COL_TOPBAR if win else Color("#c0392b"))
	title.size = Vector2(560, 80)
	title.position = Vector2(0, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	var detail := _make_label("最终得分 %d / %d" % [score, TARGET_SCORE], 34, Color("#5b3a14"))
	detail.size = Vector2(560, 50)
	detail.position = Vector2(0, 160)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(detail)
	var btn := _make_button("再来一局", COL_BTN_PLAY, Rect2(155, 260, 250, 84))
	btn.pressed.connect(func (): get_tree().reload_current_scene())
	panel.add_child(btn)
