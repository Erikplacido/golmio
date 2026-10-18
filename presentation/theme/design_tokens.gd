class_name DesignTokens
extends RefCounted
## Design Tokens & Sistema Visual Unificado do FOTEBA (Godot 4).
## Fonte única da verdade para paleta, tipografia, espaçamentos, tiers e componentes de interface.

# ==============================================================================
# 🎨 1. PALETA GOLMIO (tema claro: papel creme e tinta preta)
# ==============================================================================
# Fonte: jogo/tools/tokens.ase (paleta oficial). Os tons marcados como "derivado" não estão no
# arquivo e saem das cores oficiais.

const COLOR_PAPER          := Color("#fcf6e6") # Papel Base: fundo das telas
const COLOR_PAPER_SURFACE  := Color("#f6eed8") # Papel Superfície: seções, cards, janelas
const COLOR_INK            := Color("#000000") # Tinta Preta: contornos, sombras duras, texto
const COLOR_DISABLED       := Color("#c0c0c0") # Cinza Desabilitado
const BORDER_WIDTH := 2                # Contorno de tinta dos componentes (px lógicos)
const SHADOW_OFFSET := Vector2(2, 3)   # Sombra dura deslocada (sem desfoque)

# Superfícies & Fundos
const COLOR_BG_APP       := COLOR_PAPER
const COLOR_BG_SURFACE   := COLOR_PAPER_SURFACE
const COLOR_BG_CARD      := COLOR_PAPER_SURFACE
const COLOR_BG_INPUT     := Color("#fffdf6") # derivado: campos e botões secundários (papel mais claro)
const COLOR_BG_HOVER     := Color("#ede2c4") # derivado: superfície um tom abaixo

# Bordas & Divisórias
const COLOR_BORDER_SUBTLE := Color("#ddd2b4") # derivado: divisores secundários
const COLOR_BORDER_BASE   := COLOR_INK
const COLOR_BORDER_STRONG := COLOR_INK

# Acentos & Identidade Visual
const COLOR_ACCENT_YELLOW    := Color("#fec12e") # Amarelo Golmio: ação principal, seleção
const COLOR_ACCENT_BLUE      := Color("#005d89") # Azul Golmio: navegação, informação, foco
const COLOR_ACCENT_PRIMARY   := COLOR_ACCENT_YELLOW
const COLOR_ACCENT_HOVER     := Color("#ffd162") # derivado: amarelo mais claro (hover)
const COLOR_ACCENT_CYAN      := COLOR_ACCENT_BLUE # legado: o "ciano" do tema escuro virou o azul
const COLOR_ACCENT_EMERALD   := Color("#258543") # Verde Sucesso: confirmar, equipado
const COLOR_ACCENT_GOLD      := COLOR_ACCENT_YELLOW # gols, títulos, cartão amarelo
const COLOR_ACCENT_RED       := Color("#e53c23") # Vermelho Alerta: remover, erro, cartão vermelho

# Tipografia & Fontes
# Duas famílias com papéis fixos (como nas pranchas):
#   - Display (Golmio Display, peso 800): títulos, etiquetas de seção, botão principal, abas,
#     placares, siglas e números grandes. Já é pesada: nunca recebe negrito sintético.
#   - Texto (Lexend, variável 100–900, OFL): rótulos, texto corrido, dicas, listas, campos e
#     botões secundários. Feita para leitura em tamanho pequeno.
# A Display só tem 177 glifos (faltam · • º ª $ ° < >); o que faltar sai da Lexend, nunca de uma
# fonte do sistema diferente em cada plataforma.
const FONT_DISPLAY_PATH := "res://assets/fonts/GolmioDisplay-Regular.ttf"
const FONT_TEXT_PATH    := "res://assets/fonts/Lexend-Variable.ttf"

# Pesos da fonte de texto (eixo wght).
const WEIGHT_REGULAR  := 400 # texto corrido
const WEIGHT_MEDIUM   := 500 # rótulos, botões secundários
const WEIGHT_SEMIBOLD := 600 # valores, destaques dentro do texto
const WEIGHT_BOLD     := 700

