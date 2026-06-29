## 主场景: 分数挑战模式单局 (Balatro式)
## 在限定回合内, 通过出牌+桌面自由重组凑分, 达到目标分数即获胜
extends Control

# ---------- 布局常量 (720x1280 竖屏) ----------
const TILE_SIZE := Vector2(66, 94)
const SX := 73.0
const SY := 100.0
const TABLE_COLS := 9
const TABLE_ROWS := 6
const RACK_COLS := 9
const RACK_ROWS := 1
const TABLE_ORIGIN := Vector2(35, 188)
const RACK_ORIGIN := Vector2(35, 930)
const DROP_RADIUS := 60.0
# assets_v2 资源根 + 烘焙适配资源(去留白/受控九宫格, Godot端1:1贴图)
const AV2 := "res://assets_v2/"
const FIT := "res://assets_v2/fitted/"

# ---------- 对局常量 ----------
const HAND_START := 8
const MAX_TURNS := 5
const EMPTY_HAND_BONUS := 20
const EXCHANGES_PER_FLOOR := 2
const FLOOR_TARGETS: Array[int] = [40, 60, 85, 125, 180, 260, 380, 550] # 分数挑战目标
const BATTLE_HP: Array[int] = [40, 55, 75, 100, 135, 180, 240, 320] # 对战敌方体力(难度主要靠AI变强)
const SHOP_REROLL_COST := 2
const PLAYER_MAX_HP := 60 # 对战模式我方体力(每层重置); 敌方体力=该层目标分

# ---------- 配色 (对齐视觉设定图) ----------
const COL_BG := Color("#fbf0d9")
const COL_FELT := Color("#4a9d5b")
const COL_FELT_EDGE := Color("#37824a")
const COL_SLOT := Color(0, 0, 0, 0.10)
const COL_WOOD := Color("#9c6633")
const COL_WOOD_EDGE := Color("#774c21")
const COL_PLANK := Color("#b07a45")
const COL_TOPBAR := Color("#2e8b4f")
const COL_TOPBAR_EDGE := Color("#246c3d")
const COL_BTN_PLAY := Color("#3cc25e")
const COL_BTN_SORT := Color("#3b8bea")
const COL_BTN_UNDO := Color("#ef7f33")

# ---------- 状态 ----------
var deck: Array = []
var table_grid: Array = [] # [row][col] -> TileNode 或 null
var rack_grid: Array = []
var score := 0
var turn := 1
var floor_num := 1
var exchanges_left := EXCHANGES_PER_FLOOR
var sort_by_color := true
var game_over := false
var snapshot: Array = []
var start_groups := {} # uid -> 回合开始时所在牌组的成员uid数组(排序)
var next_uid := 0
var exchange_mode := false
var overlay_nodes: Array = []
var relic_mgr := RelicManager.new()
var mode := "score" # "score" 分数挑战 / "battle" 对战原型
var arena_mode := false # 场面争夺: 复用对战框架, 仅替换我方算分(出牌张数×(1+场面牌型分))
var lbl_arena: Label # 场面倍率显示
var arena_scored := {} # uid -> 上次领取倍率时该链的组成签名(面值多重集); 牌不动, 链改组后倍率重新生效
var player_hp := PLAYER_MAX_HP
var enemy_hp := 0
var enemy_hand: Array = []
var gold := 0
var next_chips_bonus := 0 # 回收商等遗物存入下回合的chips
var relic_bar: Control
var busy := false # AI回合/动画期间锁输入

# 新手教程
signal tut_continue
var tut_step := 0
var tut_guides: Array = []
var tut_panel: Panel
var tut_label: Label
var tut_btn: Button
var board_frame: Panel # 回合开始时的棋盘闪框

# 对战HUD部件
var pill: TextureRect # 中央木牌(层/回合)
var badge_l: TextureRect
var badge_r: TextureRect
var lbl_turn_b: Label # 对战模式的层/回合(左上)
var pbar := {} # 我方血条 {root, fill, label, w}
var ebar := {} # 敌方血条
var ebox: Panel # 敌人展示区
var enemy_action: Label # 敌人行动播报

# ---------- UI 引用 ----------
var tiles_layer: Control
var lbl_turn: Label
var lbl_score: Label
var lbl_target: Label
var lbl_deck: Label
var lbl_ex_count: Label
# 底部头像簇 (assets_v2)
var player_av: TextureRect
var lbl_me: Label
var lbl_gold: Label        # 我方金币(我方信息区)
var btn_log: TextureButton # 对战记录按钮(对战右上角)
var battle_log: Array = [] # 逐回合伤害计算记录
# 注: lbl_turn_b 复用为"对手手牌数", 置于对手头像下方
var toast_label: Label
var btn_play: TextureButton
var btn_exchange: TextureButton # 换牌/确认 两态(贴图切换)
var ui_font: FontFile

func _ready() -> void:
	_build_static_ui()
	_show_mode_select()

