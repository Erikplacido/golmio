class_name GearButton
extends Button
## Botão de "Opções" com o ícone "ajustes" (GameIcons) ou, sem ele, uma engrenagem desenhada (não
## depende de glifo: no navegador a fonte padrão não tem emoji nem ⚙). Com texto, o ícone fica à
## esquerda; sem texto, centralizado.
## Ao ser pressionado abre o painel do autoload Settings.

const ICON_SIZE := 18.0
const ICON_GAP := 8.0

var icon_color := Color("#e2e8f0")


func _init(label: String = "") -> void:
	text = label
	tooltip_text = "Configurações (F10)"
	focus_mode = Control.FOCUS_NONE
	pressed.connect(_on_pressed)


func _ready() -> void:
	var pad := ICON_SIZE + ICON_GAP if text != "" else 0.0
	for sb_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBox = get_theme_stylebox(sb_name)
		if sb and pad > 0.0:
			sb = sb.duplicate()
			sb.content_margin_left = maxf(sb.content_margin_left, 10.0) + pad
			add_theme_stylebox_override(sb_name, sb)
	if text == "":
		custom_minimum_size = custom_minimum_size.max(Vector2(40, 40))


func _on_pressed() -> void:
	var s := get_node_or_null("/root/Settings")
	if s:
		s.open_panel()


func _draw() -> void:
	var sb: StyleBox = get_theme_stylebox("normal")
	var left := (sb.content_margin_left - ICON_SIZE - ICON_GAP) if (text != "" and sb) else 0.0
	var c := Vector2(left + ICON_SIZE / 2.0, size.y / 2.0) if text != "" else size / 2.0
	# Só o ícone: ele ocupa o botão (com 18 px fixos virava um ponto em telas pequenas).
	var icon_size := ICON_SIZE if text != "" else maxf(ICON_SIZE, minf(size.x, size.y) * 0.5)
	# Ícone "ajustes" do pacote sobre um disco claro (a engrenagem é quase preta e sumiria no
	# fundo escuro); sem o ícone, a engrenagem desenhada.
	if GameIcons.has("ajustes"):
		draw_circle(c, icon_size * 0.72, Color("#efe6d2"))
		GameIcons.draw(self, "ajustes", c, icon_size * 1.15)
	else:
		draw_gear(self, c, icon_size / 2.0, icon_color)


## Engrenagem de 8 dentes centrada em `c` com raio externo `r`.
static func draw_gear(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var teeth := 8
	var pts := PackedVector2Array()
	var inner := r * 0.72
	for i in teeth * 4:
		var a := TAU * float(i) / float(teeth * 4)
		var rr := r if (i % 4 == 1 or i % 4 == 2) else inner
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, col)
	ci.draw_circle(c, r * 0.32, Color(0.05, 0.07, 0.12))