# Escala tipográfica (px lógicos; razão ~1,25 sobre a base 16). Nenhum texto abaixo de 12.
const TYPE_DISPLAY := 32 # placar, número de destaque
const TYPE_TITLE   := 24 # título de tela
const TYPE_H2      := 20 # etiqueta de seção, botão principal
const TYPE_BODY    := 16 # texto corrido, rótulos, botões
const TYPE_SMALL   := 14 # metadados, botões compactos
const TYPE_CAPTION := 12 # dicas, legendas, crachás (mínimo absoluto)


static var _display: Font = null
static var _text := {} # peso -> FontVariation


static func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path) as Font
	var ff := FontFile.new()
	if FileAccess.file_exists(path) and ff.load_dynamic_font(path) == OK:
		return ff
	return ThemeDB.fallback_font


## Fonte de texto (Lexend) no peso pedido.
static func text_font(weight: int = WEIGHT_REGULAR) -> Font:
	if _text.has(weight):
		return _text[weight]
	var fv := FontVariation.new()
	fv.base_font = _load_font(FONT_TEXT_PATH)
	# A chave tem de ser a tag numérica: com a string "wght" o Godot ignora o eixo.
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	_text[weight] = fv
	return fv


## Fonte display (Golmio Display), com a Lexend Bold cobrindo os glifos que faltam.
static func display_font() -> Font:
	if _display != null:
		return _display
	var base_f := _load_font(FONT_DISPLAY_PATH)
	if base_f is FontFile and (base_f as FontFile).fallbacks.is_empty():
		(base_f as FontFile).fallbacks = [text_font(WEIGHT_BOLD)]
	_display = base_f
	return _display


## Atalho legado: `font(true)` é a display; `font(false)` é a de texto.
static func font(display: bool = false) -> Font:
	return display_font() if display else text_font()


static func init_typography() -> void:
	var f := text_font()
	ThemeDB.fallback_font = f
	ThemeDB.fallback_font_size = TYPE_BODY
	var dt := ThemeDB.get_default_theme()
	if dt != null:
		dt.default_font = f
		dt.default_font_size = TYPE_BODY

const COLOR_TEXT_PRIMARY   := COLOR_INK          # Texto principal
const COLOR_TEXT_SECONDARY := Color("#5c5c5d")  # Texto Secundário
const COLOR_TEXT_MUTED     := Color("#6d6e6b")  # Texto Atenuado: dicas e placeholders

# ==============================================================================
# 🎴 2. CORES DOS TIPOS DE CARTA (Normal / Raro / Lendário / Mítico / Divino)
# ==============================================================================
# Ids internos (DNA "tier") seguem bronze..deus; nomes exibidos vêm de GameTerms.card_tier().

const COLOR_TIER_BRONZE   := Color("#cd7f32") # Normal
const COLOR_TIER_PRATA    := Color("#c0c0c0") # Raro
const COLOR_TIER_OURO     := Color("#ffd700") # Lendário
const COLOR_TIER_DIAMANTE := Color("#00e5ff") # Mítico
const COLOR_TIER_DEUS     := Color("#a855f7") # Divino

static func color_for_tier(tier: String) -> Color:
	match tier.to_lower():
		"bronze": return COLOR_TIER_BRONZE
		"prata": return COLOR_TIER_PRATA
		"ouro": return COLOR_TIER_OURO
		"diamante": return COLOR_TIER_DIAMANTE
		"deus": return COLOR_TIER_DEUS
		_: return COLOR_TEXT_MUTED

# ==============================================================================
# ⚽ 3. CORES POSICIONAIS (Futebol)
# ==============================================================================

# Legíveis como texto sobre o papel creme.
const COLOR_POS_GK  := Color("#a86400") # Goleiro (âmbar escuro; derivado do amarelo)
const COLOR_POS_DEF := COLOR_ACCENT_BLUE    # Defesa
const COLOR_POS_MID := COLOR_ACCENT_EMERALD # Meio-campo
const COLOR_POS_FWD := COLOR_ACCENT_RED     # Ataque

