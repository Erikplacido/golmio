class_name ClubCrest
extends Control
## Escudo do clube desenhado por código (GDD 1.1): forma na cor principal, desenho interno na
## secundária, contorno de tinta e a sigla. O brasão (`crest_id`, catálogo em Cosmetics.CRESTS)
## escolhe a forma e o desenho. Serve para o clube do jogador (Club) e para adversários (cor + sigla).

const OUTLINE := 2.5

var primary := Color("#c8102e")
var secondary := Color.WHITE
var sigla := ""
## Brasão (Cosmetics.CRESTS): forma do escudo e desenho interno.
var crest_id := Cosmetics.DEFAULT_CREST:
	set(v):
		crest_id = v if Cosmetics.CRESTS.has(v) else Cosmetics.DEFAULT_CREST
		queue_redraw()


func _init(p_size: float = 40.0) -> void:
	custom_minimum_size = Vector2(p_size, p_size * 1.15)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func for_club(club: Club, p_size: float = 40.0) -> ClubCrest:
	var c := ClubCrest.new(p_size)
	if club:
		c.primary = club.primary_color()
		c.secondary = Color.from_string(str(club.colors.get("secondary", "#ffffff")), Color.WHITE)
		c.sigla = club.short_name
		var identity: Variant = club.ext.get("club_identity", {})
		if identity is Dictionary:
			c.crest_id = str(identity.get("crest_id", ""))
	return c


static func for_colors(p_primary: Color, p_secondary: Color, p_sigla: String, p_size: float = 40.0) -> ClubCrest:
	var c := ClubCrest.new(p_size)
	c.primary = p_primary
	c.secondary = p_secondary
	c.sigla = p_sigla
	return c


func _shield(r: Rect2) -> PackedVector2Array:
	var w := r.size.x
	var h := r.size.y
	var o := r.position
	match str(Cosmetics.CRESTS[crest_id].shape):
		"redondo":
			var pts := PackedVector2Array()
			var rad := minf(w, h) / 2.0
			for i in 40:
				pts.append(r.get_center() + Vector2.from_angle(TAU * i / 40.0) * rad)
			return pts
		"frances":
			return PackedVector2Array([o, o + Vector2(w, 0.0), o + Vector2(w, h * 0.62),
				o + Vector2(w * 0.5, h), o + Vector2(0.0, h * 0.62)])
		"flamula":
			return PackedVector2Array([o + Vector2(0.0, h * 0.04), o + Vector2(w, h * 0.04),
				o + Vector2(w * 0.5, h)])
		"losango":
			return PackedVector2Array([o + Vector2(w * 0.5, 0.0), o + Vector2(w, h * 0.5),
				o + Vector2(w * 0.5, h), o + Vector2(0.0, h * 0.5)])
	return PackedVector2Array([
		o + Vector2(0.0, h * 0.06), o + Vector2(w * 0.5, 0.0), o + Vector2(w, h * 0.06),
		o + Vector2(w, h * 0.52), o + Vector2(w * 0.86, h * 0.76), o + Vector2(w * 0.5, h),
		o + Vector2(w * 0.14, h * 0.76), o + Vector2(0.0, h * 0.52),
	])


func _draw() -> void:
	var r := Rect2(Vector2(OUTLINE, OUTLINE), size - Vector2(OUTLINE, OUTLINE) * 2.0)
	var pts := _shield(r)
	draw_colored_polygon(_shield(r.grow(-0.5)).duplicate(), primary)
	# Desenho interno na cor secundária, recortado pelo escudo (polígonos intersectados).
	for shape in _motif(r):
		for poly in Geometry2D.intersect_polygons(shape, pts):
			draw_colored_polygon(poly, secondary)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, DesignTokens.COLOR_INK, OUTLINE, true)
	if sigla != "":
		var f := DesignTokens.font(true)
		var fs := maxi(int(r.size.x * (0.34 if sigla.length() <= 3 else 0.26)), 8)
		var tw := f.get_string_size(sigla, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y := 0.62 if Cosmetics.CRESTS[crest_id].motif == "estrela" else 0.5
		var pos := Vector2(r.get_center().x - tw / 2.0, r.position.y + r.size.y * y + fs * 0.35)
		draw_string_outline(f, pos, sigla, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(int(fs * 0.3), 2), DesignTokens.COLOR_INK)
		draw_string(f, pos, sigla, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## Polígonos do desenho interno (antes do recorte pela forma).
func _motif(r: Rect2) -> Array:
	var o := r.position
	var w := r.size.x
	var h := r.size.y
	var quad := func(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
		return PackedVector2Array([o + Vector2(w * x0, h * y0), o + Vector2(w * x1, h * y0),
			o + Vector2(w * x1, h * y1), o + Vector2(w * x0, h * y1)])
	match str(Cosmetics.CRESTS[crest_id].motif):
		"faixa_vertical":
			return [quad.call(0.40, 0.0, 0.60, 1.0)]
		"metades":
			return [quad.call(0.5, 0.0, 1.0, 1.0)]
		"faixa_diagonal":
			return [PackedVector2Array([o + Vector2(w * -0.1, h * 0.15), o + Vector2(w * 0.1, 0.0),
				o + Vector2(w * 1.1, h * 0.85), o + Vector2(w * 0.9, h)])]
		"listras":
			return [quad.call(0.14, 0.0, 0.30, 1.0), quad.call(0.42, 0.0, 0.58, 1.0), quad.call(0.70, 0.0, 0.86, 1.0)]
		"estrela":
			# Estrela no alto; a sigla fica embaixo dela.
			var c := o + Vector2(w * 0.5, h * 0.24)
			var star := PackedVector2Array()
			for i in 10:
				var rad := w * (0.16 if i % 2 == 0 else 0.07)
				star.append(c + Vector2.from_angle(-PI / 2.0 + PI * i / 5.0) * rad)
			return [star]
	return []
