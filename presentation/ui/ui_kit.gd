class_name UiKit
extends RefCounted
## Kit de componentes Golmio (docs/PLANO_DE_TELAS.md §6) sobre DesignTokens, UiFrames e GameIcons.
## Fábricas sem estado: devolvem nós prontos no estilo das pranchas (papel creme, tinta preta,
## sombra dura). As telas montam com elas e só cuidam do conteúdo. Textos chegam já traduzidos.
##
## Regras do kit:
##   - uma ação principal (amarelo) por tela; o resto é papel ou azul;
##   - alvo de toque mínimo TOUCH (48 px lógicos; a casca amplia em telas pequenas);
##   - informação nunca depende só de cor (V/E/D com letra, setor com sigla, ícone com rótulo).

const TOUCH := 48.0
## Escala tipográfica (DesignTokens.TYPE_*). Display = Golmio; o resto do texto = Lexend.
const FONT_DISPLAY := DesignTokens.TYPE_DISPLAY
const FONT_TITLE := DesignTokens.TYPE_TITLE
const FONT_H2 := DesignTokens.TYPE_H2
const FONT_BODY := DesignTokens.TYPE_BODY
const FONT_SMALL := DesignTokens.TYPE_SMALL
const FONT_CAPTION := DesignTokens.TYPE_CAPTION

const INK := DesignTokens.COLOR_INK
const PAPER := DesignTokens.COLOR_PAPER
const MUTED := DesignTokens.COLOR_TEXT_SECONDARY
const YELLOW := DesignTokens.COLOR_ACCENT_YELLOW
const BLUE := DesignTokens.COLOR_ACCENT_BLUE
const GREEN := DesignTokens.COLOR_ACCENT_EMERALD
const RED := DesignTokens.COLOR_ACCENT_RED

## Tipos de botão: cor do corpo e do texto.
const BUTTON_KINDS := {
	"primary": {"fill": DesignTokens.COLOR_ACCENT_YELLOW, "hover": DesignTokens.COLOR_ACCENT_HOVER, "text": DesignTokens.COLOR_INK},
	"secondary": {"fill": DesignTokens.COLOR_BG_INPUT, "hover": DesignTokens.COLOR_BG_HOVER, "text": DesignTokens.COLOR_INK},
	"info": {"fill": DesignTokens.COLOR_ACCENT_BLUE, "hover": Color("#1a74a0"), "text": Color.WHITE},
	"destructive": {"fill": DesignTokens.COLOR_ACCENT_RED, "hover": Color("#f0563f"), "text": Color.WHITE},
	"success": {"fill": DesignTokens.COLOR_ACCENT_EMERALD, "hover": Color("#2f9a50"), "text": Color.WHITE},
}

## Resultado de partida: letra + cor (a letra garante a leitura sem cor).
const OUTCOMES := {
	"win": {"key": "RESULTADO_LETRA_V", "color": DesignTokens.COLOR_ACCENT_EMERALD},
	"draw": {"key": "RESULTADO_LETRA_E", "color": Color("#efe3b8")},
	"loss": {"key": "RESULTADO_LETRA_D", "color": DesignTokens.COLOR_ACCENT_RED},
}


# --- texto ----------------------------------------------------------------------------------

