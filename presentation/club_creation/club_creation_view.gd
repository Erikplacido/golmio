class_name ClubCreationView
extends Control
## Tela de Criação e Personalização do Clube (Godot 4):
##   - Define Nome e Sigla do Clube;
##   - Personaliza Uniforme Principal (Home Kit) e Uniforme Reserva (Away Kit);
##   - 8 padrões de estampa, golas modulares PNG, punhos, cores e escudo;
##   - Validação de contraste em tempo real entre Uniforme Principal e Reserva;
##   - Pré-visualização do uniforme montado em StickerCard e PortraitRenderer;
##   - Compatível com a estrutura de dados `club.ext["club_identity"]`.

signal club_saved(club_data: Dictionary)
signal back_pressed

const PALETTE_PRESETS := [
	"#c8102e", "#e11d48", "#f97316", "#facc15", "#16a34a", "#065f46",
	"#0ea5e9", "#1d4ed8", "#1e3a8a", "#7c3aed", "#7f1d1d", "#92400e",
	"#94a3b8", "#ffffff", "#111111", "#1d1d1b",
]

## Padrões e brasões (grátis e desbloqueáveis): Cosmetics.PATTERNS / Cosmetics.CRESTS.
const COLOR_NAMES := ["Principal", "Secundária", "Detalhe"]

const COLLAR_OPTIONS := [
	{"id": "Caricatura retrô com gola redonda.png", "label": "Redonda"},
	{"id": "Caricatura vintage com gola de futebol.png", "label": "Gola V"},
	{"id": "Retrato esportivo com gola polo retrô.png", "label": "Polo Retrô"},
	{"id": "Retrato retrô com gola mandarim azul-marinho.png", "label": "Mandarim"},
	{"id": "nenhuma", "label": "Sem Gola"},
]

## Cores de UI da tela (tema Golmio: DesignTokens)
const BG_CARD := DesignTokens.COLOR_BG_SURFACE
const BG_INPUT := DesignTokens.COLOR_BG_INPUT
const BORDER := DesignTokens.COLOR_INK
const ACCENT := DesignTokens.COLOR_ACCENT_PRIMARY
const ACCENT_CYAN := DesignTokens.COLOR_ACCENT_BLUE
const TEXT_MAIN := DesignTokens.COLOR_TEXT_PRIMARY
const TEXT_MUTED := DesignTokens.COLOR_TEXT_SECONDARY
const COLOR_OK := DesignTokens.COLOR_ACCENT_EMERALD
const COLOR_WARN := Color("#a86400")   # âmbar escuro (derivado do amarelo): legível no papel

## Dados de edição
var club_name: String = "Meu Clube FC"
var club_sigla: String = "MCF"
var active_tab_kit: String = "home" # "home" | "away"
var home_kit: Dictionary = {}
var away_kit: Dictionary = {}
var sample_athletes: Array = []
var current_sample_idx: int = 0

## Nós de interface
var _name_input: LineEdit
var _sigla_input: LineEdit
var _pattern_buttons: Dictionary = {}
var _collar_buttons: Dictionary = {}
var _color_swatches: Array[Button] = []   # as 3 cores do kit; tocar abre a paleta
var _color_popup: PopupPanel
var _color_picker: ColorPicker
var _pattern_thumbs: Dictionary = {}       # id -> KitThumb
var _collar_thumbs: Dictionary = {}        # id -> KitThumb
var _crest_buttons: Dictionary = {}        # id -> Button
var _crest_views: Array[ClubCrest] = []
var _crest_id: String = Cosmetics.DEFAULT_CREST
## Clube já criado (editar uniforme depois): libera os itens que ele ganhou. null na criação.
var owner_club: Club
var _choice_button_groups: Dictionary = {} # field_name -> Array[Button]
var _contrast_card_panel: PanelContainer
var _contrast_label: Label
var _preview_card_home: StickerCard
var _preview_card_away: StickerCard
var _tab_btn_home: Button
var _tab_btn_away: Button
var _slider_count: HSlider
var _slider_width: HSlider
var _label_count_val: Label
var _label_width_val: Label
var _row_count: Control
var _row_width: Control
var _check_cuff: CheckBox
var _check_cuff_trim: CheckBox
var _cuff_controls_box: Control
var _active_color_idx: int = 0
var _btn_switch_athlete: Button
var _error_label: Label

## Layout de página: expandido (editor em 2 colunas) ou compacto (celular: pré-visualização no
## topo, uma etapa por vez, ações no rodapé). Mesmo estado e mesma lógica nos dois.
const COMPACT_MAX := 760.0
const STEPS := [
	["clube", "Clube"], ["cores", "Cores"], ["camisa", "Camisa"], ["gola", "Gola"], ["mangas", "Mangas"],
]
## Seções (painéis) de cada etapa do compacto; "kit" (qual uniforme) aparece nas etapas de uniforme.
const STEP_SECTIONS := {
	"clube": ["identity", "crest"], "cores": ["kit", "colors"], "camisa": ["kit", "pattern"],
	"gola": ["kit", "collar"], "mangas": ["kit", "cuffs"],
}
var compact := false
var _step := "clube"
var _layout_ready := false
var _sections := {}               # id -> PanelContainer
var _header_title: Label
var _header_box: HBoxContainer
var _btn_random: Button
var _btn_save: Button
var _body_expanded: Control
var _scroll_left: ScrollContainer
var _left_vbox: VBoxContainer
var _right_vbox: VBoxContainer
var _preview_header: Control
var _cards_hbox: HBoxContainer
var _card_label_home: Label
var _card_label_away: Label
var _body_compact: VBoxContainer
var _compact_preview: VBoxContainer
var _compact_steps_slot: Control
var _compact_scroll: ScrollContainer
var _compact_bottom: HBoxContainer
var _pat_grid: GridContainer
var _id_rows: Array[BoxContainer] = []   # Nome / Sigla: rótulo ao lado (expandido) ou acima (compacto)
var _id_labels: Array[Label] = []
var _contrast_title: Label


func _init() -> void:
	home_kit = UniformMaps.normalize_kit(UniformMaps.KIT_DEFAULT.duplicate(true))
	home_kit["colors"] = ["#c8102e", "#ffffff", "#1d1d1b"]
	home_kit["sigla"] = "MCF"
	
	away_kit = UniformMaps.normalize_kit(UniformMaps.KIT_DEFAULT.duplicate(true))
	away_kit["pattern"] = "lisa"
	away_kit["colors"] = ["#ffffff", "#c8102e", "#1d1d1b"]
	away_kit["collar_color"] = 1
	away_kit["collar_trim_color"] = 0
	away_kit["sigla"] = "MCF"