func _show_mode_select() -> void:
	game_over = true
	tut_panel.visible = false
	for n in overlay_nodes:
		n.queue_free()
	overlay_nodes = []
	for child in tiles_layer.get_children():
		child.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	overlay_nodes.append(dim)
	var panel := _rounded_panel(Rect2(80, 300, 560, 680), Color("#fdf6e8"), 24)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	overlay_nodes.append(panel)
	var title := _make_label("选择模式", 46, Color("#6b4a23"))
	title.size = Vector2(560, 70)
	title.position = Vector2(0, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	var b1 := _make_button("对战模式", "purple", Rect2(130, 120, 300, 86))
	b1.pressed.connect(func ():
		mode = "battle"
		arena_mode = false
		_reset_run()
		floor_num = 1
		_start_floor())
	panel.add_child(b1)
	var b2 := _make_button("分数挑战", "green", Rect2(130, 224, 300, 86))
	b2.pressed.connect(func ():
		mode = "score"
		arena_mode = false
		_reset_run()
		floor_num = 1
		_start_floor())
	panel.add_child(b2)
	var b4 := _make_button("场面争夺", "blue", Rect2(130, 328, 300, 86))
	b4.pressed.connect(func ():
		mode = "battle"      # 复用对战框架(敌人/血量/层数)
		arena_mode = true    # 仅替换我方算分
		_reset_run()
		floor_num = 1
		_start_floor())
	panel.add_child(b4)
	var b3 := _make_button("新手教程", "orange", Rect2(130, 432, 300, 86))
	b3.pressed.connect(func ():
		mode = "tutorial"
		arena_mode = false
		_reset_run()
		floor_num = 1
		_start_floor())
	panel.add_child(b3)

## 新一轮run: 清空跨层成长状态(金币/遗物)
func _reset_run() -> void:
	gold = 0
	next_chips_bonus = 0
	relic_mgr = RelicManager.new()
	_refresh_relic_bar()

func _floor_target() -> int:
	return FLOOR_TARGETS[min(floor_num, FLOOR_TARGETS.size()) - 1]

func _battle_max() -> int:
	if mode == "tutorial":
		return 75
	return BATTLE_HP[min(floor_num, BATTLE_HP.size()) - 1]

## 分层AI人格
func _ai_cfg() -> Dictionary:
	if floor_num <= 2:
		return {"name": "杂兵", "draws": 1, "pulls": false, "joker": false}
	elif floor_num <= 4:
		return {"name": "老手", "draws": 2, "pulls": true, "joker": false}
	elif floor_num <= 6:
		return {"name": "精英", "draws": 2, "pulls": true, "joker": true}
	return {"name": "魔王", "draws": 3, "pulls": true, "joker": true}

# ============================================================
# 静态UI搭建
# ============================================================
func _build_static_ui() -> void:
	# UI字体: Poppins(数字/英文) -> 中文回落到打包的CJK子集字体(Web端没有系统字体)
	ui_font = load("res://assets/fonts/Poppins-Bold.ttf")
	var cjk: FontFile = load("res://assets/fonts/cjk_subset.ttf")
	if ui_font != null:
		var fbs: Array[Font] = []
		if cjk != null:
			fbs.append(cjk)
		fbs.append(ThemeDB.fallback_font)
		ui_font.fallbacks = fbs

	# 整幅背景: 湖畔战斗场景 (assets_v2)
	var bg := _texture_rect(AV2 + "backgrounds/battle_lakeside_background.png", Rect2(0, 0, 720, 1280))
	add_child(bg)

	# --- 棋盘: 毛毡+格位(已删木框, 放大到接近屏宽, 卡牌内收进绿区), Godot端1:1贴图 ---
	var board := _texture_rect(FIT + "felt.png", Rect2(2, 150, 716, 670))
	add_child(board)

	# --- 顶部HUD: 中央木牌(层/回合) ---
	pill = _texture_rect(FIT + "plaque.png", Rect2(254, 8, 212, 89))
	add_child(pill)
	lbl_turn = _make_label("第1层 1/%d" % MAX_TURNS, 25, Color("#4a2f12"))
	lbl_turn.position = Vector2(0, -3)
	lbl_turn.size = Vector2(212, 89)
	lbl_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_turn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pill.add_child(lbl_turn)

	# 牌库角标(分数模式左上 / 对战模式右上, 位置在_start_floor里按模式切换)
	badge_l = _texture_rect(FIT + "badge_deck.png", Rect2(14, 14, 150, 84))
	add_child(badge_l)
	lbl_deck = _make_label("0", 26, Color("#3a2a14"))
	lbl_deck.position = Vector2(48, 0)
	lbl_deck.size = Vector2(93, 84)
	lbl_deck.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_deck.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_l.add_child(lbl_deck)

	# 目标角标(分数模式右上)
	badge_r = _texture_rect(FIT + "badge_turn.png", Rect2(492, 14, 150, 84))
	add_child(badge_r)
	lbl_target = _make_label("目标 %d" % FLOOR_TARGETS[0], 19, Color("#3a2a14"))
	lbl_target.position = Vector2(42, 0)
	lbl_target.size = Vector2(99, 84)
	lbl_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_target.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_r.add_child(lbl_target)

	# --- 对战HUD: 左上敌人展示区(score模式隐藏); 对手手牌数置于头像下方 ---
	ebox = _rounded_panel(Rect2(8, 8, 252, 120), Color(0.06, 0.16, 0.10, 0.42), 18)
	add_child(ebox)
	var eavatar := _texture_rect(AV2 + "avatars/enemy_boar_cave_circle.png", Rect2(6, 6, 84, 84))
	ebox.add_child(eavatar)
	lbl_turn_b = _make_label("手牌 0", 16, Color("#ffe6c8")) # 对手手牌数(头像下方)
	lbl_turn_b.position = Vector2(2, 92)
	lbl_turn_b.size = Vector2(92, 24)
	lbl_turn_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_turn_b.add_theme_color_override("font_outline_color", Color("#3a2412"))
	lbl_turn_b.add_theme_constant_override("outline_size", 3)
	ebox.add_child(lbl_turn_b)
	ebar = _make_hp_bar(Rect2(100, 14, 144, 30), Color("#e84b3c"))
	ebox.add_child(ebar.root)
	enemy_action = _make_label("等待出牌…", 14, Color("#ffe6d6"))
	enemy_action.position = Vector2(100, 50)
	enemy_action.size = Vector2(146, 64)
	enemy_action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ebox.add_child(enemy_action)

	# --- 牌架 (烘焙单排木托盘) ---
	var rackp := _texture_rect(FIT + "rack1.png", Rect2(2, 916, 716, 132))
	add_child(rackp)

	# 右上角: 设置(齿轮) + 对战记录(仅对战, 查看逐回合伤害计算)
	var help_btn := _icon_button(AV2 + "ui/icons/icon_settings.png", Rect2(666, 12, 44, 44), _show_help)
	add_child(help_btn)
	btn_log = _icon_button(AV2 + "ui/icons/icon_menu.png", Rect2(666, 60, 44, 44), _show_battle_log)
	add_child(btn_log)

	# --- 底部玩家簇 (放在牌架之后入树, 头像在最上层, 不被牌架遮挡) ---
	# Combo面板(分数, 居中浮于毛毡下沿)
	var combo := _texture_rect(FIT + "combo.png", Rect2(250, 816, 224, 54))
	add_child(combo)
	lbl_score = _make_label("0", 30, Color("#fff2c4"))
	lbl_score.position = Vector2(75, 0)
	lbl_score.size = Vector2(134, 54)
	lbl_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_score.add_theme_color_override("font_outline_color", Color("#6b3b0c"))
	lbl_score.add_theme_constant_override("outline_size", 4)
	combo.add_child(lbl_score)
	# 场面争夺: 场面倍率显示(木牌下方居中, 仅arena可见)
	lbl_arena = _make_label("场面 ×1", 22, Color("#fff0c0"))
	lbl_arena.position = Vector2(260, 100)
	lbl_arena.size = Vector2(200, 28)
	lbl_arena.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_arena.add_theme_color_override("font_outline_color", Color("#7a3b0c"))
	lbl_arena.add_theme_constant_override("outline_size", 4)
	lbl_arena.visible = false
	add_child(lbl_arena)
	# 玩家头像 + 名字 + 金币 + 血条 + 遗物条
	player_av = _texture_rect(AV2 + "avatars/player_adventurer_circle.png", Rect2(8, 820, 82, 82))
	add_child(player_av)
	lbl_me = _make_label("我", 22, Color.WHITE)
	lbl_me.position = Vector2(96, 814)
	lbl_me.size = Vector2(46, 26)
	lbl_me.add_theme_color_override("font_outline_color", Color("#3a5a2e"))
	lbl_me.add_theme_constant_override("outline_size", 4)
	add_child(lbl_me)
	lbl_gold = _make_label("金币 0", 18, Color("#ffe08a")) # 我方金币(我方信息区)
	lbl_gold.position = Vector2(142, 816)
	lbl_gold.size = Vector2(110, 24)
	lbl_gold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_gold.add_theme_color_override("font_outline_color", Color("#5b3a14"))
	lbl_gold.add_theme_constant_override("outline_size", 3)
	add_child(lbl_gold)
	pbar = _make_hp_bar(Rect2(96, 844, 150, 22), Color("#3cc25e"))
	add_child(pbar.root)
	# 遗物条(技能): 移到我方血条下一排
	relic_bar = Control.new()
	relic_bar.position = Vector2(96, 872)
	relic_bar.size = Vector2(566, 32)
	add_child(relic_bar)

	# --- 按钮行 (出牌/换牌/整理/撤回): 整图烘字按钮 ---
	btn_play = _image_button("btn_play", Rect2(13, 1058, 164, 77), _on_end_turn)
	add_child(btn_play)
	btn_exchange = _image_button("btn_hint", Rect2(190, 1058, 164, 77), _on_exchange)
	add_child(btn_exchange)
	lbl_ex_count = _badge_on(btn_exchange, str(EXCHANGES_PER_FLOOR))
	var btn_sort := _image_button("btn_sort", Rect2(367, 1058, 164, 77), _on_sort)
	add_child(btn_sort)
	var btn_undo := _image_button("btn_undo", Rect2(544, 1058, 164, 77), _on_undo)
	add_child(btn_undo)

	# 提示文字层
	toast_label = _make_label("", 30, Color.WHITE)
	toast_label.size = Vector2(640, 60)
	toast_label.position = Vector2(40, 1126)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_outline_color", Color("#5b3a14"))
	toast_label.add_theme_constant_override("outline_size", 4)
	add_child(toast_label)

	# 牌的容器层(置顶)
	tiles_layer = Control.new()
	tiles_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	tiles_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tiles_layer)

	# 回合开始闪框(毛毡描边, 对齐 felt.png)
	board_frame = Panel.new()
	board_frame.position = Vector2(8, 156)
	board_frame.size = Vector2(704, 658)
	board_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_sb := StyleBoxFlat.new()
	frame_sb.bg_color = Color(0, 0, 0, 0)
	frame_sb.set_corner_radius_all(30)
	frame_sb.set_border_width_all(6)
	frame_sb.border_color = Color("#ffd94d")
	board_frame.add_theme_stylebox_override("panel", frame_sb)
	board_frame.visible = false
	add_child(board_frame)

	# 教程指引面板(默认隐藏)
	tut_panel = _rounded_panel(Rect2(30, 632, 660, 168), Color(0.99, 0.96, 0.9, 0.96), 18)
	tut_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	tut_panel.visible = false
	add_child(tut_panel)
	tut_label = _make_label("", 22, Color("#5b3a14"))
	tut_label.position = Vector2(22, 14)
	tut_label.size = Vector2(616, 100)
	tut_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tut_panel.add_child(tut_label)
	tut_btn = _make_button("继续", "green", Rect2(500, 108, 140, 50))
	tut_btn.add_theme_font_size_override("font_size", 24)
	tut_btn.pressed.connect(func ():
		tut_continue.emit())
	tut_panel.add_child(tut_btn)

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

## 带深色底边的"糖果立体"面板
func _candy_panel(rect: Rect2, color: Color, radius: int, edge_color: Color, edge_w: int) -> Panel:
	var p := _rounded_panel(rect, color, radius)
	var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
	sb.border_width_bottom = edge_w
	sb.border_color = edge_color
	sb.shadow_color = Color(0.3, 0.18, 0.05, 0.18)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 3)
	return p

## 同色描边模拟粗体
func _bold(l: Label, color: Color, outline: int) -> void:
	l.add_theme_color_override("font_outline_color", color)
	l.add_theme_constant_override("outline_size", outline)