static func label(text: String, size: int = FONT_BODY, color: Color = INK, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		# Texto que quebra linha ocupa a largura livre: sem isso, numa linha (HBox) ele fica com a
		# largura mínima e quebra letra por letra.
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 60
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Deixa um rótulo de uma linha quebrar quando a largura não comporta (celular, ~360 px lógicos)
## em vez de empurrar a tela para a direita. Onde cabe, continua numa linha só.
static func wrap(l: Label, min_w: float = 60.0) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = maxf(l.custom_minimum_size.x, min_w)
	return l


## Botão de texto longo: quebra linha só quando `host` fica mais estreito que o texto numa linha
## (celular em retrato); onde cabe, fica igual. `min_w`: largura mínima do botão.
static func wrap_button(b: Button, host: Control, min_w: float = 0.0) -> void:
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var fit := func() -> void:
		b.custom_minimum_size.x = clampf(_one_line_width(b), min_w, maxf(host.size.x, min_w))
	host.resized.connect(fit)
	fit.call()


## Largura do botão com o texto numa linha (com autowrap ligado o mínimo do Button não diz).
static func _one_line_width(b: Button) -> float:
	var font := b.get_theme_font("font")
	var w := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
	var sb := b.get_theme_stylebox("normal")
	if sb:
		w += sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
	if b.icon:
		var iw := float(b.icon.get_width())
		var cap := b.get_theme_constant("icon_max_width")
		w += (minf(iw, cap) if cap > 0 else iw) + b.get_theme_constant("h_separation")
	return ceilf(w) + 2.0


static func title(text: String, size: int = FONT_TITLE) -> Label:
	var l := label(text.to_upper(), size)
	l.add_theme_font_override("font", DesignTokens.display_font())
	return l


static func caption(text: String, wrap: bool = true) -> Label:
	return label(text, FONT_CAPTION, MUTED, wrap)


## Regra ou explicação sob demanda: só a lâmpada fica na tela; tocar mostra (e esconde) o texto.
## No celular não há dica de mouse, então o texto precisa abrir no toque.
static func hint(text: String) -> VBoxContainer:
	var box := vbox(DesignTokens.SPACING_XS)
	var b := Button.new()
	b.name = "Hint"
	b.flat = true
	b.toggle_mode = true
	b.tooltip_text = text
	b.accessibility_name = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.custom_minimum_size = Vector2(TOUCH, 32)
	GameIcons.apply(b, "dica", 22)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var l := caption(text)
	l.visible = false
	b.toggled.connect(func(on: bool) -> void: l.visible = on)
	box.add_child(b)
	box.add_child(l)
	return box


## Etiqueta de seção no estilo das pranchas ("1. INÍCIO"): faixa amarela com texto em tinta.
static func section(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sb := UiFrames.frame("ui_painel_titulo", YELLOW)
	if sb == null:
		var f := StyleBoxFlat.new()
		f.bg_color = YELLOW
		f.set_corner_radius_all(int(DesignTokens.RADIUS_SM))
		f.content_margin_left = 10
		f.content_margin_right = 10
		f.content_margin_top = 3
		f.content_margin_bottom = 4
		sb = f
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(title(text, FONT_H2))
	return p


# --- botões ---------------------------------------------------------------------------------

## Botão do kit. kind: primary (amarelo, a ação da tela) | secondary | info | destructive | success.
static func button(text: String, kind: String = "secondary", icon_id: String = "", min_h: float = TOUCH) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", FONT_BODY if kind != "primary" else FONT_H2)
	b.add_theme_font_override("font", DesignTokens.display_font() if kind == "primary" else DesignTokens.text_font(DesignTokens.WEIGHT_MEDIUM))
	style_button(b, kind)
	if icon_id != "":
		GameIcons.apply(b, icon_id, 24 if min_h >= TOUCH else 18)
		# Interface por ícones: com ícone, o botão mostra só ele. Ações destrutivas (sair, abandonar)
		# mantêm o texto para o jogador não errar; quem precisa do texto o devolve com `b.text = ...`.
		if kind != "destructive" and b.icon != null:
			icon_only(b, 34 if kind == "primary" else 28)
	return b


## Tira o rótulo do botão e deixa só o ícone, num alvo de toque quadrado. O texto vira dica e
## nome acessível, então leitor de tela e mouse continuam dizendo o que o botão faz.
static func icon_only(b: Button, size: int = 28) -> Button:
	if b.text != "":
		b.tooltip_text = b.text if b.tooltip_text == "" else b.tooltip_text
		b.accessibility_name = b.text
	b.text = ""
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", size)
	b.custom_minimum_size.x = maxf(b.custom_minimum_size.y, TOUCH)
	return b


## Aplica (ou troca) o tipo de um botão existente.
static func style_button(b: Button, kind: String) -> void:
	var k: Dictionary = BUTTON_KINDS.get(kind, BUTTON_KINDS.secondary)
	b.add_theme_stylebox_override("normal", _button_box(k.fill, false))
	b.add_theme_stylebox_override("hover", _button_box(k.hover, false))
	b.add_theme_stylebox_override("pressed", _button_box(k.fill, true))
	b.add_theme_stylebox_override("hover_pressed", _button_box(k.hover, true))
	b.add_theme_stylebox_override("disabled", _button_box(DesignTokens.COLOR_DISABLED, false))
	b.add_theme_stylebox_override("focus", DesignTokens.style_focus())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, k.text)
	b.add_theme_color_override("font_disabled_color", DesignTokens.COLOR_TEXT_MUTED)
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.45))


static func _button_box(fill: Color, pressed: bool) -> StyleBox:
	var art := UiFrames.frame("ui_botao_pressionado" if pressed else "ui_botao_normal", fill)
	if art:
		return art
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = INK
	s.set_border_width_all(DesignTokens.BORDER_WIDTH)
	s.set_corner_radius_all(int(DesignTokens.RADIUS_MD))
	s.shadow_color = INK
	s.shadow_size = 1
	s.shadow_offset = Vector2(1, 1) if pressed else DesignTokens.SHADOW_OFFSET
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 10
	return s