func _ready() -> void:
	anchors_preset = PRESET_FULL_RECT
	_load_sample_athletes()
	_build_ui()
	_build_compact_shell()
	_layout_ready = true
	resized.connect(_apply_layout)
	_apply_layout()
	_update_ui_state()


func get_active_kit() -> Dictionary:
	return home_kit if active_tab_kit == "home" else away_kit


func set_active_kit(k: Dictionary) -> void:
	if active_tab_kit == "home":
		home_kit = k
	else:
		away_kit = k


## Quatro atletas de vitrine (um por setor) do gerador oficial: o retrato veste o uniforme editado.
func _load_sample_athletes() -> void:
	sample_athletes.clear()
	sample_athletes.append_array(PreviewAthletes.generate(["FWD", "MID", "DEF", "GK"], ["ouro", "prata", "diamante", "bronze"]))


func _build_ui() -> void:
	# Fundo de papel e tema Golmio
	theme = DesignTokens.base_theme(true)
	add_child(UiFrames.paper_background())

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 0)
	add_child(main_vbox)

	# 1. Barra Superior (Header)
	var header := PanelContainer.new()
	header.custom_minimum_size = Vector2(0, 52)
	var h_style := StyleBoxFlat.new()
	h_style.bg_color = DesignTokens.COLOR_BG_SURFACE
	h_style.border_width_bottom = 1
	h_style.border_color = BORDER
	h_style.content_margin_left = 20
	h_style.content_margin_right = 20
	header.add_theme_stylebox_override("panel", h_style)
	main_vbox.add_child(header)

	var h_hbox := HBoxContainer.new()
	h_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(h_hbox)
	_header_box = h_hbox

	var title_lbl := Label.new()
	h_hbox.add_child(GameIcons.rect("clube", 26))
	_header_title = title_lbl
	title_lbl.text = "CRIE SEU CLUBE"
	title_lbl.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
	title_lbl.add_theme_font_override("font", DesignTokens.display_font())
	title_lbl.add_theme_color_override("font_color", TEXT_MAIN)
	h_hbox.add_child(title_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	h_hbox.add_child(spacer)

	_error_label = Label.new()
	_error_label.visible = false
	_error_label.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	_error_label.add_theme_color_override("font_color", ACCENT)
	h_hbox.add_child(_error_label)

	var btn_random := Button.new()
	btn_random.text = "Sortear visual"
	GameIcons.apply(btn_random, "substituicao", 24)
	UiKit.icon_only(btn_random, 24)
	btn_random.custom_minimum_size = Vector2(UiKit.TOUCH, 34)
	btn_random.pressed.connect(_randomize_club_style)
	_style_button(btn_random, false)
	h_hbox.add_child(btn_random)
	_btn_random = btn_random

	var btn_save := Button.new()
	btn_save.text = "Salvar"
	GameIcons.apply(btn_save, "confirmar", 20)
	btn_save.custom_minimum_size = Vector2(140, 34)
	btn_save.pressed.connect(_on_save_pressed)
	_style_button(btn_save, true)
	h_hbox.add_child(btn_save)
	_btn_save = btn_save

	var btn_settings := GearButton.new()
	btn_settings.custom_minimum_size = Vector2(40, 34)
	_style_button(btn_settings, false)
	h_hbox.add_child(btn_settings)
	add_to_group("settings_button_host")

	# 2. Área Central Dividida (HBox com Margens)
	var body_margin := MarginContainer.new()
	body_margin.size_flags_horizontal = SIZE_EXPAND_FILL
	body_margin.size_flags_vertical = SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 8)
	body_margin.add_theme_constant_override("margin_right", 8)
	body_margin.add_theme_constant_override("margin_top", 12)
	body_margin.add_theme_constant_override("margin_bottom", 12)
	main_vbox.add_child(body_margin)
	_body_expanded = body_margin

	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	content_hbox.size_flags_vertical = SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 8)
	body_margin.add_child(content_hbox)

	# =========================================================================
	# LADO ESQUERDO: CONTROLES COM SCROLL
	# =========================================================================
	var scroll_left := ScrollContainer.new()
	scroll_left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_left.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll_left.size_flags_vertical = SIZE_EXPAND_FILL
	scroll_left.size_flags_stretch_ratio = 1.15
	content_hbox.add_child(scroll_left)
	_scroll_left = scroll_left

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 12)
	scroll_left.add_child(left_vbox)
	_left_vbox = left_vbox

	# Card 1: Identidade Básica
	var card_id_box := _create_card("Clube", left_vbox, "identity")

	var row_name := BoxContainer.new()
	row_name.alignment = BoxContainer.ALIGNMENT_CENTER
	_id_rows.append(row_name)
	var lbl_name := Label.new()
	lbl_name.text = "Nome"
	lbl_name.custom_minimum_size = Vector2(60, 0)
	_id_labels.append(lbl_name)
	lbl_name.add_theme_color_override("font_color", TEXT_MUTED)
	_name_input = LineEdit.new()
	_name_input.text = club_name
	_name_input.placeholder_text = "Ex: Rubro Várzea FC"
	_name_input.max_length = 30
	_name_input.size_flags_horizontal = SIZE_EXPAND_FILL
	_name_input.text_changed.connect(func(t: String):
		club_name = t
		_update_ui_state()
	)
	row_name.add_child(lbl_name)
	row_name.add_child(_name_input)
	card_id_box.add_child(row_name)

	var row_sigla := BoxContainer.new()
	row_sigla.alignment = BoxContainer.ALIGNMENT_CENTER
	_id_rows.append(row_sigla)
	var lbl_sigla := Label.new()
	lbl_sigla.text = "Sigla"
	lbl_sigla.tooltip_text = "2 a 5 letras"
	lbl_sigla.mouse_filter = Control.MOUSE_FILTER_PASS
	lbl_sigla.custom_minimum_size = Vector2(60, 0)
	_id_labels.append(lbl_sigla)
	lbl_sigla.add_theme_color_override("font_color", TEXT_MUTED)
	_sigla_input = LineEdit.new()
	_sigla_input.text = club_sigla
	_sigla_input.placeholder_text = "RVZ (2 a 5 letras)"
	_sigla_input.max_length = 5
	_sigla_input.size_flags_horizontal = SIZE_EXPAND_FILL
	_sigla_input.text_changed.connect(func(t: String):
		club_sigla = t.to_upper()
		_sigla_input.text = club_sigla
		home_kit["sigla"] = club_sigla
		away_kit["sigla"] = club_sigla
		_update_ui_state()
	)
	row_sigla.add_child(lbl_sigla)
	row_sigla.add_child(_sigla_input)
	card_id_box.add_child(row_sigla)

	# Brasão: forma + desenho; os bloqueados chegam por recompensa ou loja.
	var card_crest_box := _create_card("Brasão", left_vbox, "crest")
	var crest_grid := GridContainer.new()
	crest_grid.columns = 5
	crest_grid.add_theme_constant_override("h_separation", 6)
	crest_grid.add_theme_constant_override("v_separation", 6)
	card_crest_box.add_child(crest_grid)
	for c_id in Cosmetics.CRESTS:
		var cb := Button.new()
		cb.custom_minimum_size = Vector2(0, 64)
		cb.size_flags_horizontal = SIZE_EXPAND_FILL
		var crest := ClubCrest.new(40)
		crest.crest_id = c_id
		crest.set_anchors_and_offsets_preset(PRESET_CENTER)
		crest.position = Vector2.ZERO
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(crest)
		cb.add_child(center)
		if not Cosmetics.is_unlocked(c_id, owner_club):
			var lock := GameIcons.rect("bloqueado", 20)
			lock.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
			lock.position += Vector2(-24, 4)
			cb.add_child(lock)
		_crest_views.append(crest)
		cb.pressed.connect(func():
			if Cosmetics.is_unlocked(c_id, owner_club):
				_crest_id = c_id
				_update_ui_state()
		)
		_crest_buttons[c_id] = cb
		crest_grid.add_child(cb)

	# Card 2: Alternância de Kits (Home / Away)
	var card_tab_box := _create_card("Uniforme", left_vbox, "kit")
	var tab_hbox := HBoxContainer.new()
	tab_hbox.add_theme_constant_override("separation", 10)
	card_tab_box.add_child(tab_hbox)

	_tab_btn_home = Button.new()
	_tab_btn_home.text = "Principal"
	GameIcons.apply(_tab_btn_home, "uniforme", 22)
	_tab_btn_home.custom_minimum_size = Vector2(0, 36)
	_tab_btn_home.size_flags_horizontal = SIZE_EXPAND_FILL
	_tab_btn_home.pressed.connect(func(): _switch_kit_tab("home"))
	tab_hbox.add_child(_tab_btn_home)

	_tab_btn_away = Button.new()
	_tab_btn_away.text = "Reserva"
	GameIcons.apply(_tab_btn_away, "clube", 20)
	_tab_btn_away.custom_minimum_size = Vector2(0, 36)
	_tab_btn_away.size_flags_horizontal = SIZE_EXPAND_FILL
	_tab_btn_away.pressed.connect(func(): _switch_kit_tab("away"))
	tab_hbox.add_child(_tab_btn_away)

	# Cores: a própria amostra é o botão (com o nome dentro); tocar abre a paleta daquela cor.
	var card_colors_box := _create_card("Cores", left_vbox, "colors")
	var swatch_row := HBoxContainer.new()
	swatch_row.add_theme_constant_override("separation", 8)
	card_colors_box.add_child(swatch_row)
	_color_swatches.clear()
	for i in range(3):
		var sw := Button.new()
		sw.text = COLOR_NAMES[i]
		sw.custom_minimum_size = Vector2(0, UiKit.TOUCH)
		sw.size_flags_horizontal = SIZE_EXPAND_FILL
		sw.clip_text = true
		sw.pressed.connect(func(): _open_color_popup(i, sw))
		_color_swatches.append(sw)
		swatch_row.add_child(sw)
	_build_color_popup()

	# Padrão: miniaturas da camisa com as cores do kit (o nome fica na dica).
	var card_pat_box := _create_card("Padrão", left_vbox, "pattern")
	var pat_grid := GridContainer.new()
	_pat_grid = pat_grid
	pat_grid.columns = 6
	pat_grid.add_theme_constant_override("h_separation", 6)
	pat_grid.add_theme_constant_override("v_separation", 6)
	card_pat_box.add_child(pat_grid)

	for p_id in Cosmetics.PATTERNS:
		var btn_p := Button.new()
		btn_p.tooltip_text = tr(Cosmetics.PATTERNS[p_id].label)
		btn_p.custom_minimum_size = Vector2(0, 64)
		btn_p.size_flags_horizontal = SIZE_EXPAND_FILL
		btn_p.add_child(_centered(_thumb_for(p_id, _pattern_thumbs, false)))
		btn_p.pressed.connect(func():
			if not Cosmetics.is_unlocked(p_id, owner_club):
				return
			var k := get_active_kit()
			k["pattern"] = p_id
			set_active_kit(k)
			_update_ui_state()
		)
		_pattern_buttons[p_id] = btn_p
		pat_grid.add_child(btn_p)

	_row_count = HBoxContainer.new()
	_row_count.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl_cnt := Label.new()
	lbl_cnt.text = "Repetições"
	lbl_cnt.custom_minimum_size = Vector2(96, 0)
	lbl_cnt.add_theme_color_override("font_color", TEXT_MUTED)
	_slider_count = HSlider.new()
	_slider_count.min_value = 1
	_slider_count.max_value = 7
	_slider_count.step = 1
	_slider_count.size_flags_horizontal = SIZE_EXPAND_FILL
	_label_count_val = Label.new()
	_label_count_val.custom_minimum_size = Vector2(30, 0)
	_slider_count.value_changed.connect(func(v: float):
		var k := get_active_kit()
		k["count"] = int(v)
		set_active_kit(k)
		_label_count_val.text = str(int(v))
		_refresh_thumbs()
		_update_preview()
	)
	_row_count.add_child(lbl_cnt)
	_row_count.add_child(_slider_count)
	_row_count.add_child(_label_count_val)
	card_pat_box.add_child(_row_count)

	_row_width = HBoxContainer.new()
	_row_width.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl_w := Label.new()
	lbl_w.text = "Largura"
	lbl_w.custom_minimum_size = Vector2(96, 0)
	lbl_w.add_theme_color_override("font_color", TEXT_MUTED)
	_slider_width = HSlider.new()
	_slider_width.min_value = 0.06
	_slider_width.max_value = 0.45
	_slider_width.step = 0.01
	_slider_width.size_flags_horizontal = SIZE_EXPAND_FILL
	_label_width_val = Label.new()
	_label_width_val.custom_minimum_size = Vector2(36, 0)
	_slider_width.value_changed.connect(func(v: float):
		var k := get_active_kit()
		k["width"] = v
		set_active_kit(k)
		_label_width_val.text = "%d%%" % int(v * 100)
		_refresh_thumbs()
		_update_preview()
	)
	_row_width.add_child(lbl_w)
	_row_width.add_child(_slider_width)
	_row_width.add_child(_label_width_val)
	card_pat_box.add_child(_row_width)

	# Gola: miniaturas com a gola desenhada (o nome fica na dica).
	var card_collar_box := _create_card("Gola", left_vbox, "collar")
	var collar_grid := GridContainer.new()
	collar_grid.columns = 5
	collar_grid.add_theme_constant_override("h_separation", 6)
	collar_grid.add_theme_constant_override("v_separation", 6)
	card_collar_box.add_child(collar_grid)

	for opt in COLLAR_OPTIONS:
		var btn_col := Button.new()
		btn_col.tooltip_text = opt["label"]
		btn_col.custom_minimum_size = Vector2(0, 64)
		btn_col.size_flags_horizontal = SIZE_EXPAND_FILL
		btn_col.add_child(_centered(_thumb_for(opt["id"], _collar_thumbs, true)))
		btn_col.pressed.connect(func():
			var k := get_active_kit()
			k["collar"] = opt["id"]
			set_active_kit(k)
			_update_ui_state()
		)
		_collar_buttons[opt["id"]] = btn_col
		collar_grid.add_child(btn_col)

	var row_col_color := _create_color_index_row("Gola", "collar_color")
	card_collar_box.add_child(row_col_color)

	var row_col_trim := _create_color_index_row("Friso", "collar_trim_color")
	card_collar_box.add_child(row_col_trim)

	# Card 6: Mangas e Punhos
	var card_cuff_box := _create_card("Mangas", left_vbox, "cuffs")

	var row_sleeve_color := _create_color_index_row("Mangas", "sleeve_color")
	card_cuff_box.add_child(row_sleeve_color)

	_check_cuff = CheckBox.new()
	_check_cuff.text = "Punho"
	_check_cuff.toggled.connect(func(v: bool):
		var k := get_active_kit()
		k["cuff"] = v
		set_active_kit(k)
		_update_ui_state()
	)
	card_cuff_box.add_child(_check_cuff)

	_cuff_controls_box = VBoxContainer.new()
	_cuff_controls_box.add_theme_constant_override("separation", 6)
	card_cuff_box.add_child(_cuff_controls_box)

	var row_cuff_color := _create_color_index_row("Punho", "cuff_color")
	_cuff_controls_box.add_child(row_cuff_color)

	_check_cuff_trim = CheckBox.new()
	_check_cuff_trim.text = "Friso no punho"
	_check_cuff_trim.toggled.connect(func(v: bool):
		var k := get_active_kit()
		k["cuff_trim"] = v
		set_active_kit(k)
		_update_ui_state()
	)
	_cuff_controls_box.add_child(_check_cuff_trim)

	var row_cuff_trim_color := _create_color_index_row("Friso", "cuff_trim_color")
	_cuff_controls_box.add_child(row_cuff_trim_color)

	# Card 7: Validação de Contraste
	_contrast_card_panel = PanelContainer.new()
	var c_style := StyleBoxFlat.new()
	c_style.bg_color = BG_CARD
	c_style.border_width_left = 1
	c_style.border_width_top = 1
	c_style.border_width_right = 1
	c_style.border_width_bottom = 1
	c_style.border_color = BORDER
	c_style.corner_radius_top_left = 8
	c_style.corner_radius_top_right = 8
	c_style.corner_radius_bottom_left = 8
	c_style.corner_radius_bottom_right = 8
	c_style.content_margin_left = 14
	c_style.content_margin_right = 14
	c_style.content_margin_top = 6
	c_style.content_margin_bottom = 6
	_contrast_card_panel.add_theme_stylebox_override("panel", c_style)
	left_vbox.add_child(_contrast_card_panel)

	var cont_vbox := VBoxContainer.new()
	cont_vbox.add_theme_constant_override("separation", 6)
	_contrast_card_panel.add_child(cont_vbox)

	var cont_title := Label.new()
	cont_title.text = "CONTRASTE"
	cont_title.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	cont_title.add_theme_font_override("font", DesignTokens.display_font())
	cont_title.add_theme_color_override("font_color", ACCENT_CYAN)
	cont_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cont_title.custom_minimum_size.x = 120
	cont_vbox.add_child(cont_title)
	_contrast_title = cont_title
	cont_title.visible = false   # a frase já diz o que é; o contorno colorido dá o nível

	_contrast_label = Label.new()
	_contrast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_contrast_label.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	cont_vbox.add_child(_contrast_label)

	# =========================================================================
	# LADO DIREITO: ESTÚDIO DE PRÉ-VISUALIZAÇÃO (PREVIEW STUDIO)
	# =========================================================================
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.95
	var right_style := StyleBoxFlat.new()
	right_style.bg_color = DesignTokens.COLOR_BG_SURFACE
	right_style.border_width_left = 1
	right_style.border_width_top = 1
	right_style.border_width_right = 1
	right_style.border_width_bottom = 1
	right_style.border_color = BORDER
	right_style.corner_radius_top_left = 10
	right_style.corner_radius_top_right = 10
	right_style.corner_radius_bottom_left = 10
	right_style.corner_radius_bottom_right = 10
	right_style.content_margin_left = 16
	right_style.content_margin_right = 16
	right_style.content_margin_top = 16
	right_style.content_margin_bottom = 16
	right_panel.add_theme_stylebox_override("panel", right_style)
	content_hbox.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 14)
	right_panel.add_child(right_vbox)
	_right_vbox = right_vbox

	var preview_header_box := VBoxContainer.new()
	preview_header_box.add_theme_constant_override("separation", 2)
	right_vbox.add_child(preview_header_box)
	_preview_header = preview_header_box

	var preview_title := Label.new()
	preview_title.text = "PRÉVIA"
	preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_title.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	preview_title.add_theme_font_override("font", DesignTokens.display_font())
	preview_title.add_theme_color_override("font_color", ACCENT_CYAN)
	preview_header_box.add_child(preview_title)


	# Container das cartas lado a lado
	var cards_hbox := HBoxContainer.new()
	cards_hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	cards_hbox.size_flags_vertical = SIZE_EXPAND_FILL
	cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_hbox.add_theme_constant_override("separation", 20)
	right_vbox.add_child(cards_hbox)
	_cards_hbox = cards_hbox

	# Card Home
	var home_card_box := VBoxContainer.new()
	home_card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	home_card_box.add_theme_constant_override("separation", 8)
	var lbl_h := Label.new()
	lbl_h.text = "PRINCIPAL"
	lbl_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_h.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	lbl_h.add_theme_font_override("font", DesignTokens.display_font())
	lbl_h.add_theme_color_override("font_color", TEXT_MAIN)
	UiKit.wrap(lbl_h)   # 360 dp: quebra em duas linhas sobre a carta em vez de alargar a coluna
	home_card_box.add_child(lbl_h)
	_card_label_home = lbl_h

	_preview_card_home = StickerCard.new()
	_preview_card_home.custom_minimum_size = Vector2(190, 275)
	_preview_card_home.size_flags_horizontal = SIZE_SHRINK_CENTER
	_preview_card_home.pressed.connect(func(): _switch_kit_tab("home"))
	home_card_box.add_child(_preview_card_home)
	cards_hbox.add_child(home_card_box)

	# Card Away
	var away_card_box := VBoxContainer.new()
	away_card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	away_card_box.add_theme_constant_override("separation", 8)
	var lbl_a := Label.new()
	lbl_a.text = "RESERVA"
	lbl_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_a.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	lbl_a.add_theme_font_override("font", DesignTokens.display_font())
	lbl_a.add_theme_color_override("font_color", TEXT_MAIN)
	UiKit.wrap(lbl_a)
	away_card_box.add_child(lbl_a)
	_card_label_away = lbl_a

	_preview_card_away = StickerCard.new()
	_preview_card_away.custom_minimum_size = Vector2(190, 275)
	_preview_card_away.size_flags_horizontal = SIZE_SHRINK_CENTER
	_preview_card_away.pressed.connect(func(): _switch_kit_tab("away"))
	away_card_box.add_child(_preview_card_away)
	cards_hbox.add_child(away_card_box)

	# Botão para alternar modelo de atleta
	_btn_switch_athlete = Button.new()
	_btn_switch_athlete.text = "1/4"
	_btn_switch_athlete.tooltip_text = "Trocar o atleta da prévia"
	GameIcons.apply(_btn_switch_athlete, "elenco", 24)
	_btn_switch_athlete.custom_minimum_size = Vector2(96, 36)
	_btn_switch_athlete.size_flags_horizontal = SIZE_SHRINK_CENTER
	_btn_switch_athlete.pressed.connect(func():
		if not sample_athletes.is_empty():
			current_sample_idx = (current_sample_idx + 1) % sample_athletes.size()
			_btn_switch_athlete.text = "%d/%d" % [current_sample_idx + 1, sample_athletes.size()]
			_update_preview()
	)
	_style_button(_btn_switch_athlete, false)
	right_vbox.add_child(_btn_switch_athlete)