func _texture_rect(path: String, rect: Rect2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.position = rect.position
	t.size = rect.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	if ui_font != null:
		l.add_theme_font_override("font", ui_font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## 糖果质感按钮: 9-slice 贴图 (btn_<name>.png / btn_<name>_p.png)
func _make_button(text: String, color_name: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	if ui_font != null:
		b.add_theme_font_override("font", ui_font)
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	# 中文字形不加描边, 避免发糊; 仅留轻微深色投影增强可读性
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.25))
	b.add_theme_constant_override("shadow_offset_y", 2)
	var sb := _btn_stylebox("res://assets/ui/btn_%s.png" % color_name)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("focus", sb)
	var sbp := _btn_stylebox("res://assets/ui/btn_%s_p.png" % color_name)
	sbp.content_margin_top = 10
	b.add_theme_stylebox_override("pressed", sbp)
	return b

## 九宫格拉伸贴图(木框/木牌/牌架等保持边角不变形)
func _nine(path: String, rect: Rect2, ml: int, mt: int, mr: int, mb: int) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = load(path)
	n.position = rect.position
	n.size = rect.size
	n.patch_margin_left = ml
	n.patch_margin_top = mt
	n.patch_margin_right = mr
	n.patch_margin_bottom = mb
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return n

## 图标按钮(设置齿轮等)
func _icon_button(path: String, rect: Rect2, on_press: Callable) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = load(path)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = rect.position
	b.size = rect.size
	b.pressed.connect(on_press)
	return b

## 整图烘字按钮(fitted/btn_*.png, 文字已烘进底板 → 4 按钮完全一致、永不错位)
func _image_button(tex_name: String, rect: Rect2, on_press: Callable) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = load(FIT + tex_name + ".png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = rect.position
	b.size = rect.size
	b.pressed.connect(on_press)
	return b

## assets_v2 动作按钮: 彩色底板(无字) + 居中中文 + 按下下沉
func _action_button(text: String, base_name: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	if ui_font != null:
		b.add_theme_font_override("font", ui_font)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	b.add_theme_constant_override("shadow_offset_y", 2)
	var tex: Texture2D = load(FIT + "%s.png" % base_name)
	var sb := _av2_btn_sb(tex)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("focus", sb)
	var sbp := _av2_btn_sb(tex)
	sbp.content_margin_top = 8
	b.add_theme_stylebox_override("pressed", sbp)
	return b

## assets_v2 按钮底板九宫格(边距适配矮按钮)
func _av2_btn_sb(tex: Texture2D) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 24
	sb.texture_margin_right = 24
	sb.texture_margin_top = 24
	sb.texture_margin_bottom = 24
	return sb

## 按钮右上角的红色计数角标
func _badge_on(btn: BaseButton, text: String) -> Label:
	var badge := _rounded_panel(Rect2(btn.size.x - 34, -8, 34, 34), Color("#e74c3c"), 17)
	var l := _make_label(text, 22, Color.WHITE)
	l.position = Vector2(0, 2)
	l.size = Vector2(34, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(l)
	btn.add_child(badge)
	return l

## 血条: 深色底 + 彩色填充 + 居中文字
func _make_hp_bar(rect: Rect2, color: Color) -> Dictionary:
	var root := _rounded_panel(rect, Color(0, 0, 0, 0.45), 12)
	var w := rect.size.x - 8.0
	var fill := _rounded_panel(Rect2(4, 4, w, rect.size.y - 8.0), color, 9)
	root.add_child(fill)
	var label := _make_label("", 20, Color.WHITE)
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("outline_size", 3)
	root.add_child(label)
	return {"root": root, "fill": fill, "label": label, "w": w}

func _update_bar(bar: Dictionary, name: String, cur: int, maxv: int) -> void:
	var target_w: float = bar.w * clampf(float(cur) / float(max(1, maxv)), 0.0, 1.0)
	var tw := create_tween()
	tw.tween_property(bar.fill, "size:x", maxf(target_w, 0.01), 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bar.label.text = "%s %d/%d" % [name, cur, maxv]

func _shake(node: Control) -> void:
	var orig: Vector2 = node.position
	var tw := create_tween()
	for off in [6.0, -5.0, 4.0, -3.0]:
		tw.tween_property(node, "position:x", orig.x + off, 0.05)
	tw.tween_property(node, "position:x", orig.x, 0.05)

## 结算公式大字弹出
func _show_score_pop(text: String) -> void:
	var l := _make_label(text, 46, Color("#ffd94d"))
	l.size = Vector2(720, 80)
	l.position = Vector2(0, 460)
	l.pivot_offset = Vector2(360, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color("#7a4d10"))
	l.add_theme_constant_override("outline_size", 8)
	l.scale = Vector2(0.5, 0.5)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2(1.15, 1.15), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.1)
	tw.tween_interval(0.8)
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", 420.0, 0.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.set_parallel(false)
	tw.tween_callback(l.queue_free)

func _set_all_draggable(b: bool) -> void:
	for child in tiles_layer.get_children():
		if child is TileNode:
			(child as TileNode).draggable = b

## 玩法帮助面板
func _show_help() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := _rounded_panel(Rect2(40, 160, 640, 960), Color("#fdf6e8"), 24)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var title := _make_label("玩法说明", 40, Color("#6b4a23"))
	title.size = Vector2(640, 56)
	title.position = Vector2(0, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	var body := _make_label("", 22, Color("#5b3a14"))
	body.text = """目标: 对战模式把敌方体力打到0; 挑战模式达到目标分。
合法牌组:
· 顺子 = 同色连续数字, 至少3张 (如 红3-红4-红5)
· 刻子 = 同数字不同颜色3张
· 对子 = 同数字任意2张 (不计分的伏笔, 每回合限1个)
· Joker(★) 可顶任何一张牌

桌面重组: 桌上所有牌都是公共资源, 可以任意拆开重排,
只要按「出牌」时整个桌面全部合法即可。

伤害(得分) = chips × 倍率
· chips = 本回合新打出牌的面值合计 (对子不计)
· 倍率 = 1 + 0.5 × 被你重组的旧牌数
  (把旧牌拆组/挪去新组合才算, 只在旧组后面接牌不算)
· 重组敌方铺的牌、遗物会有额外加成

换牌: 选中手牌洗回牌库, 换等量新牌 (每层2次)
手牌打空: 立得额外奖励并补5张
过层得金币, 商店购买遗物强化你的构筑。"""
	body.position = Vector2(40, 100)
	body.size = Vector2(560, 780)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(body)
	var close := _make_button("关闭", "green", Rect2(220, 856, 200, 76))
	close.pressed.connect(func ():
		dim.queue_free()
		panel.queue_free())
	panel.add_child(close)

## 对战记录: 逐回合伤害计算明细
func _show_battle_log() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := _rounded_panel(Rect2(40, 170, 640, 840), Color("#fdf6e8"), 24)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var title := _make_label("对战记录", 38, Color("#6b4a23"))
	title.size = Vector2(640, 52)
	title.position = Vector2(0, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	# 伤害公式说明
	var formula := _make_label("伤害 = 基础 × 倍率\n· 基础 = 本回合新打出牌的面值合计\n· 倍率 = 1 + 0.5 × 被重组的旧牌数", 20, Color("#7a5a2e"))
	formula.position = Vector2(36, 84)
	formula.size = Vector2(568, 96)
	formula.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(formula)
	var sep := _rounded_panel(Rect2(36, 188, 568, 2), Color(0.6, 0.45, 0.25, 0.5), 1)
	panel.add_child(sep)
	# 逐回合记录(最新在上)
	var lines := battle_log.duplicate()
	lines.reverse()
	var body_text: String = "本层暂无对战记录" if lines.is_empty() else "\n".join(lines)
	var body := _make_label(body_text, 21, Color("#4a3418"))
	body.position = Vector2(36, 204)
	body.size = Vector2(568, 580)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(body)
	var close := _make_button("关闭", "green", Rect2(220, 800, 200, 70))
	close.pressed.connect(func ():
		dim.queue_free()
		panel.queue_free())
	panel.add_child(close)

# ---------- 桌面自动整理 ----------
## 结算后重排桌面: 组间留空, 顺子可延伸端留呼吸位, 对子留补位
func _auto_layout_table(checked: Array) -> void:
	if checked.is_empty():
		return
	for buffered in [true, false]:
		var plan := _layout_plan(checked, buffered)
		if not plan.is_empty():
			for p in plan:
				var t: TileNode = p.tile
				table_grid[t.row][t.col] = null
			for p in plan:
				var t: TileNode = p.tile
				table_grid[p.r][p.c] = t
				t.row = p.r
				t.col = p.c
				_animate_to_slot(t, "table", p.r, p.c)
			return

func _layout_plan(checked: Array, buffered: bool) -> Array:
	var row := 0
	var col := 0
	var out: Array = []
	for entry in checked:
		var n: int = entry.tiles.size()
		var pre := 0
		var post := 0
		if buffered:
			var k: String = entry.res.kind
			if k == "run":
				var vals: Array = entry.res.values
				var first := int(vals[0])
				var last := int(vals[vals.size() - 1])
				var asc := last > first
				pre = 1 if ((asc and first > Rules.MIN_NUM) or (not asc and first < Rules.MAX_NUM)) else 0
				post = 1 if ((asc and last < Rules.MAX_NUM) or (not asc and last > Rules.MIN_NUM)) else 0
			elif k == "pair":
				post = 1
		var need := pre + n + post
		if col > 0:
			col += 1 # 组间至少1空
		if col + need > TABLE_COLS:
			row += 1
			col = 0
			if row >= TABLE_ROWS or need > TABLE_COLS:
				return []
		var c0 := col + pre
		for i in n:
			out.append({"tile": entry.tiles[i], "r": row, "c": c0 + i})
		col += need
	return out

func _btn_stylebox(path: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(path)
	sb.texture_margin_left = 34
	sb.texture_margin_right = 34
	sb.texture_margin_top = 34
	sb.texture_margin_bottom = 34
	return sb

# ============================================================
# 对局流程
# ============================================================
## 开始(或重开)一层: 牌库重置/桌面清空/手牌重发, 遗物跨层保留
func _start_floor() -> void:
	for n in overlay_nodes:
		n.queue_free()
	overlay_nodes = []
	for child in tiles_layer.get_children():
		child.queue_free()
	game_over = false
	exchange_mode = false
	busy = false
	btn_exchange.texture_normal = load(FIT + "btn_hint.png")
	# 按模式切换顶部HUD形态(教程沿用对战HUD)
	# 木牌(层/回合)、牌库角标、底部玩家簇 + Combo 两种模式都常驻
	var is_battle := mode != "score"
	badge_r.visible = not is_battle      # 目标角标仅分数模式
	pbar.root.visible = is_battle        # 我方血条仅对战
	ebox.visible = is_battle             # 敌人展示区(含对手手牌数)仅对战
	btn_log.visible = is_battle          # 对战记录按钮仅对战
	enemy_action.text = "等待出牌…"
	# 牌库角标: 分数模式居左上; 对战模式左上让位给敌人区, 移到右上
	badge_l.position = Vector2(492, 14) if is_battle else Vector2(14, 14)
	battle_log.clear()                   # 清空上一层的对战记录
	arena_scored.clear()                 # 清空场面争夺的"已领链"记录
	score = 0
	turn = 1
	exchanges_left = EXCHANGES_PER_FLOOR
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
	if mode == "tutorial":
		# 固定手牌: 红345 / 蓝3,7 / 橙2,2,3; 牌库只有定向摸牌: 蓝5 → 鬼牌
		deck = [
			{"color": -1, "num": 0, "joker": true},
			{"color": 1, "num": 5, "joker": false},
		]
		var fixed_hand := [
			{"color": 0, "num": 3, "joker": false}, {"color": 0, "num": 4, "joker": false},
			{"color": 0, "num": 5, "joker": false}, {"color": 1, "num": 3, "joker": false},
			{"color": 1, "num": 7, "joker": false}, {"color": 2, "num": 2, "joker": false},
			{"color": 2, "num": 2, "joker": false}, {"color": 2, "num": 3, "joker": false},
		]
		var slot_i := 0
		for d in fixed_hand:
			@warning_ignore("integer_division")
			var rr := slot_i / RACK_COLS
			var cc := slot_i % RACK_COLS
			var tile := _create_tile(d, "rack", rr, cc)
			rack_grid[rr][cc] = tile
			slot_i += 1
		player_hp = PLAYER_MAX_HP
		enemy_hp = 75
		enemy_hand = []
		tut_step = 0
		_tut_intro() # 异步旁白流程
	else:
		for _i in HAND_START:
			_draw_to_rack()
		if mode == "battle":
			player_hp = PLAYER_MAX_HP
			enemy_hp = _battle_max()
			enemy_hand = []
			for _i in HAND_START:
				if deck.size() > 0:
					enemy_hand.append(deck.pop_back())
	_take_snapshot()
	_update_hud()
	_flash_turn_frame()

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

func _create_tile(def: Dictionary, zone: String, row: int, col: int, uid: int = -1) -> TileNode:
	var tile := TileNode.new()
	tile.setup(def, TILE_SIZE)
	if uid >= 0:
		tile.uid = uid
	else:
		tile.uid = next_uid
		next_uid += 1
	tile.zone = zone
	tile.home_zone = zone
	tile.row = row
	tile.col = col
	tile.position = _slot_pos(zone, row, col)
	tile.pick_started.connect(_on_tile_picked)
	tile.drop_attempt.connect(_on_tile_dropped)
	tile.clicked.connect(_on_tile_clicked)
	tiles_layer.add_child(tile)
	return tile

func _slot_pos(zone: String, r: int, c: int) -> Vector2:
	var origin := TABLE_ORIGIN if zone == "table" else RACK_ORIGIN
	return origin + Vector2(c * SX, r * SY)

func _grid_of(zone: String) -> Array:
	return table_grid if zone == "table" else rack_grid

## 牌面值指纹(重组判定用): 同色同数的两份拷贝视为同一张
func _val_key(d: Dictionary) -> int:
	return 900 if d.joker else int(d.color) * 100 + int(d.num)

# ---------- 拖拽 ----------
func _on_tile_picked(tile: TileNode) -> void:
	tiles_layer.move_child(tile, tiles_layer.get_child_count() - 1)

func _on_tile_dropped(tile: TileNode, global_pos: Vector2) -> void:
	var center: Vector2 = global_pos + TILE_SIZE / 2.0
	var zones: Array = ["table"] if tile.home_zone == "table" else ["table", "rack"]
	# 找最近的目标格(空或占用都行), 用更大的吸附半径 → 更"磁性"
	var snap := DROP_RADIUS + 26.0
	var tz := ""
	var tr := -1
	var tc := -1
	var td := snap
	for z in zones:
		var rows: int = TABLE_ROWS if z == "table" else RACK_ROWS
		var cols: int = TABLE_COLS if z == "table" else RACK_COLS
		for r in rows:
			for c in cols:
				var sc: Vector2 = _slot_pos(z, r, c) + TILE_SIZE / 2.0
				var d := center.distance_to(sc)
				if d < td:
					td = d
					tz = z
					tr = r
					tc = c
	if tz == "":
		_animate_to_slot(tile, tile.zone, tile.row, tile.col) # 弹回原位
		return
	var grid := _grid_of(tz)
	var occ = grid[tr][tc]
	_grid_of(tile.zone)[tile.row][tile.col] = null # 先清原位
	if occ != null and occ != tile:
		# 目标被占 → 行内自动腾位(吸附+重排); 腾不出则退到最近空位
		if not _row_make_room(tz, tr, tc):
			var fb := _nearest_empty_slot(tile, center, snap)
			if fb.is_empty():
				_grid_of(tile.zone)[tile.row][tile.col] = tile # 还原
				_animate_to_slot(tile, tile.zone, tile.row, tile.col)
				return
			tz = fb.z
			tr = fb.r
			tc = fb.c
			grid = _grid_of(tz)
	grid[tr][tc] = tile
	tile.zone = tz
	tile.row = tr
	tile.col = tc
	tile.set_new_highlight(tz == "table" and tile.home_zone == "rack")
	_animate_to_slot(tile, tz, tr, tc)
	_refresh_arena_meter() # 场面争夺: 拖拽后实时刷新场面倍率

## 行内腾位: 把目标格 (r,c) 旁边的牌朝最近空位推一格, 空出该格 (自动重排)
func _row_make_room(zone: String, r: int, c: int) -> bool:
	var grid := _grid_of(zone)
	var cols: int = TABLE_COLS if zone == "table" else RACK_COLS
	var er := -1
	for cc in range(c + 1, cols):
		if grid[r][cc] == null:
			er = cc
			break
	var el := -1
	for cc in range(c - 1, -1, -1):
		if grid[r][cc] == null:
			el = cc
			break
	if er < 0 and el < 0:
		return false
	var use_right: bool = er >= 0 and (el < 0 or (er - c) <= (c - el))
	if use_right:
		for cc in range(er, c, -1):
			var t: TileNode = grid[r][cc - 1]
			grid[r][cc] = t
			if t != null:
				t.col = cc
				_animate_to_slot(t, zone, r, cc)
	else:
		for cc in range(el, c):
			var t: TileNode = grid[r][cc + 1]
			grid[r][cc] = t
			if t != null:
				t.col = cc
				_animate_to_slot(t, zone, r, cc)
	grid[r][c] = null
	return true

## 最近空位(腾位失败时的退路)
func _nearest_empty_slot(tile: TileNode, center: Vector2, radius: float) -> Dictionary:
	var zones: Array = ["table"] if tile.home_zone == "table" else ["table", "rack"]
	var best := {}
	var bd := radius
	for z in zones:
		var rows: int = TABLE_ROWS if z == "table" else RACK_ROWS
		var cols: int = TABLE_COLS if z == "table" else RACK_COLS
		for r in rows:
			for c in cols:
				if _grid_of(z)[r][c] != null:
					continue
				var sc: Vector2 = _slot_pos(z, r, c) + TILE_SIZE / 2.0
				var d := center.distance_to(sc)
				if d < bd:
					bd = d
					best = {"z": z, "r": r, "c": c}
	return best

func _animate_to_slot(tile: TileNode, zone: String, r: int, c: int) -> void:
	var tw := create_tween()
	tw.tween_property(tile, "position", _slot_pos(zone, r, c), 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ============================================================
# 场面争夺 (arena) — 复用对战框架, 仅替换我方算分
# ============================================================
## 牌型分: 对子1 / 刻子2 / 三连2 / 四连4 / 五连5 / 六连6 / 七连7
func _shape_score(kind: String, n: int) -> int:
	if kind == "run":
		if n <= 3: return 2
		elif n == 4: return 4
		elif n == 5: return 5
		elif n == 6: return 6
		return 7
	elif kind == "group":
		return 2
	elif kind == "pair":
		return 1
	return 0

## 链的"组成签名"(面值多重集): 判断这条链是否被改动过
func _chain_sig(tiles: Array) -> Array:
	var sig: Array = []
	for t in tiles:
		sig.append(_val_key(t.def))
	sig.sort()
	return sig

## 链是否"新鲜"(倍率可领): 只要不是"原样保留的已领链"就算新鲜。
## 已领 = 链内每张牌上次领取时的签名都 == 当前签名(没被改组过)。
## 牌重排成别的链 → 签名变化 → 重新新鲜 → 倍率再次生效。
func _chain_fresh(tiles: Array, sig: Array) -> bool:
	for t in tiles:
		if not arena_scored.has(t.uid) or arena_scored[t.uid] != sig:
			return true
	return false

## 结算: 基础(本回合出牌面值和) × 倍率(各"新鲜链"牌型分和)。"消耗"= 把刚领的链标记为已领(牌不动)。
func _arena_settle(checked: Array, _k: int) -> int:
	var base := 0  # 本回合从手里打出的牌面值之和
	var s := 0     # 新鲜链(本回合改变了组成的链)牌型分之和 = 倍率
	var harvested: Array = [] # [tiles, sig]
	for entry in checked:
		for i in entry.tiles.size():
			if entry.tiles[i].is_new:
				base += int(entry.res.values[i])
		var sig := _chain_sig(entry.tiles)
		if _chain_fresh(entry.tiles, sig):
			s += _shape_score(entry.res.kind, entry.tiles.size())
			harvested.append([entry.tiles, sig])
	var gained: int = base * s
	score += gained
	battle_log.append("第%d回合 · 我方  基础 %d × 倍率 %d = %d 伤害" % [turn, base, s, gained])
	_show_score_pop("%d × %d = %d!" % [base, s, gained])
	# 消耗: 这些链倍率已领 → 记录其当前组成; 牌留在桌面, 重排成别的链后会重新新鲜
	for h in harvested:
		for t in h[0]:
			arena_scored[t.uid] = h[1]
	return gained

## 场面倍率显示(随拖拽实时刷新) + 已领链暗淡提示
func _refresh_arena_meter() -> void:
	if lbl_arena == null:
		return
	lbl_arena.visible = arena_mode
	if not arena_mode:
		return
	# 先全部复原, 再把"已领链"(倍率已消耗)调暗, 提示需要重排才能再生效
	for row in table_grid:
		for t in row:
			if t != null:
				t.modulate = Color.WHITE
	var s := 0
	for g in _parse_table_groups():
		var defs: Array = []
		for t in g:
			defs.append(t.def)
		var res := Rules.check_set(defs)
		if not res.valid:
			continue
		var sig := _chain_sig(g)
		if _chain_fresh(g, sig):
			s += _shape_score(res.kind, g.size())
		else:
			for t in g:
				t.modulate = Color(0.66, 0.66, 0.72) # 已领: 倍率为0, 需重排
	lbl_arena.text = "场面倍率 ×%d" % s

# ---------- 回合结算 ----------
func _on_end_turn() -> void:
	if game_over or exchange_mode or busy:
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

	# 每回合最多打出1个新对子(排水口, 不可无脑倒手牌)
	var new_pairs := 0
	for entry in checked:
		if entry.res.kind == "pair":
			for t in entry.tiles:
				if t.is_new:
					new_pairs += 1
					break
	if new_pairs > relic_mgr.pair_limit():
		_toast("每回合最多只能打出%d个对子" % relic_mgr.pair_limit())
		return

	# 教程: 校验是否按引导出牌
	if mode == "tutorial" and not _tut_check_submit(checked):
		return

	busy = true
	_set_all_draggable(false)

	var new_count := 0
	for row in table_grid:
		for t in row:
			if t != null and t.is_new:
				new_count += 1

	var turn_gain := 0
	if new_count == 0:
		_toast("本回合未出牌, 摸1张")
	elif arena_mode:
		# 场面争夺: 出牌张数 × (1+场面牌型分), 结算即消耗
		turn_gain = _arena_settle(checked, new_count)
	else:
		# chips: 各牌组新牌面值经遗物修正后求和 (+回收商存入的返还)
		var chips := next_chips_bonus
		next_chips_bonus = 0
		for entry in checked:
			var flags: Array = []
			var defs2: Array = []
			for t in entry.tiles:
				flags.append(t.is_new)
				defs2.append(t.def)
			chips += relic_mgr.chips_for_set(entry.res.kind, entry.res.values, flags, defs2)
		# R = 被实质重组的旧牌数(原组被拆/牌被挪; 仅被新牌扩充不算)
		# 按"面值多重集"对比: 同名牌互换不计, 防刷分
		var reorg := 0
		var enemy_reorg := 0
		var reorg_tiles: Array = []
		for entry in checked:
			var vals: Array = []
			var new_val_counts := {}
			for t in entry.tiles:
				var vk := _val_key(t.def)
				vals.append(vk)
				if t.is_new:
					new_val_counts[vk] = int(new_val_counts.get(vk, 0)) + 1
			vals.sort()
			var cur_counts := {}
			for v in vals:
				cur_counts[v] = int(cur_counts.get(v, 0)) + 1
			for t in entry.tiles:
				if t.is_new or not start_groups.has(t.uid):
					continue
				var before: Array = start_groups[t.uid]
				if vals == before:
					continue
				# 扩充豁免: 原组面值全保留, 且新增面值都来自本回合新牌
				var before_counts := {}
				for v in before:
					before_counts[v] = int(before_counts.get(v, 0)) + 1
				var expanded := true
				for v in before_counts:
					if int(cur_counts.get(v, 0)) < int(before_counts[v]):
						expanded = false
						break
				if expanded:
					for v in cur_counts:
						var extra: int = int(cur_counts[v]) - int(before_counts.get(v, 0))
						if extra > int(new_val_counts.get(v, 0)):
							expanded = false
							break
				if not expanded:
					reorg += 1
					reorg_tiles.append(t)
					if t.owner_tag == "enemy":
						enemy_reorg += 1
		var mult := 1.0 + relic_mgr.mult_step() * reorg + relic_mgr.enemy_reorg_bonus(enemy_reorg)
		var gained := int(round(chips * mult))
		score += gained
		turn_gain = gained
		# 记入对战记录(伤害计算)
		if reorg > 0:
			battle_log.append("第%d回合 · 我方  基础 %d × 倍率 %.1f (重组 %d 张) = %d 伤害" % [turn, chips, mult, reorg, gained])
		else:
			battle_log.append("第%d回合 · 我方  打出 %d 点 (无重组, 倍率 1.0)" % [turn, gained])
		# 结算可视化: 重组连击逐张点亮(×1×2×3…) → 倍率横幅 → 公式大字 + 新牌脉冲
		await _play_reorg_combo(reorg_tiles, mult)
		if reorg > 0:
			_show_score_pop("%d × %.1f = %d!" % [chips, mult, gained])
		else:
			_show_score_pop("+%d" % gained)
		for entry in checked:
			for t in entry.tiles:
				if t.is_new:
					t.flash_hint()

	# 锁定桌面牌
	for row in table_grid:
		for t in row:
			if t != null:
				t.home_zone = "table"
				t.set_new_highlight(false)

	# 自动整理桌面: 组间留空, 顺子留头尾呼吸位, 对子留补位 (场面争夺牌也留在桌面)
	_auto_layout_table(checked)

	# 空手奖励 (对战/教程计入伤害, 分数模式计入得分)
	if _rack_count() == 0:
		if mode != "score":
			turn_gain += EMPTY_HAND_BONUS
			_toast("手牌打空! 额外 %d 伤害, 补5张" % EMPTY_HAND_BONUS)
		else:
			score += EMPTY_HAND_BONUS
			_toast("手牌打空! 奖励 +%d, 补5张" % EMPTY_HAND_BONUS)
		for _i in 5:
			_draw_to_rack()

	if mode != "score":
		enemy_hp -= turn_gain
		if turn_gain > 0:
			var heal := relic_mgr.lifesteal(turn_gain)
			if heal > 0:
				player_hp = min(PLAYER_MAX_HP, player_hp + heal)
			_shake(ebox)
		_update_hud()
		if enemy_hp <= 0:
			enemy_hp = 0
			busy = false
			_show_floor_result(true)
			return
		var draws_b := relic_mgr.draw_count(1)
		for _i in draws_b:
			_draw_to_rack()
		var alive := true
		if mode == "tutorial":
			alive = await _tut_after_submit()
		else:
			await get_tree().create_timer(0.45).timeout
			alive = await _ai_turn()
		if not alive:
			busy = false
			return
		turn += 1
		_take_snapshot()
		_update_hud()
		busy = false
		_set_all_draggable(true)
		_flash_turn_frame()
		return

	if score >= _floor_target():
		busy = false
		_update_hud()
		_show_floor_result(true)
		return

	var draws := relic_mgr.draw_count(1)
	for _i in draws:
		_draw_to_rack()

	if turn >= MAX_TURNS:
		busy = false
		_update_hud()
		_show_floor_result(false)
		return

	turn += 1
	_take_snapshot()
	_update_hud()
	busy = false
	_set_all_draggable(true)
	_flash_turn_frame()

# ---------- 对战: AI回合 (逐张飞牌动画) ----------
## 返回false表示我方被击败(对局已结束)
func _ai_turn() -> bool:
	enemy_action.text = "对手思考中…"
	var groups := _parse_table_groups()
	var ginfo: Array = []
	for g in groups:
		var defs: Array = []
		for t in g:
			defs.append(t.def)
		var res := Rules.check_set(defs)
		ginfo.append({"kind": res.kind, "values": res.values, "defs": defs, "tiles": g})
	var cfg := _ai_cfg()
	var plan := AiOpponent.plan(enemy_hand, ginfo, cfg)
	var dmg := 0
	var played := 0
	var r_ai := 0
	var pulled_gis := {}
	# 拆组突袭: 从桌面组拉牌 + 手牌2张组新顺/刻 (AI同样吃 chips×倍率)
	for p in plan.pulls:
		var spot_p := _find_table_space(3)
		if spot_p.is_empty():
			break
		var g_src: Dictionary = ginfo[p.gi]
		var src_tiles: Array = g_src.tiles
		var pulled: TileNode = null
		for t in src_tiles:
			if t.def == p.take_def:
				pulled = t
				break
		if pulled == null:
			continue
		pulled_gis[p.gi] = true
		r_ai += src_tiles.size()
		for t in src_tiles:
			t.flash_color(Color("#ff7a6b"))
		# 抽走 + 行内压缩补位
		table_grid[pulled.row][pulled.col] = null
		for t in src_tiles:
			if t != pulled and t.col > pulled.col:
				table_grid[t.row][t.col] = null
				t.col -= 1
				table_grid[t.row][t.col] = t
				_animate_to_slot(t, "table", t.row, t.col)
		# 新组: 按数字排序放置
		var members: Array = [p.take_def, p.new_defs[0], p.new_defs[1]]
		members.sort_custom(func (x, y): return x.num < y.num)
		for i in members.size():
			var d2: Dictionary = members[i]
			if d2 == p.take_def:
				pulled.row = spot_p.r
				pulled.col = spot_p.c + i
				table_grid[pulled.row][pulled.col] = pulled
				_animate_to_slot(pulled, "table", pulled.row, pulled.col)
			else:
				await _place_ai_tile(d2, spot_p.r, spot_p.c + i)
				dmg += int(d2.num)
		played += 2
		_remove_from_enemy_hand(p.new_defs)
	for s in plan.sets:
		var spot := _find_table_space(s.size())
		if spot.is_empty():
			break
		for i in s.size():
			await _place_ai_tile(s[i], spot.r, spot.c + i)
		for d in s:
			dmg += int(d.num)
		played += s.size()
		_remove_from_enemy_hand(s)
	for e in plan.exts:
		if pulled_gis.has(e.gi):
			continue # 该组已被拆, 端值失效
		var g2: Dictionary = ginfo[e.gi]
		var tiles: Array = g2.tiles
		var r: int = tiles[0].row
		var c0: int = tiles[0].col
		var c1: int = tiles[tiles.size() - 1].col
		var target_c: int = c0 - 1 if e.side == "left" else c1 + 1
		var guard_c: int = target_c - 1 if e.side == "left" else target_c + 1
		if target_c < 0 or target_c >= TABLE_COLS:
			continue
		if table_grid[r][target_c] != null:
			continue
		if guard_c >= 0 and guard_c < TABLE_COLS and table_grid[r][guard_c] != null:
			continue
		await _place_ai_tile(e.def, r, target_c)
		dmg += int(e.def.num)
		played += 1
		_remove_from_enemy_hand([e.def])
	for p in plan.pairs:
		var spot2 := _find_table_space(2)
		if spot2.is_empty():
			break
		await _place_ai_tile(p[0], spot2.r, spot2.c)
		await _place_ai_tile(p[1], spot2.r, spot2.c + 1)
		played += 2
		_remove_from_enemy_hand(p)
	# AI落子后同样自动整理桌面
	if played > 0:
		var groups2 := _parse_table_groups()
		var checked2: Array = []
		for g3 in groups2:
			var defs3: Array = []
			for t in g3:
				defs3.append(t.def)
			var res3 := Rules.check_set(defs3)
			if res3.valid:
				checked2.append({"tiles": g3, "res": res3})
		_auto_layout_table(checked2)
	for _di in int(cfg.draws):
		if deck.size() > 0:
			if relic_mgr.enemy_draw_blocked():
				_toast("烟雾弹生效, 敌方摸牌落空!")
			else:
				enemy_hand.append(deck.pop_back())
	# 伤害 = chips × (1 + 0.5×AI重组数), 与玩家同一公式
	var mult_ai := 1.0 + 0.5 * r_ai
	var dmg_total := int(round(dmg * mult_ai))
	dmg_total = relic_mgr.modify_enemy_damage(dmg_total)
	if dmg_total > 0:
		player_hp -= dmg_total
		if r_ai > 0:
			enemy_action.text = "重组突袭! %d×%.1f=%d伤害!" % [dmg, mult_ai, dmg_total]
			_show_score_pop("敌方 %d × %.1f = %d!" % [dmg, mult_ai, dmg_total])
			battle_log.append("第%d回合 · 对手  基础 %d × 倍率 %.1f (重组 %d 张) = %d 伤害" % [turn, dmg, mult_ai, r_ai, dmg_total])
		else:
			enemy_action.text = "出牌%d张, 造成%d伤害!" % [played, dmg_total]
			battle_log.append("第%d回合 · 对手  出牌 %d 张, 造成 %d 伤害" % [turn, played, dmg_total])
		_shake(pbar.root)
	elif played > 0:
		enemy_action.text = "打出对子, 蓄势中"
	else:
		enemy_action.text = "无牌可出, 摸牌休整"
	# 意图预告(按其手牌预演下回合)
	var groups3 := _parse_table_groups()
	var ginfo3: Array = []
	for g4 in groups3:
		var defs4: Array = []
		for t in g4:
			defs4.append(t.def)
		var res4 := Rules.check_set(defs4)
		if res4.valid:
			ginfo3.append({"kind": res4.kind, "values": res4.values, "defs": defs4, "tiles": g4})
	enemy_action.text += "\n" + AiOpponent.intent_text(enemy_hand, ginfo3, cfg)
	_update_hud()
	if player_hp <= 0:
		player_hp = 0
		_update_hud()
		_show_floor_result(false)
		return false
	return true

## 在桌面找能放下n张连排的空位(两侧需留空/到边), 找不到返回空字典
func _find_table_space(n: int) -> Dictionary:
	for r in TABLE_ROWS:
		for c in range(0, TABLE_COLS - n + 1):
			var ok := true
			if c > 0 and table_grid[r][c - 1] != null:
				ok = false
			if ok:
				for i in n:
					if table_grid[r][c + i] != null:
						ok = false
						break
			if ok and c + n < TABLE_COLS and table_grid[r][c + n] != null:
				ok = false
			if ok:
				return {"r": r, "c": c}
	return {}

## 敌方落子: 从敌人展示区飞向目标格
func _place_ai_tile(def: Dictionary, r: int, c: int) -> void:
	var tile := _create_tile(def, "table", r, c)
	tile.owner_tag = "enemy"
	table_grid[r][c] = tile
	tile.position = ebox.position + Vector2(20, 70)
	tile.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(tile, "position", _slot_pos("table", r, c), 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(tile, "scale", Vector2.ONE, 0.3)
	await get_tree().create_timer(0.18).timeout

func _remove_from_enemy_hand(defs: Array) -> void:
	for d in defs:
		enemy_hand.erase(d)

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

# ---------- 换牌 ----------
## 进入选择模式 -> 点选手牌 -> 再按确认: 选中牌洗回牌库, 抽回等量
func _on_exchange() -> void:
	if game_over or busy:
		return
	if mode == "tutorial":
		_toast("教程中暂不可用")
		return
	if not exchange_mode:
		if exchanges_left <= 0:
			_toast("本层换牌次数已用完")
			return
		exchange_mode = true
		btn_exchange.texture_normal = load(FIT + "btn_confirm.png")
		for row in rack_grid:
			for t in row:
				if t != null:
					t.select_mode = true
		for row in table_grid:
			for t in row:
				if t != null:
					t.draggable = false
		_toast("点选要换掉的手牌, 再按「确认」(再按一次空选可取消)")
		return
	# 确认阶段
	var picked: Array = []
	for row in rack_grid:
		for t in row:
			if t != null and t.selected:
				picked.append(t)
	if picked.is_empty():
		_exit_exchange_mode()
		_toast("已取消换牌")
		return
	var picked_defs: Array = []
	for t in picked:
		picked_defs.append(t.def)
		deck.append(t.def)
		rack_grid[t.row][t.col] = null
		t.queue_free()
	deck.shuffle()
	var refund := relic_mgr.exchange_refund(picked_defs)
	if refund > 0:
		next_chips_bonus += refund
		_toast("回收商: 下回合chips+%d" % refund)
	var n: int = picked.size()
	for _i in n:
		_draw_to_rack()
	exchanges_left -= 1
	_exit_exchange_mode()
	_take_snapshot() # 牌库已变, 撤回基准同步刷新
	_update_hud()
	_toast("换掉 %d 张" % n)

func _exit_exchange_mode() -> void:
	exchange_mode = false
	btn_exchange.texture_normal = load(FIT + "btn_hint.png")
	for row in rack_grid:
		for t in row:
			if t != null:
				t.select_mode = false
				t.set_selected(false)
	for row in table_grid:
		for t in row:
			if t != null:
				t.draggable = true

func _on_tile_clicked(tile: TileNode) -> void:
	if exchange_mode and tile.zone == "rack":
		tile.set_selected(not tile.selected)

# ---------- 整理 / 提示 / 撤回 ----------
@warning_ignore("integer_division")
func _on_sort() -> void:
	if game_over or exchange_mode or busy:
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

func _on_undo() -> void:
	if game_over or exchange_mode or busy:
		return
	if mode == "tutorial":
		_toast("教程中暂不可用")
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
					snapshot.append({"def": t.def, "zone": zone, "row": r, "col": c,
						"uid": t.uid, "is_new": t.is_new, "owner": t.owner_tag})
	# 记录回合开始时每张桌面牌所属牌组的"面值多重集"(重组判定基准)
	# 用面值而非实例id对比, 防止"两张相同牌互换牌组"刷重组数的漏洞
	start_groups = {}
	for g in _parse_table_groups():
		var vals: Array = []
		for t in g:
			vals.append(_val_key(t.def))
		vals.sort()
		for t in g:
			start_groups[t.uid] = vals

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
		var tile := _create_tile(rec.def, rec.zone, rec.row, rec.col, rec.uid)
		_grid_of(rec.zone)[rec.row][rec.col] = tile
		tile.owner_tag = rec.get("owner", "player")
		if rec.get("is_new", false):
			tile.home_zone = "rack"
			tile.set_new_highlight(true)

# ---------- HUD / 结算 ----------
func _update_hud() -> void:
	# 木牌(层/回合)、Combo分数、牌库角标、金币 两种模式都刷新
	lbl_score.text = "%d" % score
	lbl_deck.text = "%d" % deck.size()
	lbl_gold.text = "金币 %d" % gold        # 我方金币(我方信息区)
	if mode != "score":
		lbl_turn.text = "第%d层 回合%d" % [floor_num, turn]
		_update_bar(pbar, "我方", player_hp, PLAYER_MAX_HP)
		var ename: String = "对手" if mode == "tutorial" else String(_ai_cfg().name)
		_update_bar(ebar, ename, enemy_hp, _battle_max())
		lbl_turn_b.text = "手牌 %d" % enemy_hand.size()   # 对手手牌数(头像下方)
	else:
		lbl_turn.text = "第%d层 %d/%d" % [floor_num, turn, MAX_TURNS]
		lbl_target.text = "目标 %d" % _floor_target()
	lbl_ex_count.text = str(exchanges_left)
	_refresh_arena_meter() # 场面争夺: 同步场面倍率显示

# ---------- 层间商店 ----------
var _shop_cards_box: Control
var _shop_gold_lbl: Label

func _show_shop() -> void:
	for n in overlay_nodes:
		n.queue_free()
	overlay_nodes = []
	game_over = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	overlay_nodes.append(dim)
	var panel := _rounded_panel(Rect2(40, 140, 640, 1000), Color("#fdf6e8"), 24)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	overlay_nodes.append(panel)
	var title := _make_label("商店", 44, Color("#6b4a23"))
	title.size = Vector2(640, 60)
	title.position = Vector2(0, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	_shop_gold_lbl = _make_label("金币 %d" % gold, 30, Color("#b8860b"))
	_shop_gold_lbl.size = Vector2(640, 40)
	_shop_gold_lbl.position = Vector2(0, 96)
	_shop_gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_shop_gold_lbl)
	_shop_cards_box = Control.new()
	_shop_cards_box.position = Vector2(40, 160)
	_shop_cards_box.size = Vector2(560, 560)
	panel.add_child(_shop_cards_box)
	_shop_build_cards()
	var refresh_btn := _make_button("刷新 %d金" % SHOP_REROLL_COST, "blue", Rect2(60, 770, 230, 84))
	refresh_btn.add_theme_font_size_override("font_size", 28)
	refresh_btn.pressed.connect(func ():
		if gold < SHOP_REROLL_COST:
			_toast("金币不足")
			return
		gold -= SHOP_REROLL_COST
		_shop_gold_lbl.text = "金币 %d" % gold
		_update_hud()
		_shop_build_cards())
	panel.add_child(refresh_btn)
	var next_btn := _make_button("下一层", "green", Rect2(330, 770, 250, 84))
	next_btn.pressed.connect(func ():
		floor_num += 1
		_start_floor())
	panel.add_child(next_btn)

func _shop_build_cards() -> void:
	for c in _shop_cards_box.get_children():
		c.queue_free()
	var offers := relic_mgr.shop_offers(3)
	if offers.is_empty():
		var empty := _make_label("遗物已售罄", 28, Color("#8a6a3f"))
		empty.position = Vector2(180, 240)
		_shop_cards_box.add_child(empty)
		return
	var y := 0.0
	for id in offers:
		var d: Dictionary = RelicManager.DEFS[id]
		var card := _rounded_panel(Rect2(0, y, 560, 160), Color("#f3e7cd"), 16)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		_shop_cards_box.add_child(card)
		var nm := _make_label("%s  [%s]" % [d.name, d.short], 28, Color("#6b4a23"))
		nm.position = Vector2(24, 16)
		card.add_child(nm)
		var ds := _make_label(d.desc, 20, Color("#8a6a3f"))
		ds.position = Vector2(24, 62)
		ds.size = Vector2(380, 86)
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(ds)
		var buy := _make_button("%d金" % d.price, "green", Rect2(424, 38, 112, 84))
		buy.add_theme_font_size_override("font_size", 28)
		var rid: String = id
		buy.pressed.connect(func ():
			var price: int = RelicManager.DEFS[rid].price
			if gold < price:
				_toast("金币不足")
				return
			gold -= price
			relic_mgr.add(rid)
			_refresh_relic_bar()
			_shop_gold_lbl.text = "金币 %d" % gold
			_update_hud()
			buy.disabled = true
			buy.text = "已购")
		card.add_child(buy)
		y += 184.0

# ---------- 结算连击/回合提示动效 ----------
## 重组连击: 逐张点亮被计入R的旧牌, 弹出×1×2×3…, 收尾倍率横幅(×3+变色, ×5+震屏)
func _play_reorg_combo(tiles: Array, mult: float) -> void:
	if tiles.is_empty():
		return
	var i := 0
	for t in tiles:
		i += 1
		t.flash_color(Color("#4db8ff"))
		_spawn_combo_tag(t, i)
		await get_tree().create_timer(0.16).timeout
	await get_tree().create_timer(0.25).timeout
	var n := tiles.size()
	var fsize := 34
	var col := Color("#ffd94d")
	if n >= 5:
		fsize = 48
		col = Color("#ff5a4d")
	elif n >= 3:
		fsize = 42
		col = Color("#ff9c2e")
	var l := _make_label("重组 ×%d   倍率 1 + 0.5×%d = %.1fx" % [n, n, mult], fsize, col)
	l.size = Vector2(720, 70)
	l.position = Vector2(0, 530)
	l.pivot_offset = Vector2(360, 35)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color("#5b2408"))
	l.add_theme_constant_override("outline_size", 8)
	l.scale = Vector2(0.4, 0.4)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2(1.2, 1.2), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.1)
	tw.tween_interval(0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)
	if n >= 3:
		_shake(self)
	await get_tree().create_timer(0.6).timeout

## 单张连击标签 ×N: 从牌位弹出后飞向横幅位置
func _spawn_combo_tag(t: TileNode, n: int) -> void:
	var l := _make_label("×%d" % n, 28 + min(n, 6) * 3, Color("#ff5a4d") if n >= 5 else (Color("#ff9c2e") if n >= 3 else Color("#ffd94d")))
	l.position = t.position + Vector2(14, -26)
	l.add_theme_color_override("font_outline_color", Color("#5b2408"))
	l.add_theme_constant_override("outline_size", 6)
	l.scale = Vector2(0.4, 0.4)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2(1.25, 1.25), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.08)
	tw.tween_interval(0.15)
	tw.set_parallel(true)
	tw.tween_property(l, "position", Vector2(340, 540), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(l, "modulate:a", 0.0, 0.32)
	tw.set_parallel(false)
	tw.tween_callback(l.queue_free)

## 回合开始: 棋盘金框呼吸闪烁
func _flash_turn_frame() -> void:
	if game_over:
		return
	board_frame.visible = true
	board_frame.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(board_frame, "modulate:a", 0.9, 0.18)
	tw.tween_property(board_frame, "modulate:a", 0.15, 0.2)
	tw.tween_property(board_frame, "modulate:a", 0.75, 0.18)
	tw.tween_property(board_frame, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func ():
		board_frame.visible = false)

# ---------- 新手教程 ----------
func _tut_show(text: String, wait := true) -> void:
	tut_panel.visible = true
	tut_label.text = text
	tut_btn.visible = wait
	if wait:
		await tut_continue

func _tut_set_guides(tiles: Array) -> void:
	for t in tut_guides:
		if is_instance_valid(t):
			t.set_guide(false)
	tut_guides = tiles
	for t in tut_guides:
		t.set_guide(true)

func _rack_tiles_matching(color: int, num: int, joker := false) -> Array:
	var out: Array = []
	for row in rack_grid:
		for t in row:
			if t == null:
				continue
			if joker and t.def.joker:
				out.append(t)
			elif not joker and not t.def.joker and t.def.color == color and t.def.num == num:
				out.append(t)
	return out

func _table_tile(color: int, num: int) -> TileNode:
	for row in table_grid:
		for t in row:
			if t != null and not t.def.joker and t.def.color == color and t.def.num == num:
				return t
	return null

## 教程开场旁白(步骤1-3)
func _tut_intro() -> void:
	busy = true
	_set_all_draggable(false)
	await get_tree().create_timer(0.5).timeout
	await _tut_show("欢迎来到新手教程! 本作牌池共43张: 红/蓝/橙 三种颜色 × 数字1-7 × 各2份, 外加1张百变鬼牌★。先来认识你的手牌。")
	var reds: Array = _rack_tiles_matching(0, 3) + _rack_tiles_matching(0, 4) + _rack_tiles_matching(0, 5)
	_tut_set_guides(reds)
	await _tut_show("顺子: 同一颜色、数字相连, 至少3张。看, 你手里的 红3-红4-红5 正是一组顺子!")
	_tut_set_guides(_rack_tiles_matching(0, 3) + _rack_tiles_matching(1, 3) + _rack_tiles_matching(2, 3))
	await _tut_show("刻子: 相同数字 + 三种不同颜色。红3 + 蓝3 + 橙3 正好凑成!")
	_tut_set_guides(_rack_tiles_matching(2, 2))
	await _tut_show("对子: 任意两张同数字, 同色异色都可以, 比如这两张橙2。对子不计分, 但能占场铺路、等第三张补成刻子。")
	_tut_set_guides(_rack_tiles_matching(0, 3) + _rack_tiles_matching(1, 3) + _rack_tiles_matching(2, 3) + _rack_tiles_matching(2, 2))
	_tut_show("实战! 把 红3/蓝3/橙3 拖到桌面排成一排(刻子), 再把两张橙2排成对子, 然后按「出牌」。", false)
	tut_step = 3
	busy = false
	_set_all_draggable(true)

## 教程: 提交校验(步骤3/6/9的引导约束)
func _tut_check_submit(checked: Array) -> bool:
	if tut_step == 3:
		var has_group := false
		var has_pair := false
		var extra := false
		for entry in checked:
			if entry.res.kind == "group" and int(entry.res.values[0]) == 3:
				has_group = true
			elif entry.res.kind == "pair" and int(entry.res.values[0]) == 2:
				has_pair = true
			else:
				extra = true
		if not (has_group and has_pair and not extra):
			_toast("按引导来: 三张3排成刻子 + 两张橙2排成对子")
			return false
	elif tut_step == 6:
		var red_run := false
		var blue_run := false
		for entry in checked:
			if entry.res.kind != "run":
				continue
			var c := -1
			for d in entry.tiles:
				if not d.def.joker:
					c = d.def.color
					break
			if c == 0 and entry.tiles.size() >= 3:
				red_run = true
			elif c == 1 and entry.tiles.size() >= 4:
				blue_run = true
		if not (red_run and blue_run):
			_toast("按引导来: 拖出刻子里的红3和手中红4红5组成顺子, 再把蓝5接到对手的蓝234后面")
			return false
	elif tut_step == 9:
		if _rack_count() > 0:
			_toast("把 ★ 和 蓝7 接到蓝色顺子尾部, 打空全部手牌!")
			return false
	_tut_set_guides([])
	return true

## 教程: 玩家结算后的旁白+脚本AI(步骤4-9)
func _tut_after_submit() -> bool:
	if tut_step == 3:
		await _tut_show("漂亮! 刻子计分 3+3+3 = 9点伤害, 对子不计分。每回合结束自动摸1张——你摸到了 蓝5。")
		_tut_show("轮到对手出牌…", false)
		await _tut_ai_turn(5)
		await _tut_show("对手打出蓝色顺子 2-3-4, 对你造成9点伤害。别慌, 它铺的牌也会成为你的素材!")
		tut_step = 6
		var guides: Array = []
		var red3 := _table_tile(0, 3)
		if red3 != null:
			guides.append(red3)
		guides += _rack_tiles_matching(0, 4) + _rack_tiles_matching(0, 5) + _rack_tiles_matching(1, 5)
		_tut_set_guides(guides)
		_tut_show("核心机制: 桌上所有牌都可重新组合! 把刻子里的 红3 拖出来, 与手中 红4红5 组成顺子; 再把 蓝5 接到对手的蓝234后面。重组旧牌有倍率加成, 完成后按「出牌」。", false)
	elif tut_step == 6:
		await _tut_show("感受到了吗! 重组3张旧牌 → 倍率1+0.5×3=2.5x, 14×2.5=35点伤害! 这就是本作的爆发引擎。你摸到了百变鬼牌★。")
		_tut_show("轮到对手出牌…", false)
		await _tut_ai_turn(8)
		await _tut_show("对手把红6接到了你的顺子上(它也会借你的场面!), 又打出橙5-6-7, 你受到24点伤害。该反击了。")
		tut_step = 9
		_tut_set_guides(_rack_tiles_matching(0, 0, true) + _rack_tiles_matching(1, 7))
		_tut_show("终结一击: 鬼牌★可以充当任何牌。把 ★ 和 蓝7 接到蓝色顺子后面(★当作蓝6), 打空手牌还有额外+20伤害, 击杀对手!", false)
	elif tut_step == 9:
		# 兜底: 步骤9提交后理应击杀; 若数值意外未达成, 直接结束教程防卡死
		enemy_hp = 0
		_update_hud()
		_show_floor_result(true)
		return false
	return true

## 教程: 固定脚本的敌方回合
func _tut_ai_turn(step: int) -> void:
	enemy_action.text = "对手思考中…"
	await get_tree().create_timer(0.5).timeout
	var dmg := 0
	if step == 5:
		var spot := _find_table_space(3)
		var defs := [
			{"color": 1, "num": 2, "joker": false},
			{"color": 1, "num": 3, "joker": false},
			{"color": 1, "num": 4, "joker": false},
		]
		if not spot.is_empty():
			for i in defs.size():
				await _place_ai_tile(defs[i], spot.r, spot.c + i)
			dmg = 9
	elif step == 8:
		# 红6接到红顺子右端
		var groups := _parse_table_groups()
		for g in groups:
			var defs_g: Array = []
			for t in g:
				defs_g.append(t.def)
			var res := Rules.check_set(defs_g)
			if res.valid and res.kind == "run" and not g[0].def.joker and g[0].def.color == 0:
				var r: int = g[0].row
				var target_c: int = g[g.size() - 1].col + 1
				if target_c < TABLE_COLS and table_grid[r][target_c] == null:
					await _place_ai_tile({"color": 0, "num": 6, "joker": false}, r, target_c)
					dmg += 6
				break
		var spot2 := _find_table_space(3)
		if not spot2.is_empty():
			var defs2 := [
				{"color": 2, "num": 5, "joker": false},
				{"color": 2, "num": 6, "joker": false},
				{"color": 2, "num": 7, "joker": false},
			]
			for i in defs2.size():
				await _place_ai_tile(defs2[i], spot2.r, spot2.c + i)
			dmg += 18
	# 整理桌面
	var groups2 := _parse_table_groups()
	var checked2: Array = []
	for g2 in groups2:
		var defs3: Array = []
		for t in g2:
			defs3.append(t.def)
		var res2 := Rules.check_set(defs3)
		if res2.valid:
			checked2.append({"tiles": g2, "res": res2})
	_auto_layout_table(checked2)
	if dmg > 0:
		player_hp -= dmg
		enemy_action.text = "出牌, 造成%d伤害!" % dmg
		battle_log.append("第%d回合 · 对手  打出 %d 伤害" % [turn, dmg])
		_shake(pbar.root)
	_update_hud()

func _refresh_relic_bar() -> void:
	for child in relic_bar.get_children():
		child.queue_free()
	var x := 0.0
	for id in relic_mgr.owned:
		var def: Dictionary = RelicManager.DEFS[id]
		var b := Button.new()
		b.text = def.short
		b.position = Vector2(x, 0)
		b.size = Vector2(40, 40)
		if ui_font != null:
			b.add_theme_font_override("font", ui_font)
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_color_override("font_color", Color("#6b4a23"))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#fdf6e8")
		sb.set_corner_radius_all(20)
		sb.border_width_bottom = 4
		sb.border_color = Color("#d9bf94")
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		var rid: String = id
		b.pressed.connect(func ():
			_toast("%s: %s" % [RelicManager.DEFS[rid].name, RelicManager.DEFS[rid].desc]))
		relic_bar.add_child(b)
		x += 46.0

func _toast(msg: String) -> void:
	toast_label.text = msg
	toast_label.modulate = Color.WHITE
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(toast_label, "modulate:a", 0.0, 0.5)

func _show_floor_result(win: bool) -> void:
	game_over = true
	for child in tiles_layer.get_children():
		if child is TileNode:
			(child as TileNode).draggable = false
	var cleared_all := win and floor_num >= FLOOR_TARGETS.size()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	overlay_nodes.append(dim)
	var panel := _rounded_panel(Rect2(80, 420, 560, 400), Color("#fdf6e8"), 24)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	overlay_nodes.append(panel)
	var win_word := "击败对手!" if mode == "battle" else "第%d层 过关!" % floor_num
	if mode == "tutorial":
		win_word = "教程完成!"
	var title_text := "通关!" if cleared_all else (win_word if win else "止步第%d层" % floor_num)
	var title := _make_label(title_text, 52, COL_TOPBAR if win else Color("#c0392b"))
	title.size = Vector2(560, 80)
	title.position = Vector2(0, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	var detail_text := "我方体力 %d · 敌方 %d" % [player_hp, enemy_hp] if mode == "battle" \
		else "得分 %d / %d" % [score, _floor_target()]
	var detail := _make_label(detail_text, 34, Color("#5b3a14"))
	detail.size = Vector2(560, 50)
	detail.position = Vector2(0, 160)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(detail)
	if win and mode == "tutorial":
		tut_panel.visible = false
		var btn_menu := _make_button("返回菜单", "green", Rect2(155, 264, 250, 84))
		btn_menu.pressed.connect(_show_mode_select)
		panel.add_child(btn_menu)
	elif win and not cleared_all:
		if mode == "battle":
			# 过层金币: 5 + 剩余体力/10 + 利息
			var gain := 5 + int(player_hp / 10.0)
			var bonus := relic_mgr.interest(gold)
			gold += gain + bonus
			var gtext := "金币 +%d (共 %d)" % [gain + bonus, gold]
			if bonus > 0:
				gtext = "金币 +%d 含利息%d (共 %d)" % [gain + bonus, bonus, gold]
			var gold_lbl := _make_label(gtext, 26, Color("#b8860b"))
			gold_lbl.size = Vector2(560, 40)
			gold_lbl.position = Vector2(0, 208)
			gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			panel.add_child(gold_lbl)
			var btn := _make_button("进入商店", "yellow", Rect2(155, 264, 250, 84))
			btn.pressed.connect(_show_shop)
			panel.add_child(btn)
		else:
			var btn := _make_button("下一层", "green", Rect2(155, 260, 250, 84))
			btn.pressed.connect(func ():
				floor_num += 1
				_start_floor())
			panel.add_child(btn)
	else:
		var btn := _make_button("重新挑战", "green", Rect2(155, 260, 250, 84))
		btn.pressed.connect(func ():
			_reset_run()
			floor_num = 1
			_start_floor())
		panel.add_child(btn)
