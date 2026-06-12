## 单张牌的可视节点: 程序生成的贴图牌面(奶油渐变+皇冠水印+烘焙数字), 支持拖拽
class_name TileNode
extends Control

signal pick_started(tile: TileNode)
signal drop_attempt(tile: TileNode, global_pos: Vector2)
signal clicked(tile: TileNode)

const NEW_BORDER := Color("#f5c542")
const BAD_BORDER := Color("#e74c3c")
const SELECT_BORDER := Color("#4db8ff")

var def: Dictionary = {}
## 本回合开始时所在区域: "rack" 或 "table"。table牌不可回手。
var home_zone := "rack"
var zone := "rack"
var row := 0
var col := 0
var is_new := false # 本回合从手牌打到桌面
var draggable := true
var select_mode := false # 换牌选择模式: 点击切换选中, 不可拖拽
var selected := false
var owner_tag := "player" # 谁打出的: "player"/"enemy" (夺地旗等遗物用)
## 每张牌全局唯一ID(快照/重组判定用, 撤回重建时保留)
var uid := -1

var _overlay_style: StyleBoxFlat
var _dragging := false
var _drag_off := Vector2.ZERO
var _guide_tw: Tween

## 教程引导: 持续呼吸缩放直到关闭
func set_guide(on: bool) -> void:
	if _guide_tw != null:
		_guide_tw.kill()
		_guide_tw = null
		scale = Vector2.ONE
	if on:
		_guide_tw = create_tween().set_loops()
		_guide_tw.tween_property(self, "scale", Vector2(1.1, 1.1), 0.4)
		_guide_tw.tween_property(self, "scale", Vector2.ONE, 0.4)

func setup(d: Dictionary, size_px: Vector2) -> void:
	def = d
	custom_minimum_size = size_px
	size = size_px
	pivot_offset = size_px / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 软投影: 画在贴图后面(不能用透明覆盖层的shadow, 否则会蒙暗整张牌)
	var shadow := Panel.new()
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color(0, 0, 0, 0.22)
	shadow_style.set_corner_radius_all(14)
	shadow.add_theme_stylebox_override("panel", shadow_style)
	shadow.position = Vector2(2, 5)
	shadow.size = size_px - Vector2(4, 2)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)

	var tex := TextureRect.new()
	var path := "res://assets/tiles/tile_joker.png" if def.joker \
		else "res://assets/tiles/tile_%d_%d.png" % [def.color, def.num]
	tex.texture = load(path)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.size = size_px
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tex)

	# 高亮/报错描边层(纯描边, 无填充无阴影)
	_overlay_style = StyleBoxFlat.new()
	_overlay_style.bg_color = Color(0, 0, 0, 0)
	_overlay_style.set_corner_radius_all(12)
	_overlay_style.set_border_width_all(0)
	_overlay_style.border_color = NEW_BORDER
	var overlay := Panel.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_theme_stylebox_override("panel", _overlay_style)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

func set_new_highlight(on: bool) -> void:
	is_new = on
	_overlay_style.border_color = NEW_BORDER
	_overlay_style.set_border_width_all(4 if on else 0)

func set_selected(on: bool) -> void:
	selected = on
	if on:
		_overlay_style.border_color = SELECT_BORDER
		_overlay_style.set_border_width_all(4)
	else:
		set_new_highlight(is_new)

func flash_bad() -> void:
	var orig := _overlay_style.border_color
	var orig_w := _overlay_style.border_width_top
	_overlay_style.border_color = BAD_BORDER
	_overlay_style.set_border_width_all(5)
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_callback(func ():
		_overlay_style.border_color = orig
		_overlay_style.set_border_width_all(orig_w))

## 临时染色描边(伤害结算高亮等), 1秒后恢复
func flash_color(col: Color) -> void:
	_overlay_style.border_color = col
	_overlay_style.set_border_width_all(4)
	var tw := create_tween()
	tw.tween_interval(1.1)
	tw.tween_callback(func ():
		set_new_highlight(is_new))

func flash_hint() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.15)
	tw.tween_property(self, "scale", Vector2.ONE, 0.15)
	tw.set_loops(3)

func _gui_input(event: InputEvent) -> void:
	if select_mode:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			clicked.emit(self)
		return
	if not draggable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_off = get_global_mouse_position() - global_position
			z_index = 100
			scale = Vector2(1.08, 1.08)
			pick_started.emit(self)
		elif _dragging:
			_dragging = false
			z_index = 0
			scale = Vector2.ONE
			drop_attempt.emit(self, global_position)
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_off
