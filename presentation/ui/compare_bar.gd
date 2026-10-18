class_name CompareBar
extends VBoxContainer
## Barra comparativa (pré-jogo, intervalo, resultado): rótulo no meio, valor de cada lado e uma
## barra dividida na proporção. O valor maior fica em negrito e a divisão da barra mostra a
## proporção: a diferença não depende só da cor.

const BAR_H := 12.0

var _bar: Control
var _left := 0.0
var _right := 0.0
var _left_color := DesignTokens.COLOR_ACCENT_BLUE
var _right_color := DesignTokens.COLOR_ACCENT_RED


## `fmt`: como mostrar os números (ex.: "%d", "%.2f", "%d%%").
static func make(caption: String, left: float, right: float, left_color: Color, right_color: Color,
		fmt: String = "%d") -> CompareBar:
	var c := CompareBar.new()
	c._left = maxf(left, 0.0)
	c._right = maxf(right, 0.0)
	c._left_color = left_color
	c._right_color = right_color
	c.add_theme_constant_override("separation", 2)
	var row := UiKit.hbox(DesignTokens.SPACING_SM)
	var lv := UiKit.label(_fmt(fmt, left), UiKit.FONT_BODY)
	var rv := UiKit.label(_fmt(fmt, right), UiKit.FONT_BODY)
	if left > right:
		lv.add_theme_font_override("font", DesignTokens.font(true))
	if right > left:
		rv.add_theme_font_override("font", DesignTokens.font(true))
	lv.custom_minimum_size.x = 56
	rv.custom_minimum_size.x = 56
	rv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var mid := UiKit.label(caption, UiKit.FONT_SMALL, UiKit.MUTED)
	mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lv)
	row.add_child(mid)
	row.add_child(rv)
	c.add_child(row)
	c._bar = Control.new()
	c._bar.custom_minimum_size = Vector2(80, BAR_H)
	c._bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c._bar.draw.connect(c._draw_bar)
	c.add_child(c._bar)
	return c


static func _fmt(fmt: String, v: float) -> String:
	return fmt % (roundi(v) if fmt.contains("%d") else v)


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, _bar.size)
	var total := _left + _right
	var k := 0.5 if total <= 0.0 else _left / total
	var split := r.size.x * k
	_bar.draw_rect(Rect2(r.position, Vector2(split, r.size.y)), _left_color if total > 0.0 else DesignTokens.COLOR_BORDER_SUBTLE)
	_bar.draw_rect(Rect2(r.position + Vector2(split, 0), Vector2(r.size.x - split, r.size.y)), _right_color if total > 0.0 else DesignTokens.COLOR_BORDER_SUBTLE)
	_bar.draw_line(Vector2(split, 0), Vector2(split, r.size.y), DesignTokens.COLOR_PAPER, 2.0)
	_bar.draw_rect(r, DesignTokens.COLOR_INK, false, 2.0)