# =========================================================================
# LAYOUT COMPACTO (CELULAR)
# =========================================================================

## Estrutura do compacto, criada uma vez e vazia: _apply_layout() muda as peças de lugar.
func _build_compact_shell() -> void:
	_body_compact = VBoxContainer.new()
	_body_compact.size_flags_vertical = SIZE_EXPAND_FILL
	_body_compact.add_theme_constant_override("separation", 0)
	_body_compact.visible = false
	_body_expanded.get_parent().add_child(_body_compact)

	# Pré-visualização fixa no topo: as duas camisas (toque escolhe qual editar) e o contraste.
	var stage := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = DesignTokens.COLOR_BG_SURFACE
	st.border_width_bottom = 1
	st.border_color = BORDER
	st.set_content_margin_all(DesignTokens.SPACING_SM)
	stage.add_theme_stylebox_override("panel", st)
	_body_compact.add_child(stage)
	_compact_preview = VBoxContainer.new()
	_compact_preview.add_theme_constant_override("separation", DesignTokens.SPACING_SM)
	stage.add_child(_compact_preview)

	# Etapas (uma seção por vez)
	var steps_margin := MarginContainer.new()
	for side in ["left", "right", "top"]:
		steps_margin.add_theme_constant_override("margin_" + side, DesignTokens.SPACING_SM)
	_body_compact.add_child(steps_margin)
	_compact_steps_slot = VBoxContainer.new()
	steps_margin.add_child(_compact_steps_slot)

	_compact_scroll = ScrollContainer.new()
	_compact_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_compact_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		scroll_margin.add_theme_constant_override("margin_" + side, DesignTokens.SPACING_SM)
	_compact_scroll.add_child(scroll_margin)
	_body_compact.add_child(_compact_scroll)

	# Rodapé na zona do polegar: Sortear + Salvar (a ação principal)
	var bottom := PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = DesignTokens.COLOR_BG_SURFACE
	bs.border_width_top = 1
	bs.border_color = BORDER
	bs.set_content_margin_all(DesignTokens.SPACING_SM)
	bottom.add_theme_stylebox_override("panel", bs)
	_body_compact.add_child(bottom)
	_compact_bottom = HBoxContainer.new()
	_compact_bottom.add_theme_constant_override("separation", DesignTokens.SPACING_SM)
	bottom.add_child(_compact_bottom)


