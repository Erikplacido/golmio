class_name NavBar
extends PanelContainer
## Navegação dos cinco destinos (Início, Elenco, Coleção, Clube, Loja) em três formas, conforme a
## largura (docs/PLANO_DE_TELAS.md §2):
##   BOTTOM — barra inferior do celular em retrato (só o ícone, grande; o nome fica na dica);
##   RAIL ... trilho à esquerda em telas médias (celular deitado, tablet), também só ícone;
##   TOP .... abas na barra superior em telas largas (desktop, navegador).
## Só emite tab_pressed; quem navega é a casca (Router.switch_tab).

signal tab_pressed(tab: String)

enum Mode { BOTTOM, RAIL, TOP }

const BOTTOM_H := 66.0
const RAIL_W := 92.0
const TOP_H := 44.0

var mode: int = Mode.TOP
var active := "home"
var _box: BoxContainer
var _buttons := {}


func _init(p_mode: int = Mode.TOP) -> void:
	mode = p_mode


func _ready() -> void:
	_rebuild()


func set_mode(p_mode: int) -> void:
	if p_mode == mode and _box != null:
		return
	mode = p_mode
	if is_inside_tree():
		_rebuild()


func set_active(tab: String) -> void:
	active = tab
	for t in _buttons:
		_style(_buttons[t], t == active)


func _rebuild() -> void:
	if _box:
		_box.queue_free()
		remove_child(_box)
	_buttons.clear()
	var sb := StyleBoxFlat.new()
	sb.bg_color = DesignTokens.COLOR_BG_SURFACE
	sb.border_color = DesignTokens.COLOR_INK
	match mode:
		Mode.BOTTOM:
			sb.border_width_top = 2
			sb.set_content_margin_all(DesignTokens.SPACING_XS)
			custom_minimum_size = Vector2(0, BOTTOM_H)
			_box = HBoxContainer.new()
		Mode.RAIL:
			sb.border_width_right = 2
			sb.set_content_margin_all(DesignTokens.SPACING_SM)
			custom_minimum_size = Vector2(RAIL_W, 0)
			_box = VBoxContainer.new()
		_:
			sb.draw_center = false
			sb.set_content_margin_all(0)
			custom_minimum_size = Vector2(0, TOP_H)
			_box = HBoxContainer.new()
	add_theme_stylebox_override("panel", sb)
	_box.add_theme_constant_override("separation", DesignTokens.SPACING_XS)
	add_child(_box)
	for tab in Routes.TABS:
		var b := Button.new()
		b.name = "Tab_" + tab
		b.text = tr(Routes.TAB_LABELS[tab])
		b.tooltip_text = b.text
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.clip_text = true
		GameIcons.apply(b, Routes.TAB_ICONS[tab], 34 if mode != Mode.TOP else 28)
		# Só o ícone, em qualquer largura. O nome continua na dica e como nome acessível.
		if b.icon != null:
			b.accessibility_name = b.text
			b.text = ""
		match mode:
			Mode.BOTTOM:
				b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
				b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				b.custom_minimum_size = Vector2(0, BOTTOM_H - 8)
				b.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
				b.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_SEMIBOLD))
			Mode.RAIL:
				b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
				b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				b.custom_minimum_size = Vector2(0, 60)
				b.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
				b.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_SEMIBOLD))
			_:
				b.custom_minimum_size = Vector2(0, TOP_H)
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				# Display só em caixa-alta (como nas pranchas): em caixa-baixa a Golmio fica espaçada.
				b.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
				b.add_theme_font_override("font", DesignTokens.display_font())
		var t: String = tab
		b.pressed.connect(func() -> void: tab_pressed.emit(t))
		_style(b, tab == active)
		_box.add_child(b)
		_buttons[tab] = b


func _style(b: Button, on: bool) -> void:
	if mode == Mode.TOP:
		UiKit.style_button(b, "primary" if on else "secondary")
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			DesignTokens.compact_margins(b.get_theme_stylebox(st), 10, 4)
		return
	# Barra e trilho: sem moldura; a aba ativa ganha o fundo amarelo com contorno.
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(int(DesignTokens.RADIUS_MD))
		s.set_content_margin_all(4)
		if on:
			s.bg_color = DesignTokens.COLOR_ACCENT_YELLOW
			s.border_color = DesignTokens.COLOR_INK
			s.set_border_width_all(2)
		elif st == "hover":
			s.bg_color = DesignTokens.COLOR_BG_HOVER
		elif st == "focus":
			s.draw_center = false
			s.border_color = DesignTokens.COLOR_ACCENT_BLUE
			s.set_border_width_all(2)
		else:
			s.draw_center = false
		b.add_theme_stylebox_override(st, s)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, DesignTokens.COLOR_INK)
