class_name KitThumb
extends Control
## Camisa em miniatura desenhada por código: mostra o padrão (com as cores e repetições do kit) e a
## gola, para escolher pelo desenho em vez do nome. Usa a mesma fórmula do retrato
## (UniformMaps.pattern_index), então a miniatura bate com a figurinha.

const CELL := 2.0

var kit: Dictionary = {}:
	set(v):
		kit = v
		queue_redraw()
## Só a gola em destaque (escolha de gola): corpo liso na cor principal.
var collar_only := false
var locked := false:
	set(v):
		locked = v
		queue_redraw()


func _init(p_size: float = 56.0) -> void:
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _shirt(r: Rect2) -> PackedVector2Array:
	var o := r.position
	var w := r.size.x
	var h := r.size.y
	return PackedVector2Array([
		o + Vector2(w * 0.34, 0.0), o + Vector2(w * 0.66, 0.0), o + Vector2(w, h * 0.18),
		o + Vector2(w * 0.88, h * 0.40), o + Vector2(w * 0.76, h * 0.34), o + Vector2(w * 0.76, h),
		o + Vector2(w * 0.24, h), o + Vector2(w * 0.24, h * 0.34), o + Vector2(w * 0.12, h * 0.40),
		o + Vector2(0.0, h * 0.18),
	])


func _draw() -> void:
	var r := Rect2(Vector2(size.x * 0.06, size.y * 0.10), size * Vector2(0.88, 0.82))
	var poly := _shirt(r)
	var body := Rect2(r.position + Vector2(r.size.x * 0.24, 0.0), Vector2(r.size.x * 0.52, r.size.y))
	var sleeve := UniformMaps.kit_color(kit, UniformMaps.color_index(kit.get("sleeve_color", 0)))
	draw_colored_polygon(poly, sleeve)
	# Corpo: amostra a estampa em células pequenas dentro da silhueta.
	var aspect := body.size.y / body.size.x
	var y := body.position.y
	while y < body.end.y:
		var x := body.position.x
		while x < body.end.x:
			var c := Vector2(x + CELL / 2.0, y + CELL / 2.0)
			if Geometry2D.is_point_in_polygon(c, poly):
				var idx := 0 if collar_only else UniformMaps.pattern_index(kit,
					(c.x - body.position.x) / body.size.x, (c.y - body.position.y) / body.size.y, aspect)
				draw_rect(Rect2(x, y, CELL, CELL), UniformMaps.kit_color(kit, idx))
			x += CELL
		y += CELL
	_draw_collar(r)
	var closed := poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, DesignTokens.COLOR_INK, 1.5, true)
	if locked:
		draw_rect(Rect2(Vector2.ZERO, size), Color(DesignTokens.COLOR_BG_SURFACE, 0.55))
		GameIcons.draw(self, "bloqueado", size / 2.0, size.x * 0.42)


func _draw_collar(r: Rect2) -> void:
	var col := UniformMaps.kit_color(kit, UniformMaps.color_index(kit.get("collar_color", 2)))
	var cx := r.position.x + r.size.x * 0.5
	var top := r.position.y
	# Na escolha de gola ela é o assunto: desenho maior e traço mais grosso.
	var k := 1.5 if collar_only else 1.0
	var w := r.size.x * 0.32 * k
	var th := 4.0 * k
	var ink := DesignTokens.COLOR_INK
	var id := str(kit.get("collar", ""))
	if id.contains("gola V") or id.contains("vintage"):
		var v := PackedVector2Array([Vector2(cx - w / 2.0, top), Vector2(cx, top + r.size.y * 0.24 * k), Vector2(cx + w / 2.0, top)])
		draw_polyline(v, col, th, true)
		draw_polyline(v, ink, 1.0, true)
	elif id.contains("polo"):
		draw_arc(Vector2(cx, top), w / 2.0, 0.0, PI, 16, col, th, true)
		for sx in [-1.0, 1.0]:
			var flap := PackedVector2Array([Vector2(cx, top + 2), Vector2(cx + sx * w * 0.55, top),
				Vector2(cx + sx * w * 0.35, top + r.size.y * 0.16)])
			draw_colored_polygon(flap, col)
			flap.append(flap[0])
			draw_polyline(flap, ink, 1.0, true)
	elif id.contains("mandarim"):
		var band := Rect2(cx - w / 2.0, top - 1.0, w, r.size.y * 0.08 * k)
		draw_rect(band, col)
		draw_rect(band, ink, false, 1.0)
	elif id != "nenhuma":
		draw_arc(Vector2(cx, top), w / 2.0, 0.0, PI, 16, col, th, true)
		draw_arc(Vector2(cx, top), w / 2.0 + th / 2.0, 0.0, PI, 16, ink, 1.0, true)