func _apply_layout() -> void:
	if not _layout_ready:
		return
	var want := size.x > 0.0 and size.x < COMPACT_MAX
	if want == compact and _body_compact.visible == compact:
		return
	compact = want
	_body_expanded.visible = not compact
	_body_compact.visible = compact
	var scroll_margin: Control = _compact_scroll.get_child(0)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if compact else TextServer.AUTOWRAP_OFF
	if compact:
		_move(_error_label, _compact_preview)
		_compact_preview.move_child(_error_label, 0)
		_move(_left_vbox, scroll_margin)
		_move(_cards_hbox, _compact_preview)
		_move(_contrast_card_panel, _compact_preview)
		_move(_btn_switch_athlete, _compact_preview)
		_move(_btn_random, _compact_bottom)
		_move(_btn_save, _compact_bottom)
		_btn_random.custom_minimum_size = Vector2(UiKit.TOUCH, UiKit.TOUCH)
		_btn_save.custom_minimum_size = Vector2(0, UiKit.TOUCH)
		_btn_save.size_flags_horizontal = SIZE_EXPAND_FILL
		for row in _id_rows:
			row.vertical = true
			row.alignment = BoxContainer.ALIGNMENT_BEGIN
		for l in _id_labels:
			l.custom_minimum_size.x = 0
		_btn_switch_athlete.custom_minimum_size = Vector2(0, 40)
		_btn_switch_athlete.size_flags_horizontal = SIZE_SHRINK_CENTER
		for card: StickerCard in [_preview_card_home, _preview_card_away]:
			card.custom_minimum_size = Vector2(118, 171)
		_cards_hbox.add_theme_constant_override("separation", DesignTokens.SPACING_LG)
		_pat_grid.columns = 4
	else:
		_move(_left_vbox, _scroll_left)
		_move(_contrast_card_panel, _left_vbox)
		_move(_cards_hbox, _right_vbox)
		_move(_btn_switch_athlete, _right_vbox)
		_right_vbox.move_child(_cards_hbox, _preview_header.get_index() + 1)
		var gear_at := _header_box.get_child_count() - 1
		_move(_error_label, _header_box)
		_header_box.move_child(_error_label, gear_at)
		gear_at += 1
		_move(_btn_random, _header_box)
		_move(_btn_save, _header_box)
		_header_box.move_child(_btn_random, gear_at)
		_header_box.move_child(_btn_save, gear_at + 1)
		_btn_random.custom_minimum_size = Vector2(UiKit.TOUCH, 34)
		_btn_save.custom_minimum_size = Vector2(140, 34)
		_btn_save.size_flags_horizontal = SIZE_FILL
		_btn_switch_athlete.custom_minimum_size = Vector2(96, 36)
		for card: StickerCard in [_preview_card_home, _preview_card_away]:
			card.custom_minimum_size = Vector2(190, 275)
		_cards_hbox.add_theme_constant_override("separation", 20)
		_pat_grid.columns = 6
		for row in _id_rows:
			row.vertical = false
			row.alignment = BoxContainer.ALIGNMENT_CENTER
		for l in _id_labels:
			l.custom_minimum_size.x = 60
	_show_step(_step)
	_update_ui_state()