## Botão bloqueado que diz por quê (plano: "ações bloqueadas dizem por quê").
static func locked_button(text: String, reason: String, icon_id: String = "bloqueado") -> Button:
	var b := button(text, "secondary", icon_id)
	b.disabled = true
	b.tooltip_text = reason
	# Cadeado no canto: o ícone diz o que é, o cadeado diz que ainda não abriu.
	if icon_id != "bloqueado":
		var lock := GameIcons.rect("bloqueado", 18)
		lock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		lock.offset_left = -22
		lock.offset_right = -4
		lock.offset_top = 4
		lock.offset_bottom = 22
		b.add_child(lock)
	return b


## Controle segmentado / sub-abas. items: [[id, rótulo], ...] ou [[id, rótulo, ícone], ...]: com
## ícone o botão mostra só ele (o rótulo vira dica e nome acessível). Devolve a fileira (UiSegmented: uma
## linha que quebra em duas quando não cabe); on_pick(id).
## `locked`: ids desabilitados (com `locked_reason` na dica).
static func segmented(items: Array, active: String, on_pick: Callable, locked: Array = [], locked_reason: String = "") -> UiSegmented:
	var row := UiSegmented.new()
	for it in items:
		var id := str(it[0])
		var b := Button.new()
		b.text = str(it[1])
		b.toggle_mode = true
		b.button_pressed = id == active
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", FONT_SMALL)
		b.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_MEDIUM))
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		style_button(b, "primary" if id == active else "secondary")
		if it.size() > 2 and str(it[2]) != "":
			GameIcons.apply(b, str(it[2]), 28)
			if b.icon != null:
				icon_only(b, 28)
				b.custom_minimum_size = Vector2(0, 44)
		if locked.has(id):
			b.disabled = true
			b.tooltip_text = locked_reason
		else:
			b.pressed.connect(func() -> void: on_pick.call(id))
		row.add_child(b)
	return row


# --- contêineres ----------------------------------------------------------------------------

static func vbox(separation: int = DesignTokens.SPACING_MD) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = DesignTokens.SPACING_MD) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func spacer(min_w: float = 0.0) -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size.x = min_w
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Painel de papel com contorno e sombra (ui_painel). `fill` tinge o papel (ex.: aviso).
static func card(fill: Color = DesignTokens.COLOR_BG_CARD, piece: String = "ui_painel") -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiFrames.frame(piece, fill)
	if sb == null:
		var f := DesignTokens.style_card(DesignTokens.RADIUS_LG) as StyleBoxFlat
		if f:
			f = f.duplicate()
			f.bg_color = fill
			sb = f
		else:
			sb = DesignTokens.style_card()
	p.add_theme_stylebox_override("panel", sb)
	return p


## Cartão com etiqueta de seção e um VBox de conteúdo. Devolve [cartão, vbox].
static func titled_card(text: String, fill: Color = DesignTokens.COLOR_BG_CARD) -> Array:
	var c := card(fill)
	var v := vbox(DesignTokens.SPACING_SM)
	c.add_child(v)
	if text != "":
		v.add_child(section(text))
	return [c, v]


## Linha de lista (ui_item_lista), clicável se `on_press` vier.
static func list_row(on_press: Callable = Callable(), fill: Color = DesignTokens.COLOR_BG_INPUT) -> PanelContainer:
	var p := card(fill, "ui_item_lista")
	p.custom_minimum_size.y = TOUCH + 8
	if on_press.is_valid():
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				on_press.call()
		)
	return p


## Deixa o clique atravessar os filhos (exceto botões) até a linha clicável que os contém.
static func pass_through(node: Node) -> void:
	for c in node.get_children():
		if c is Control and not (c is BaseButton):
			if (c as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
				(c as Control).mouse_filter = Control.MOUSE_FILTER_PASS
			pass_through(c)
	if node is Control and not (node is BaseButton) and (node as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_PASS


## Rolagem vertical que entrega a largura ao filho.
static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


## Coluna centralizada com largura máxima (telas largas não esticam texto de ponta a ponta).
static func column(max_width: float = 980.0) -> UiColumn:
	var c := UiColumn.new()
	c.max_width = max_width
	return c


static func separator() -> HSeparator:
	return HSeparator.new()


# --- pequenos componentes -----------------------------------------------------------------------

## Chip (ui_chip) com texto e ícone opcionais; `color` tinge a borda/fundo.
static func chip(text: String, color: Color = BLUE, icon_id: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", DesignTokens.style_badge(color))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h := hbox(DesignTokens.SPACING_XS)
	p.add_child(h)
	if icon_id != "" and GameIcons.has(icon_id):
		h.add_child(GameIcons.rect(icon_id, 16))
	var l := label(text, FONT_CAPTION, INK)
	l.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_SEMIBOLD))
	h.add_child(l)
	return p


## Chip de atleta: mini-retrato com o uniforme do clube + setor e nome curto.
static func athlete_chip(a: Athlete, kit: Dictionary) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", DesignTokens.style_badge(DesignTokens.color_for_position(a.position)))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.tooltip_text = a.name
	var h := hbox(DesignTokens.SPACING_XS)
	p.add_child(h)
	var thumb := PortraitThumb.new(24)
	thumb.set_athlete(a, kit)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(thumb)
	var l := label("%s %s" % [GameTerms.sector(a.position), short_name(a.name)], FONT_CAPTION, INK)
	l.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_SEMIBOLD))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return p