static func color_for_position(pos: String) -> Color:
	match pos.to_upper():
		"GK": return COLOR_POS_GK
		"DEF": return COLOR_POS_DEF
		"MID": return COLOR_POS_MID
		"FWD": return COLOR_POS_FWD
		_: return COLOR_TEXT_SECONDARY

# ==============================================================================
# 🏟️ 4. GRAMADO & PARTIDA 2D
# ==============================================================================

const COLOR_PITCH_GRASS_A := Color("#116832") # Faixa clara do gramado
const COLOR_PITCH_GRASS_B := Color("#0d5c2b") # Faixa escura do gramado
const COLOR_PITCH_LINE    := Color(1.0, 1.0, 1.0, 0.45) # Marcações em branco fosco
const COLOR_BALL          := Color("#ffffff") # Bola
const COLOR_BALL_OUTLINE  := Color("#0f172a") # Contorno da bola

# ==============================================================================
# 📐 5. GEOMETRIA, ESPAÇAMENTO & BORDAS
# ==============================================================================

const RADIUS_SM := 4.0
const RADIUS_MD := 8.0
const RADIUS_LG := 12.0
const RADIUS_XL := 16.0
const RADIUS_FULL := 999.0 # Pílulas e botões circulares

const SPACING_2XS := 2
const SPACING_XS  := 4
const SPACING_SM  := 8
const SPACING_MD  := 12
const SPACING_LG  := 16
const SPACING_XL  := 24
const SPACING_2XL := 32

# ==============================================================================
# 🛠️ 6. GERADORES DE ESTILOS (StyleBoxFlat para UI)
# ==============================================================================

# Usam as molduras pintadas (UiFrames, assets/ui/) quando existem; sem elas, a mesma linguagem
# (contorno de tinta e sombra dura) desenhada por código. Por isso o retorno é StyleBox.

static func _ink_shadow(s: StyleBoxFlat, offset: Vector2 = SHADOW_OFFSET) -> void:
	s.shadow_color = COLOR_INK
	s.shadow_size = 1
	s.shadow_offset = offset


static func style_card(radius: float = RADIUS_LG, border_color: Color = COLOR_BORDER_BASE) -> StyleBox:
	var art := UiFrames.frame("ui_painel", COLOR_BG_CARD)
	if art and border_color == COLOR_BORDER_BASE:
		return art
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_BG_CARD
	s.set_border_width_all(BORDER_WIDTH)
	s.border_color = border_color
	_ink_shadow(s)
	s.set_corner_radius_all(int(radius))
	s.content_margin_left = SPACING_MD
	s.content_margin_right = SPACING_MD
	s.content_margin_top = SPACING_MD
	s.content_margin_bottom = SPACING_MD
	return s

static func button_color(is_primary: bool, is_hover: bool) -> Color:
	if is_primary:
		return COLOR_ACCENT_HOVER if is_hover else COLOR_ACCENT_PRIMARY
	return COLOR_BG_HOVER if is_hover else COLOR_BG_INPUT


## `is_pressed`: estado apertado (corpo deslocado, sombra menor).
static func style_button(is_primary: bool = false, is_hover: bool = false, is_pressed: bool = false) -> StyleBox:
	var art := UiFrames.frame("ui_botao_pressionado" if is_pressed else "ui_botao_normal", button_color(is_primary, is_hover))
	if art:
		return art
	var s := StyleBoxFlat.new()
	if is_primary:
		s.bg_color = COLOR_ACCENT_HOVER if is_hover else COLOR_ACCENT_PRIMARY
	else:
		s.bg_color = COLOR_BG_HOVER if is_hover else COLOR_BG_INPUT
	s.border_color = COLOR_INK
	s.set_border_width_all(BORDER_WIDTH)
	_ink_shadow(s, Vector2(1, 1) if is_pressed else SHADOW_OFFSET)
	s.set_corner_radius_all(int(RADIUS_MD))
	s.content_margin_left = SPACING_LG
	s.content_margin_right = SPACING_LG
	s.content_margin_top = SPACING_SM
	s.content_margin_bottom = SPACING_SM
	return s