## Etapa do compacto: só as seções dela ficam visíveis (no expandido, todas).
func _show_step(step: String) -> void:
	_step = step
	for c in _compact_steps_slot.get_children():
		c.queue_free()
	if compact:
		var seg := UiKit.segmented(STEPS, _step, _show_step)
		# Cinco etapas precisam caber em 360 dp: respiro lateral menor e texto que corta, não empurra.
		for b: Button in seg.get_children():
			b.clip_text = true
			# Os estilos são instâncias próprias de cada botão (UiKit.style_button): ajustar no lugar.
			# Não duplicar: a NineSliceStyle perde a arte pintada no duplicate().
			for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				DesignTokens.compact_margins(b.get_theme_stylebox(st), 4, 4)
		_compact_steps_slot.add_child(seg)
		_compact_scroll.scroll_vertical = 0
	var wanted: Array = STEP_SECTIONS.get(_step, [])
	for sid in _sections:
		(_sections[sid] as Control).visible = not compact or wanted.has(sid)


static func _move(node: Node, to: Node) -> void:
	if node.get_parent() == to:
		return
	if node.get_parent():
		node.get_parent().remove_child(node)
	to.add_child(node)


func _create_card(title: String, parent_container: Container, section_id: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = BG_CARD
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = BORDER
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	parent_container.add_child(panel)
	if section_id != "":
		_sections[section_id] = panel

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var h_title := Label.new()
	h_title.text = title.to_upper()
	h_title.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	h_title.add_theme_font_override("font", DesignTokens.display_font())
	h_title.add_theme_color_override("font_color", ACCENT_CYAN)
	vbox.add_child(h_title)

	var sep := HSeparator.new()
	var sep_style := StyleBoxLine.new()
	sep_style.color = DesignTokens.COLOR_BORDER_SUBTLE
	sep_style.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	return vbox


## Paleta (16 cores do jogo) + seletor livre, numa janela que abre sobre a amostra tocada.
func _build_color_popup() -> void:
	_color_popup = PopupPanel.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_color_popup.add_child(box)
	var pal_grid := GridContainer.new()
	pal_grid.columns = 8
	pal_grid.add_theme_constant_override("h_separation", 6)
	pal_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(pal_grid)
	for hex in PALETTE_PRESETS:
		var p_btn := Button.new()
		p_btn.custom_minimum_size = Vector2(32, 32)
		p_btn.tooltip_text = hex
		for st in ["normal", "hover", "pressed"]:
			p_btn.add_theme_stylebox_override(st, _swatch_box(Color(hex), st == "hover"))
		p_btn.pressed.connect(func():
			_set_kit_color(_active_color_idx, Color(hex))
			_color_popup.hide()
		)
		pal_grid.add_child(p_btn)
	_color_picker = ColorPicker.new()
	_color_picker.edit_alpha = false
	_color_picker.presets_visible = false
	_color_picker.color_modes_visible = false
	_color_picker.sliders_visible = false
	_color_picker.sampler_visible = false
	_color_picker.custom_minimum_size = Vector2(280, 0)
	_color_picker.color_changed.connect(func(c: Color): _set_kit_color(_active_color_idx, c))
	box.add_child(_color_picker)
	add_child(_color_popup)


func _open_color_popup(i: int, anchor: Control) -> void:
	_active_color_idx = i
	var cols: Array = get_active_kit().get("colors", ["#ffffff", "#ffffff", "#ffffff"])
	_color_picker.color = Color(str(cols[i]) if i < cols.size() else "#ffffff")
	_color_popup.reset_size()
	var r := anchor.get_global_rect()
	var vp := get_viewport_rect().size
	var pos := Vector2(r.position.x, r.end.y + 4)
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - _color_popup.size.x - 4.0))
	if pos.y + _color_popup.size.y > vp.y:
		pos.y = maxf(4.0, r.position.y - _color_popup.size.y - 4.0)
	_color_popup.popup(Rect2i(Vector2i(pos), _color_popup.size))
	_update_ui_state()