static func icon(id: String, size: float = 22.0) -> TextureRect:
	return GameIcons.rect(id, size)


## Sigla de setor colorida (GOL/DEF/MEI/ATA): cor + texto, nunca só cor.
static func sector_tag(position: String) -> Label:
	var l := label(GameTerms.sector(position), FONT_SMALL, DesignTokens.color_for_position(position))
	l.add_theme_font_override("font", DesignTokens.display_font())
	l.custom_minimum_size.x = 34
	l.tooltip_text = GameTerms.sector(position, false)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


## Selo de OVR (número em tinta sobre o amarelo, com contorno).
static func ovr_badge(value: int, size: float = 40.0) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = YELLOW
	s.border_color = INK
	s.set_border_width_all(DesignTokens.BORDER_WIDTH)
	s.set_corner_radius_all(int(DesignTokens.RADIUS_SM))
	s.content_margin_left = 4
	s.content_margin_right = 4
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(size, size * 0.8)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := label(str(value) if value >= 0 else "--", FONT_H2)
	l.add_theme_font_override("font", DesignTokens.display_font())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Quadradinho V/E/D (letra traduzida + cor).
static func outcome_badge(outcome: String, size: float = 30.0) -> PanelContainer:
	var o: Dictionary = OUTCOMES.get(outcome, OUTCOMES.draw)
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = o.color
	s.border_color = INK
	s.set_border_width_all(DesignTokens.BORDER_WIDTH)
	s.set_corner_radius_all(int(DesignTokens.RADIUS_SM))
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(size, size)
	var l := label(TranslationServer.translate(o.key), FONT_H2, INK if outcome == "draw" else Color.WHITE)
	l.add_theme_font_override("font", DesignTokens.display_font())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Barra de progresso no estilo do kit (trilho de tinta, preenchimento colorido).
static func progress(value: float, max_value: float = 100.0, color: Color = YELLOW, height: float = 14.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = max_value
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size = Vector2(40, height)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("background", DesignTokens.style_bar_track())
	b.add_theme_stylebox_override("fill", DesignTokens.style_bar_fill(color))
	return b


## Estado vazio: ícone, título, texto e (opcional) a ação que resolve.
static func empty_state(icon_id: String, heading: String, text: String, action_label: String = "", action: Callable = Callable()) -> VBoxContainer:
	var v := vbox(DesignTokens.SPACING_MD)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if icon_id != "" and GameIcons.has(icon_id):
		var ic := GameIcons.rect(icon_id, 72)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
	var h := title(heading, FONT_TITLE)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(h)
	var t := label(text, FONT_BODY, MUTED, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.custom_minimum_size.x = 260
	v.add_child(t)
	if action_label != "" and action.is_valid():
		var b := button(action_label, "primary")
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(action)
		v.add_child(b)
		wrap_button(b, v, 220)
	return v


## Linha "rótulo .... valor" (resumos, extratos).
static func key_value(key: String, value: String, value_color: Color = INK) -> HBoxContainer:
	var h := hbox(DesignTokens.SPACING_SM)
	var k := label(key, FONT_BODY, MUTED)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(k)
	var v := label(value, FONT_BODY, value_color)
	v.add_theme_font_override("font", DesignTokens.display_font())
	h.add_child(v)
	return h


## "02:14:30" (contagem regressiva real).
static func countdown_text(seconds: int) -> String:
	var s := maxi(seconds, 0)
	return "%02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


## Primeiro e último nome curtos para espaços pequenos ("Vinícius Júnior" -> "V. Júnior").
static func short_name(full: String) -> String:
	var parts := full.strip_edges().split(" ", false)
	if parts.size() <= 1:
		return full
	return "%s. %s" % [parts[0].left(1), parts[parts.size() - 1]]