static func style_badge(fill: Color, radius: float = RADIUS_SM) -> StyleBox:
	var art := UiFrames.frame("ui_chip", fill.lerp(Color.WHITE, 0.7))
	if art:
		return art
	var s := StyleBoxFlat.new()
	s.bg_color = Color(fill.r, fill.g, fill.b, 0.22)
	s.set_border_width_all(BORDER_WIDTH)
	s.border_color = fill
	s.set_corner_radius_all(int(radius))
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s


## Anel de foco (teclado/controle), desenhado por cima do componente.
static func style_focus() -> StyleBox:
	var art := UiFrames.frame("ui_botao_foco")
	if art:
		return art
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.set_border_width_all(BORDER_WIDTH + 1)
	f.border_color = COLOR_ACCENT_BLUE
	f.set_corner_radius_all(int(RADIUS_MD) + 2)
	f.set_expand_margin_all(3)
	return f


## Janela modal / painel de configurações.
static func style_window() -> StyleBox:
	var art := UiFrames.frame("ui_janela", COLOR_BG_CARD)
	if art:
		return art
	var s := style_card(RADIUS_XL) as StyleBoxFlat
	s.shadow_offset = SHADOW_OFFSET * 2.0
	s.content_margin_left = SPACING_XL
	s.content_margin_right = SPACING_XL
	s.content_margin_top = SPACING_LG
	s.content_margin_bottom = SPACING_LG
	return s


## Aba / segmento selecionado.
static func style_tab_selected() -> StyleBox:
	var art := UiFrames.frame("ui_aba", COLOR_ACCENT_PRIMARY)
	if art:
		return art
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_ACCENT_PRIMARY
	s.border_color = COLOR_INK
	s.set_border_width_all(BORDER_WIDTH)
	s.set_corner_radius_all(int(RADIUS_MD))
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 8
	return s


## Trilho e preenchimento de barras (progresso, fôlego, volume).
static func style_bar_track() -> StyleBox:
	var art := UiFrames.frame("ui_barra_trilho")
	if art:
		return art
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_INK
	s.set_corner_radius_all(int(RADIUS_FULL))
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


static func style_bar_fill(color: Color = COLOR_ACCENT_PRIMARY) -> StyleBox:
	var art := UiFrames.frame("ui_barra_preenchimento", color)
	if art:
		return art
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = COLOR_INK
	s.set_border_width_all(BORDER_WIDTH)
	s.set_corner_radius_all(int(RADIUS_FULL))
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


