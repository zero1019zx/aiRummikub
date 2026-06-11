## 单张牌的可视节点: 奶油底圆角牌面 + 彩色数字, 支持拖拽
class_name TileNode
extends Control

signal pick_started(tile: TileNode)
signal drop_attempt(tile: TileNode, global_pos: Vector2)

const TILE_COLORS: Array[Color] = [
	Color("#e74c3c"), # 红
	Color("#2e6fd8"), # 蓝
	Color("#f39c12"), # 橙
]
const JOKER_COLOR := Color("#b14fc4")
const FACE_COLOR := Color("#fdf6e8")
const FACE_BORDER := Color("#e0c9a6")
const NEW_BORDER := Color("#f5c542")
const BAD_BORDER := Color("#e74c3c")

var def: Dictionary = {}
## 本回合开始时所在区域: "rack" 或 "table"。table牌不可回手。
var home_zone := "rack"
var zone := "rack"
var row := 0
var col := 0
var is_new := false # 本回合从手牌打到桌面
var draggable := true

var _panel: Panel
var _label: Label
var _style: StyleBoxFlat
var _dragging := false
var _drag_off := Vector2.ZERO

func setup(d: Dictionary, size_px: Vector2) -> void:
	def = d
	custom_minimum_size = size_px
	size = size_px
	mouse_filter = Control.MOUSE_FILTER_STOP

	_style = StyleBoxFlat.new()
	_style.bg_color = FACE_COLOR
	_style.set_corner_radius_all(10)
	_style.set_border_width_all(2)
	_style.border_color = FACE_BORDER
	_style.shadow_color = Color(0, 0, 0, 0.18)
	_style.shadow_size = 3
	_style.shadow_offset = Vector2(0, 2)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", _style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if def.joker:
		_label.text = "★"
		_label.add_theme_font_size_override("font_size", int(size_px.y * 0.46))
		_label.add_theme_color_override("font_color", JOKER_COLOR)
	else:
		_label.text = str(def.num)
		_label.add_theme_font_size_override("font_size", int(size_px.y * 0.46))
		_label.add_theme_color_override("font_color", TILE_COLORS[def.color])
	add_child(_label)

	# 底部小色点(Joker为紫)
	var dot := ColorRect.new()
	var dot_size := size_px.x * 0.16
	dot.size = Vector2(dot_size, dot_size)
	dot.position = Vector2((size_px.x - dot_size) / 2.0, size_px.y - dot_size - 6.0)
	dot.color = JOKER_COLOR if def.joker else TILE_COLORS[def.color]
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)

func set_new_highlight(on: bool) -> void:
	is_new = on
	_style.border_color = NEW_BORDER if on else FACE_BORDER
	_style.set_border_width_all(3 if on else 2)

func flash_bad() -> void:
	var orig := _style.border_color
	var orig_w := _style.border_width_top
	_style.border_color = BAD_BORDER
	_style.set_border_width_all(4)
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_callback(func ():
		_style.border_color = orig
		_style.set_border_width_all(orig_w))

func flash_hint() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.15)
	tw.tween_property(self, "scale", Vector2.ONE, 0.15)
	tw.set_loops(3)

func _gui_input(event: InputEvent) -> void:
	if not draggable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_off = get_global_mouse_position() - global_position
			z_index = 100
			pick_started.emit(self)
		elif _dragging:
			_dragging = false
			z_index = 0
			drop_attempt.emit(self, global_position)
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_off