func _set_kit_color(i: int, c: Color) -> void:
	var k := get_active_kit()
	var cols: Array = k.get("colors", ["#ffffff", "#ffffff", "#ffffff"]).duplicate()
	while cols.size() < 3:
		cols.append("#ffffff")
	cols[i] = "#" + c.to_html(false)
	k["colors"] = cols
	set_active_kit(k)
	_update_ui_state()


## Fundo de uma amostra de cor (contorno de tinta; mais grosso quando selecionada ou em hover).
static func _swatch_box(c: Color, strong: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.border_color = DesignTokens.COLOR_INK
	sb.set_border_width_all(3 if strong else 1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	return sb


## Cor do texto que lê em cima de `c` (tinta no claro, branco no escuro).
static func _ink_on(c: Color) -> Color:
	return DesignTokens.COLOR_INK if c.get_luminance() > 0.5 else Color.WHITE


## Miniatura de camisa (padrão ou gola) guardada em `store` para recolorir quando o kit muda.
func _thumb_for(id: String, store: Dictionary, collar_only: bool) -> KitThumb:
	var t := KitThumb.new(52)
	t.collar_only = collar_only
	store[id] = t
	return t


static func _centered(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(child)
	return c


## Miniaturas com as cores, repetições e gola do kit em edição (cada uma com o seu padrão/gola).
func _refresh_thumbs() -> void:
	var k := get_active_kit()
	for p_id in _pattern_thumbs:
		var kp := k.duplicate()
		kp["pattern"] = p_id
		var t: KitThumb = _pattern_thumbs[p_id]
		t.kit = kp
		t.locked = not Cosmetics.is_unlocked(p_id, owner_club)
	for c_id in _collar_thumbs:
		var kc := k.duplicate()
		kc["collar"] = c_id
		(_collar_thumbs[c_id] as KitThumb).kit = kc


func _create_color_index_row(label_text: String, field_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(70, 0)
	lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", TEXT_MUTED)
	row.add_child(lbl)

	var btn_group := HBoxContainer.new()
	btn_group.add_theme_constant_override("separation", 4)
	var buttons: Array[Button] = []

	# Uma bolinha por cor do kit (principal, secundária, detalhe), pintada com a cor de verdade.
	for i in range(3):
		var b := Button.new()
		b.tooltip_text = COLOR_NAMES[i]
		b.custom_minimum_size = Vector2(36, 36)
		b.pressed.connect(func():
			var k := get_active_kit()
			k[field_name] = i
			set_active_kit(k)
			_update_ui_state()
		)
		btn_group.add_child(b)
		buttons.append(b)

	_choice_button_groups[field_name] = buttons
	row.add_child(btn_group)
	return row


func _style_button(btn: Button, is_primary: bool) -> void:
	btn.add_theme_stylebox_override("normal", DesignTokens.compact_margins(DesignTokens.style_button(is_primary, false), 12, 6))
	btn.add_theme_stylebox_override("hover", DesignTokens.compact_margins(DesignTokens.style_button(is_primary, true), 12, 6))
	btn.add_theme_stylebox_override("pressed", DesignTokens.compact_margins(DesignTokens.style_button(is_primary, false, true), 12, 6))
	btn.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)


## Botão de escolha (aba de uniforme, padrão, gola, cor ativa...): amarelo quando selecionado.
func _style_toggle(btn: Button, selected: bool) -> void:
	for st in ["normal", "hover", "pressed"]:
		var sb := DesignTokens.style_button(selected, st == "hover", st == "pressed")
		btn.add_theme_stylebox_override(st, DesignTokens.compact_margins(sb, 6, 4))
	btn.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)



func _switch_kit_tab(tab: String) -> void:
	active_tab_kit = tab
	_update_ui_state()


func _update_ui_state() -> void:
	var k := get_active_kit()
	
	# Tab active states
	_style_toggle(_tab_btn_home, active_tab_kit == "home")

	_style_toggle(_tab_btn_away, active_tab_kit == "away")
	# Carta do uniforme em edição em destaque (no compacto é ela que escolhe o uniforme)
	if _layout_ready:
		_preview_card_home.modulate.a = 1.0 if active_tab_kit == "home" or not compact else 0.6
		_preview_card_away.modulate.a = 1.0 if active_tab_kit == "away" or not compact else 0.6
		_card_label_home.add_theme_color_override("font_color", ACCENT_CYAN if active_tab_kit == "home" and compact else TEXT_MAIN)
		_card_label_away.add_theme_color_override("font_color", ACCENT_CYAN if active_tab_kit == "away" and compact else TEXT_MAIN)

	# Patterns
	var cur_pat: String = str(k.get("pattern", "lisa"))
	for p_id in _pattern_buttons:
		var btn: Button = _pattern_buttons[p_id]
		_style_toggle(btn, p_id == cur_pat)
		btn.tooltip_text = tr(Cosmetics.PATTERNS[p_id].label) + ("" if Cosmetics.is_unlocked(p_id, owner_club) \
			else " · " + tr("COSMETICO_BLOQUEADO"))

	var params := str(Cosmetics.PATTERNS.get(cur_pat, {}).get("params", ""))
	var has_count := params == "count"
	var has_width := params == "width"
	_row_count.visible = has_count
	_row_width.visible = has_width
	_slider_count.value = int(k.get("count", 3))
	_label_count_val.text = str(int(k.get("count", 3)))
	_slider_width.value = float(k.get("width", 0.16))
	_label_width_val.text = "%d%%" % int(float(k.get("width", 0.16)) * 100)

	# Colors
	var cols: Array = k.get("colors", ["#ffffff", "#ffffff", "#ffffff"])
	while cols.size() < 3:
		cols.append("#ffffff")
	for i in range(_color_swatches.size()):
		var sw := _color_swatches[i]
		var c := Color(str(cols[i]))
		for st in ["normal", "hover", "pressed", "focus"]:
			sw.add_theme_stylebox_override(st, _swatch_box(c, st == "hover" or (_color_popup.visible and i == _active_color_idx)))
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			sw.add_theme_color_override(fc, _ink_on(c))
	_refresh_thumbs()
	# Brasões: escolhido em destaque, bloqueados apagados; todos com as cores e a sigla do clube.
	for c_id in _crest_buttons:
		var cb: Button = _crest_buttons[c_id]
		var free := Cosmetics.is_unlocked(c_id, owner_club)
		_style_toggle(cb, c_id == _crest_id)
		cb.modulate.a = 1.0 if free else 0.45
		cb.tooltip_text = "" if free else tr("COSMETICO_BLOQUEADO")
	for crest in _crest_views:
		crest.primary = Color(str(home_kit.colors[0]))
		crest.secondary = Color(str(home_kit.colors[1]))
		crest.sigla = club_sigla
		crest.queue_redraw()

	# Collars
	var cur_col: String = str(k.get("collar", "Caricatura retrô com gola redonda.png"))
	for col_id in _collar_buttons:
		var btn: Button = _collar_buttons[col_id]
		_style_toggle(btn, col_id == cur_col)

	# Choice button groups (P, S, D)
	for field_name in _choice_button_groups:
		var cur_val: int = int(k.get(field_name, 0))
		var btns: Array = _choice_button_groups[field_name]
		for idx in range(btns.size()):
			var b: Button = btns[idx]
			for st in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(st, _swatch_box(Color(str(cols[idx])), idx == cur_val or st == "hover"))

	# Cuffs
	var has_cuff: bool = bool(k.get("cuff", true))
	_check_cuff.set_pressed_no_signal(has_cuff)
	_cuff_controls_box.visible = has_cuff
	_check_cuff_trim.set_pressed_no_signal(bool(k.get("cuff_trim", false)))

	# Contraste
	_validate_contrast()

	# Live Preview
	_update_preview()


func _validate_contrast() -> void:
	var h_cols: Array = home_kit.get("colors", ["#c8102e", "#ffffff", "#1d1d1b"])
	var a_cols: Array = away_kit.get("colors", ["#ffffff", "#c8102e", "#1d1d1b"])
	var c_home := Color(h_cols[0])
	var c_away := Color(a_cols[0])
	
	var lum_h: float = c_home.get_luminance()
	var lum_a: float = c_away.get_luminance()
	var diff_lum: float = absf(lum_h - lum_a)
	
	var c_style: StyleBoxFlat = _contrast_card_panel.get_theme_stylebox("panel").duplicate()
	if diff_lum > 0.35:
		_contrast_label.text = "Contraste bom: principal e reserva bem diferentes."
		_contrast_label.add_theme_color_override("font_color", COLOR_OK)
		c_style.border_color = COLOR_OK
	elif diff_lum > 0.18:
		_contrast_label.text = "Contraste médio: separe mais claro e escuro."
		_contrast_label.add_theme_color_override("font_color", COLOR_WARN)
		c_style.border_color = COLOR_WARN
	else:
		_contrast_label.text = "Contraste baixo: use uma camisa clara e uma escura."
		_contrast_label.add_theme_color_override("font_color", ACCENT)
		c_style.border_color = ACCENT
	_contrast_card_panel.add_theme_stylebox_override("panel", c_style)


func _update_preview() -> void:
	if sample_athletes.is_empty():
		return
	
	var athlete: Athlete = sample_athletes[current_sample_idx]
	var raw_card := GameStore.card_for(athlete)
	
	_preview_card_home.set_card(raw_card, home_kit, null, athlete.attributes)
	_preview_card_home.flip_to_front()

	_preview_card_away.set_card(raw_card, away_kit, null, athlete.attributes)
	_preview_card_away.flip_to_front()


func _randomize_club_style() -> void:
	var pal := PALETTE_PRESETS.duplicate()
	pal.shuffle()
	var c1: String = pal[0]
	var c2: String = pal[1]
	var c3: String = pal[2]

	home_kit = UniformMaps.normalize_kit({
		"pattern": _unlocked_patterns().pick_random(),
		"colors": [c1, c2, c3],
		"count": randi_range(2, 5),
		"width": randf_range(0.12, 0.25),
		"collar": COLLAR_OPTIONS.pick_random()["id"],
		"collar_color": randi_range(0, 2),
		"collar_trim_color": randi_range(0, 2),
		"sleeve_color": randi_range(0, 2),
		"cuff": true,
		"cuff_color": randi_range(0, 2),
		"cuff_trim": randi_range(0, 1) == 1,
		"cuff_trim_color": randi_range(0, 2),
		"sigla": club_sigla,
	})

	var a_c1: String = pal[3]
	var a_c2: String = pal[4]
	var a_c3: String = pal[5]
	away_kit = UniformMaps.normalize_kit({
		"pattern": _unlocked_patterns().pick_random(),
		"colors": [a_c1, a_c2, a_c3],
		"count": randi_range(2, 5),
		"width": randf_range(0.12, 0.25),
		"collar": COLLAR_OPTIONS.pick_random()["id"],
		"collar_color": randi_range(0, 2),
		"collar_trim_color": randi_range(0, 2),
		"sleeve_color": randi_range(0, 2),
		"cuff": true,
		"cuff_color": randi_range(0, 2),
		"cuff_trim": randi_range(0, 1) == 1,
		"cuff_trim_color": randi_range(0, 2),
		"sigla": club_sigla,
	})

	_update_ui_state()


func _unlocked_patterns() -> Array:
	return Cosmetics.PATTERNS.keys().filter(func(id): return Cosmetics.is_unlocked(id, owner_club))


func _on_save_pressed() -> void:
	var check := ClubValidation.validate(club_name, club_sigla)
	if not bool(check["ok"]):
		show_errors(check["errors"])
		return
	show_errors([])
	club_name = check["name"]
	club_sigla = check["sigla"]
	club_saved.emit(export_club_data())


## Mostra (ou limpa, com lista vazia) as mensagens de erro de validação no cabeçalho.
func show_errors(errors: Array) -> void:
	if _error_label:
		_error_label.text = "  ·  ".join(errors.map(func(e): return str(e)))
		_error_label.visible = not errors.is_empty()


func export_club_data() -> Dictionary:
	return {
		"name": club_name,
		"sigla": club_sigla,
		"club_identity": {
			"kit": home_kit,
			"away_kit": away_kit,
			"crest_id": _crest_id,
		}
	}