## Tema base Golmio para uma tela inteira: textos em tinta, botões, listas suspensas, campos,
## caixas de seleção, rolagem e dicas no estilo das pranchas. Aplique na raiz (`theme = ...`);
## overrides locais continuam valendo. `compact`: botões com respiro menor (telas densas).
static func base_theme(compact := false) -> Theme:
	var t := Theme.new()
	t.default_font = text_font()
	t.default_font_size = TYPE_BODY
	# Botões e controles: Lexend Medium (o botão principal troca para a display no UiKit).
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton", "MenuButton", "LinkButton"]:
		t.set_font("font", cls, text_font(WEIGHT_MEDIUM))
	t.set_font_size("font_size", "TooltipLabel", TYPE_SMALL)
	var ink := COLOR_TEXT_PRIMARY
	for cls in ["Label", "Button", "OptionButton", "CheckBox", "CheckButton", "MenuButton", "LinkButton", "PopupMenu", "TooltipLabel"]:
		t.set_color("font_color", cls, ink)
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton", "MenuButton"]:
		for c in ["font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(c, cls, ink)
		t.set_color("font_disabled_color", cls, COLOR_TEXT_MUTED)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, style_button(false, false))
		t.set_stylebox("hover", cls, style_button(false, true))
		t.set_stylebox("pressed", cls, style_button(true, false, true))
		t.set_stylebox("hover_pressed", cls, style_button(true, true, true))
		t.set_stylebox("disabled", cls, style_button(false, false))
		t.set_stylebox("focus", cls, style_focus())
		if compact:
			for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				compact_margins(t.get_stylebox(st, cls))
	var empty := StyleBoxEmpty.new()
	for cls in ["CheckBox", "CheckButton"]:
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(st, cls, empty)
		t.set_stylebox("focus", cls, style_focus())
	var chk_on := UiFrames.piece("ui_check_marcado")
	var chk_off := UiFrames.piece("ui_check_vazio")
	if chk_on and chk_off:
		t.set_icon("checked", "CheckBox", chk_on)
		t.set_icon("unchecked", "CheckBox", chk_off)
	var rad_on := UiFrames.piece("ui_radio_marcado")
	var rad_off := UiFrames.piece("ui_radio_vazio")
	if rad_on and rad_off:
		t.set_icon("radio_checked", "CheckBox", rad_on)
		t.set_icon("radio_unchecked", "CheckBox", rad_off)
	var sw_on := UiFrames.piece("ui_interruptor_ligado")
	var sw_off := UiFrames.piece("ui_interruptor_desligado")
	if sw_on and sw_off:
		t.set_icon("checked", "CheckButton", sw_on)
		t.set_icon("unchecked", "CheckButton", sw_off)

	var field := UiFrames.frame("ui_campo", COLOR_BG_INPUT)
	if field == null:
		var f := StyleBoxFlat.new()
		f.bg_color = COLOR_BG_INPUT
		f.border_color = COLOR_INK
		f.set_border_width_all(BORDER_WIDTH)
		f.set_corner_radius_all(int(RADIUS_MD))
		f.set_content_margin_all(SPACING_SM)
		field = f
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", UiFrames.frame("ui_campo_foco") if UiFrames.has("ui_campo_foco") else style_focus())
	t.set_color("font_color", "LineEdit", ink)
	t.set_color("font_placeholder_color", "LineEdit", COLOR_TEXT_MUTED)
	t.set_color("caret_color", "LineEdit", ink)
	t.set_color("selection_color", "LineEdit", Color(COLOR_ACCENT_YELLOW, 0.5))

	var popup := StyleBoxFlat.new()
	popup.bg_color = COLOR_BG_CARD
	popup.border_color = COLOR_INK
	popup.set_border_width_all(BORDER_WIDTH)
	popup.set_corner_radius_all(int(RADIUS_MD))
	popup.set_content_margin_all(6)
	t.set_stylebox("panel", "PopupMenu", popup)
	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = Color(COLOR_ACCENT_YELLOW, 0.55)
	popup_hover.set_corner_radius_all(int(RADIUS_SM))
	t.set_stylebox("hover", "PopupMenu", popup_hover)
	t.set_color("font_hover_color", "PopupMenu", ink)

	var tip := UiFrames.frame("ui_dica")
	if tip == null:
		var tf := StyleBoxFlat.new()
		tf.bg_color = COLOR_INK
		tf.set_corner_radius_all(int(RADIUS_MD))
		tf.set_content_margin_all(SPACING_SM)
		tip = tf
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", COLOR_PAPER)

	for cls in ["VScrollBar", "HScrollBar"]:
		var sc := StyleBoxFlat.new()
		sc.bg_color = Color(COLOR_INK, 0.08)
		sc.set_corner_radius_all(4)
		var gr := StyleBoxFlat.new()
		gr.bg_color = Color(COLOR_INK, 0.45)
		gr.set_corner_radius_all(4)
		var gr_h := gr.duplicate() as StyleBoxFlat
		gr_h.bg_color = Color(COLOR_INK, 0.7)
		t.set_stylebox("scroll", cls, sc)
		t.set_stylebox("grabber", cls, gr)
		t.set_stylebox("grabber_highlight", cls, gr_h)
		t.set_stylebox("grabber_pressed", cls, gr_h)

	var sep := StyleBoxLine.new()
	sep.color = COLOR_BORDER_SUBTLE
	sep.thickness = 2
	t.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = COLOR_BORDER_SUBTLE
	vsep.thickness = 2
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	return t


## Respiro de botão compacto (telas densas como a Tática).
static func compact_margins(sb: StyleBox, h := 8.0, v := 4.0) -> StyleBox:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v + 1.0
	return sb
