class_name TitleButton
extends Button
## Botões da abertura desenhados no mesmo estilo do logo GOL MIO: contorno grosso de tinta, face
## com degrau embaixo (a "espessura" do botão) e brilho no alto.
##   PLAY: pílula amarela com ▶ e o texto (JOGAR).
##   SETTINGS / SOUND: discos creme com a engrenagem ou o alto-falante (riscado quando mudo).
## Ao apertar, a face afunda no degrau; com o mouse por cima, cresce um pouco; com `attention`,
## respira (pulsa) para chamar o toque. `appear` (0..1) é a escala de entrada, animada por fora.
## O tamanho é o da arte da abertura (px da arte): quem posiciona é a TitleScreen.

enum Kind { PLAY, SETTINGS, SOUND }

const ShineShader := preload("res://presentation/title/title_shine.gdshader")
const OUTLINE := 9.0
const LIP := 16.0                 # altura do degrau da pílula
const ROUND_OUTLINE := 7.0
const ROUND_LIP := 7.0
const INK := Color("#000000")
const YELLOW := Color("#fec12e")
const YELLOW_LIGHT := Color("#ffe27e")
const ORANGE := Color("#d47a0c")
const CREAM := Color("#fbf1ce")
const CREAM_SHADE := Color("#cdb98a")

var kind := Kind.PLAY
var label := ""
var muted := false:
	set(v):
		muted = v
		queue_redraw()
var attention := false
var appear := 1.0

var _press := 0.0                 # 0 solto → 1 afundado
var _hover := 0.0
var _time := 0.0
var _shine: ShaderMaterial


func _init(k: Kind = Kind.PLAY, text_label: String = "") -> void:
	kind = k
	label = text_label
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for sb_name in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(sb_name, StyleBoxEmpty.new())
	if kind == Kind.PLAY:
		_shine = ShaderMaterial.new()
		_shine.shader = ShineShader
		material = _shine
	resized.connect(_on_resized)


func _on_resized() -> void:
	pivot_offset = size / 2.0
	if _shine:
		_shine.set_shader_parameter("rect_size", size)


## Passa o reflexo pela face (só no JOGAR).
func shine(duration := 0.7) -> void:
	if _shine == null:
		return
	create_tween().tween_method(func(v: float): _shine.set_shader_parameter("progress", v), -0.2, 1.2, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _process(delta: float) -> void:
	_time += delta
	var dm := get_draw_mode()
	var down := dm == DRAW_PRESSED or dm == DRAW_HOVER_PRESSED
	var over := dm == DRAW_HOVER or down
	var p := move_toward(_press, 1.0 if down else 0.0, delta * 16.0)
	if p != _press:
		_press = p
		queue_redraw()
	_hover = lerpf(_hover, 1.0 if over else 0.0, 1.0 - exp(-delta * 14.0))
	var pulse := 0.0
	if attention and not down:
		pulse = 0.5 - 0.5 * cos(_time * TAU / 1.4)
	var s := appear * (1.0 + 0.05 * _hover - 0.05 * _press)
	scale = Vector2(s * (1.0 + 0.045 * pulse), s * (1.0 + 0.03 * pulse))


func _draw() -> void:
	if kind == Kind.PLAY:
		_draw_play()
	else:
		_draw_round()


func _draw_play() -> void:
	var w := size.x
	var h := size.y
	var r := h * 0.3
	var sink := LIP * 0.75 * _press
	# Sombra no chão, outline (inclui o degrau), degrau laranja e face amarela por cima.
	draw_style_box(_box(Color(0, 0, 0, 0.35), r), Rect2(10, 14 + sink, w - 20, h - 6 - sink))
	draw_style_box(_box(INK, r), Rect2(0, sink, w, h - sink))
	var inner := Rect2(OUTLINE, OUTLINE + sink, w - OUTLINE * 2.0, h - OUTLINE * 2.0 - sink)
	draw_style_box(_box(ORANGE, r - OUTLINE), inner)
	var face := Rect2(inner.position, Vector2(inner.size.x, h - OUTLINE * 2.0 - LIP))
	draw_style_box(_box(YELLOW, r - OUTLINE), face)
	var hl := Rect2(face.position + Vector2(r * 0.55, face.size.y * 0.09),
		Vector2(face.size.x - r * 1.1, face.size.y * 0.3))
	draw_style_box(_box(Color(YELLOW_LIGHT, 0.85), hl.size.y / 2.0), hl)

	# ▶ + texto, centrados na face.
	var font := DesignTokens.display_font()
	var fs := int(face.size.y * 0.58)
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font else 0.0
	var tri_w := fs * 0.62
	var gap := fs * 0.3
	var x := face.get_center().x - (tri_w + gap + tw) / 2.0
	var cy := face.get_center().y + face.size.y * 0.02
	var th := tri_w * 1.12
	var tri := PackedVector2Array([Vector2(x, cy - th / 2.0), Vector2(x + tri_w, cy), Vector2(x, cy + th / 2.0)])
	draw_colored_polygon(tri, INK)
	tri.append(tri[0])
	draw_polyline(tri, INK, fs * 0.08, true)     # cantos arredondados
	if font:
		var base := cy + (font.get_ascent(fs) - font.get_descent(fs)) / 2.0
		draw_string(font, Vector2(x + tri_w + gap, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)


func _draw_round() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0
	var sink := ROUND_LIP * 0.8 * _press
	draw_circle(c + Vector2(0, 7), r, Color(0, 0, 0, 0.35))
	draw_circle(c, r, INK)
	draw_circle(c, r - ROUND_OUTLINE, CREAM_SHADE)
	var fr := r - ROUND_OUTLINE - ROUND_LIP / 2.0
	var fc := c - Vector2(0, ROUND_LIP / 2.0 - sink)
	draw_circle(fc, fr, CREAM)
	draw_circle(fc + Vector2(-fr * 0.32, -fr * 0.4), fr * 0.28, Color(1, 1, 1, 0.45))
	if kind == Kind.SETTINGS:
		if GameIcons.has("ajustes"):
			GameIcons.draw(self, "ajustes", fc, fr * 1.25)
		else:
			GearButton.draw_gear(self, fc, fr * 0.62, INK)
	else:
		_draw_speaker(fc, fr * 1.15)


## Alto-falante com ondas (ou um X quando mudo), cabendo num quadrado de lado `s`.
func _draw_speaker(c: Vector2, s: float) -> void:
	var o := c - Vector2(s * 0.14, 0)
	var body := PackedVector2Array()
	for v in [Vector2(-0.42, -0.15), Vector2(-0.2, -0.15), Vector2(0.04, -0.38),
			Vector2(0.04, 0.38), Vector2(-0.2, 0.15), Vector2(-0.42, 0.15)]:
		body.append(o + v * s)
	draw_colored_polygon(body, INK)
	var lw := s * 0.1
	if muted:
		var x := o + Vector2(s * 0.38, 0)
		var d := s * 0.15
		draw_line(x + Vector2(-d, -d), x + Vector2(d, d), INK, lw, true)
		draw_line(x + Vector2(-d, d), x + Vector2(d, -d), INK, lw, true)
	else:
		var a := o + Vector2(s * 0.06, 0)
		draw_arc(a, s * 0.2, -0.85, 0.85, 12, INK, lw, true)
		draw_arc(a, s * 0.38, -0.9, 0.9, 16, INK, lw, true)


static func _box(col: Color, radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(maxf(radius, 0.0)))
	sb.corner_detail = 12
	sb.anti_aliasing = true
	return sb
