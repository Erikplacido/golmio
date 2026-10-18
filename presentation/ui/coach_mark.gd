class_name CoachMark
extends Control
## Dica guiada (coach mark, prancha 06): escurece a tela, deixa um recorte em volta do alvo com
## contorno amarelo e mostra o balão "1/3 · título · texto" com Pular e Próximo. Ensina fazendo:
## no máximo MAX_STEPS passos, sempre puláveis. Vive na OverlayLayer (Router.overlays.coach()).

signal finished(skipped: bool)

const MAX_STEPS := 3
const DIM := Color(0, 0, 0, 0.55)
const PAD := 8.0
const BUBBLE_W := 340.0

var _steps: Array = []
var _index := 0
var _layer: OverlayLayer
var _hole := Rect2()
var _bubble: PanelContainer
var _counter: Label
var _title: Label
var _text: Label
var _next: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bubble = UiKit.card(DesignTokens.COLOR_BG_CARD, "ui_janela")
	_bubble.custom_minimum_size.x = BUBBLE_W
	add_child(_bubble)
	var v := UiKit.vbox(DesignTokens.SPACING_SM)
	_bubble.add_child(v)
	_counter = UiKit.label("", UiKit.FONT_SMALL, UiKit.BLUE)
	v.add_child(_counter)
	_title = UiKit.title("", UiKit.FONT_H2)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	_text = UiKit.label("", UiKit.FONT_BODY, UiKit.INK, true)
	v.add_child(_text)
	var row := UiKit.hbox(DesignTokens.SPACING_SM)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var skip_b := UiKit.button(tr("UI_PULAR"), "secondary", "", 40)
	skip_b.pressed.connect(skip)
	row.add_child(skip_b)
	_next = UiKit.button(tr("UI_PROXIMO"), "primary", "", 40)
	_next.pressed.connect(next)
	row.add_child(_next)


func start(steps: Array, layer: OverlayLayer = null) -> void:
	_steps = steps
	_layer = layer
	_index = 0
	if _steps.is_empty():
		_finish(false)
		return
	_show.call_deferred()


func next() -> void:
	_index += 1
	if _index >= _steps.size():
		_finish(false)
	else:
		_show()


func skip() -> void:
	_finish(true)


func current_step() -> int:
	return _index


func _finish(skipped: bool) -> void:
	finished.emit(skipped)
	queue_free()


func _show() -> void:
	if not is_inside_tree() or _index >= _steps.size():
		return
	var st: Dictionary = _steps[_index]
	_counter.text = "%d/%d" % [_index + 1, _steps.size()]
	_title.text = str(st.get("title", ""))
	_text.text = str(st.get("text", ""))
	_next.text = tr("UI_ENTENDI") if _index == _steps.size() - 1 else tr("UI_PROXIMO")
	_hole = _target_rect(st.get("target"))
	_place_bubble()
	queue_redraw()


## Retângulo do alvo no espaço deste controle (a camada é ampliada pela escala de leitura).
func _target_rect(target: Variant) -> Rect2:
	var k := _layer.logical_scale() if _layer else 1.0
	var r := Rect2()
	if target is Control and is_instance_valid(target) and (target as Control).is_visible_in_tree():
		r = (target as Control).get_global_rect()
	elif target is Rect2:
		r = target
	else:
		return Rect2()
	return Rect2(r.position / k, r.size / k).grow(PAD)


func _place_bubble() -> void:
	var w := minf(BUBBLE_W, size.x - 24.0)
	_bubble.custom_minimum_size.x = w
	_bubble.reset_size()
	var bs := _bubble.get_combined_minimum_size()
	var pos := Vector2((size.x - w) / 2.0, (size.y - bs.y) / 2.0)
	if _hole.has_area():
		pos.x = clampf(_hole.get_center().x - w / 2.0, 12.0, size.x - w - 12.0)
		var below := _hole.end.y + 12.0
		var above := _hole.position.y - bs.y - 12.0
		pos.y = below if below + bs.y <= size.y - 12.0 else maxf(above, 12.0)
	_bubble.position = pos
	_bubble.size = Vector2(w, bs.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not _steps.is_empty():
		_show()


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if not _hole.has_area():
		draw_rect(full, DIM)
		return
	var h := _hole.intersection(full)
	draw_rect(Rect2(0, 0, size.x, h.position.y), DIM)
	draw_rect(Rect2(0, h.end.y, size.x, size.y - h.end.y), DIM)
	draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), DIM)
	draw_rect(Rect2(h.end.x, h.position.y, size.x - h.end.x, h.size.y), DIM)
	draw_rect(h, DesignTokens.COLOR_ACCENT_YELLOW, false, 4.0)
	draw_rect(h.grow(2.0), DesignTokens.COLOR_INK, false, 1.5)


## O recorte deixa o toque passar para o alvo: a dica ensina fazendo.
func _has_point(point: Vector2) -> bool:
	return not _hole.has_point(point)
