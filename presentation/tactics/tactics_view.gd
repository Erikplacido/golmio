class_name TacticsView
extends Control
## Tela Completa de Escalação e Estratégia Técnica (Godot 4):
##   - Seletor de Formações Táticas (4-3-3, 4-4-2, 3-5-2, 4-2-3-1, 3-4-3, 5-3-2);
##   - Prancheta Tática Interativa (TacticalPitch) com 11 titulares;
##   - Banco de Reservas (5 vagas, GDD 2.3) e lista do Elenco com figurinhas;
##   - Atribuição de Capitão (C), Pênaltis (P) e Faltas (F);
##   - Postura Tática (Mentalidade, Linha de Marcação, Estilo de Passe);
##   - Cálculo em tempo real da Força da Equipe (OVR, DEF, MEI, ATA);
##   - Escalação Automática inteligente por posição.

signal tactics_saved(tactics_data: Dictionary)
signal back_pressed

const TacticalPitchClass = preload("res://presentation/tactics/tactical_pitch.gd")
const FORMATIONS := ["4-3-3", "4-4-2", "3-5-2", "4-2-3-1", "3-4-3", "5-3-2"]
const FORMATIONS_DIR := "res://data/formations"
## Reservas relacionados por partida (GDD 2.3; ruleset core.bench_size).
const BENCH_SIZE := 5

## Cores de UI da tela (tema Golmio: DesignTokens)
const BG_CARD := DesignTokens.COLOR_BG_SURFACE
const BG_INPUT := DesignTokens.COLOR_BG_INPUT
const BORDER := DesignTokens.COLOR_INK
const ACCENT := DesignTokens.COLOR_ACCENT_PRIMARY
const ACCENT_CYAN := DesignTokens.COLOR_ACCENT_BLUE
const TEXT_MAIN := DesignTokens.COLOR_TEXT_PRIMARY
const TEXT_MUTED := DesignTokens.COLOR_TEXT_SECONDARY
const COLOR_OK := DesignTokens.COLOR_ACCENT_EMERALD
const COLOR_GOLD := DesignTokens.COLOR_TEXT_PRIMARY   # OVR: o amarelo não se lê como texto no papel

## Estado da equipe
var club_name: String = "Rubro Várzea"
var club_sigla: String = "RVZ"
var club_kit: Dictionary = {}
var current_formation: String = "4-3-3"
var squad: Array[Athlete] = []

## Postura
var mentality: String = "equilibrado"       # um de GameTerms.MENTALITIES
var defensive_line: String = "media"        # "baixa" | "media" | "alta"
var passing_style: String = "misto"         # "curto" | "misto" | "direto"

## Papéis especiais
var captain_id: String = ""
var penalty_id: String = ""
var freekick_id: String = ""
var corner_id: String = ""

## Dentro da casca (AppShell): a barra superior já tem Voltar e Opções, então somem daqui.
var embedded := false

## Substituições automáticas
var auto_sub_stamina: int = 35
var auto_sub_minute: int = 70
var current_club: Club = null

## 11 titulares e até BENCH_SIZE reservas (athlete_id)
var starting_11: Array[String] = []
var bench: Array[String] = []
var selected_field_slot: int = -1
var selected_squad_athlete_id: String = ""
var active_filter: String = "ALL" # "ALL" | "GK" | "DEF" | "MID" | "FWD"

## Nós de UI
var _pitch: TacticalPitchClass
var _lbl_ovr: Label
var _lbl_def: Label
var _lbl_mid: Label
var _lbl_fwd: Label
var _toast_label: Label
var _formation_buttons: Dictionary = {}
var _mentality_buttons: Dictionary = {}
var _def_line_buttons: Dictionary = {}
var _pass_buttons: Dictionary = {}
var _opt_captain: OptionButton
var _opt_penalty: OptionButton
var _opt_freekick: OptionButton
var _opt_corner: OptionButton
var _squad_scroll: ScrollContainer
var _squad_grid: VBoxContainer
var _bench_container: HBoxContainer

# Layout responsivo: abaixo de NARROW_WIDTH as colunas empilham (celular em retrato e em paisagem).
# É a soma das larguras mínimas das 3 colunas (280 + 480 + 330), dos espaços e das margens.
const NARROW_WIDTH := 1120.0
var _narrow := false
var _content_box: BoxContainer
var _left_scroll: ScrollContainer
var _center_panel: PanelContainer
var _right_panel: PanelContainer
var _header_title: Label
var _header_ratings: Control
var _header_buttons: Array[Button] = []


func _ready() -> void:
	anchors_preset = PRESET_FULL_RECT
	club_kit = UniformMaps.normalize_kit(UniformMaps.KIT_DEFAULT.duplicate(true))
	_load_squad_from_world_or_demo()
	if bench.size() > BENCH_SIZE:
		bench.resize(BENCH_SIZE)   # saves de quando o banco tinha 7 vagas
	_build_ui()
	_apply_formation(current_formation)
	if starting_11.filter(func(id: String): return id != "").size() < 11:
		_auto_lineup_best()
	_update_full_ui()
	resized.connect(_apply_responsive)
	_apply_responsive.call_deferred()


func _load_squad_from_world_or_demo() -> void:
	var app_node = get_node_or_null("/root/App")
	if app_node and app_node.get("backend") != null:
		var w_dict: Dictionary = app_node.backend.load_world()
		var world := World.from_dict(w_dict)
		if not world.clubs.is_empty():
			var c_id = world.clubs.keys()[0]
			var c: Club = world.clubs[c_id]
			current_club = c
			club_name = c.name
			club_sigla = c.short_name
			club_kit = PortraitRenderer.kit_for_club(c)
			squad.clear()
			for a_id in c.athlete_ids:
				if world.athletes.has(a_id):
					squad.append(world.athletes[a_id])
			if c.ext.has("tactics"):
				var tac: Dictionary = c.ext["tactics"]
				current_formation = str(tac.get("formation", "4-3-3"))
				mentality = str(tac.get("mentality", "equilibrado"))
				defensive_line = str(tac.get("defensive_line", "media"))
				passing_style = str(tac.get("passing_style", "misto"))
				captain_id = str(tac.get("captain_id", ""))
				penalty_id = str(tac.get("penalty_taker_id", ""))
				freekick_id = str(tac.get("freekick_taker_id", ""))
				corner_id = str(tac.get("corner_taker_id", ""))
				auto_sub_stamina = int(tac.get("sub_rule_stamina", 35))
				auto_sub_minute = int(tac.get("sub_rule_minute", 70))
				starting_11.assign(Array(tac.get("starting_11", [])))
				bench.assign(Array(tac.get("bench", [])))
			if not squad.is_empty():
				return

	_load_demo_squad()


func setup_club(club: Club, athletes: Array[Athlete], tactics_data: Dictionary = {}) -> void:
	current_club = club
	club_name = club.name
	club_sigla = club.short_name
	club_kit = PortraitRenderer.kit_for_club(club)
	squad = athletes.duplicate()
	if not tactics_data.is_empty():
		current_formation = str(tactics_data.get("formation", "4-3-3"))
		mentality = str(tactics_data.get("mentality", "equilibrado"))
		defensive_line = str(tactics_data.get("defensive_line", "media"))
		passing_style = str(tactics_data.get("passing_style", "misto"))
		captain_id = str(tactics_data.get("captain_id", ""))
		penalty_id = str(tactics_data.get("penalty_taker_id", ""))
		freekick_id = str(tactics_data.get("freekick_taker_id", ""))
		corner_id = str(tactics_data.get("corner_taker_id", ""))
		auto_sub_stamina = int(tactics_data.get("sub_rule_stamina", 35))
		auto_sub_minute = int(tactics_data.get("sub_rule_minute", 70))
		starting_11.assign(Array(tactics_data.get("starting_11", [])))
		bench.assign(Array(tactics_data.get("bench", [])))
	_apply_formation(current_formation)
	if starting_11.filter(func(id: String): return id != "").size() < 11:
		_auto_lineup_best()
	_update_full_ui()


## Elenco de demonstração (tela aberta sem clube salvo): 18 atletas do gerador oficial.
func _load_demo_squad() -> void:
	var positions := [
		"GK", "DEF", "DEF", "DEF", "DEF",
		"MID", "MID", "MID", "FWD", "FWD", "FWD",
		"GK", "DEF", "MID", "MID", "FWD", "FWD", "FWD"
	]
	var tiers: Array = []
	for i in positions.size():
		tiers.append(["ouro", "prata", "bronze"][i % 3])
	squad.clear()
	squad.append_array(PreviewAthletes.generate(positions, tiers))


func _build_ui() -> void:
	theme = DesignTokens.base_theme(true)
	add_child(UiFrames.paper_background())

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 0)
	add_child(main_vbox)

	# 1. Header Superior
	var header := PanelContainer.new()
	header.custom_minimum_size = Vector2(0, 58)
	var h_style := StyleBoxFlat.new()
	h_style.bg_color = DesignTokens.COLOR_BG_SURFACE
	h_style.border_width_bottom = 1
	h_style.border_color = BORDER
	h_style.content_margin_left = 10
	h_style.content_margin_right = 10
	header.add_theme_stylebox_override("panel", h_style)
	main_vbox.add_child(header)

	var h_hbox := HBoxContainer.new()
	h_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(h_hbox)

	var btn_back := Button.new()
	btn_back.text = "Voltar"
	GameIcons.apply(btn_back, "voltar", 20)
	btn_back.pressed.connect(func():
		back_pressed.emit()
		var router := get_node_or_null("/root/Router")
		if router:
			router.back()
		else:
			get_tree().change_scene_to_file("res://presentation/match_view/match_view.tscn")
	)
	_style_button(btn_back, false)
	btn_back.visible = not embedded
	h_hbox.add_child(btn_back)

	# O título encolhe com reticências: em janelas estreitas os botões continuam visíveis.
	var title_lbl := Label.new()
	h_hbox.add_child(GameIcons.rect("tatica", 26))
	title_lbl.text = "ESCALAÇÃO & ESQUEMA TÁTICO · %s (%s)" % [club_name, club_sigla]
	title_lbl.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
	title_lbl.add_theme_font_override("font", DesignTokens.display_font())
	title_lbl.add_theme_color_override("font_color", TEXT_MAIN)
	title_lbl.clip_text = true
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	title_lbl.custom_minimum_size.x = 80
	title_lbl.tooltip_text = title_lbl.text
	title_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	h_hbox.add_child(title_lbl)
	_header_title = title_lbl

	# Ratings do Time
	_header_ratings = _create_header_ratings()
	h_hbox.add_child(_header_ratings)

	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	_toast_label.add_theme_color_override("font_color", COLOR_OK)
	h_hbox.add_child(_toast_label)

	var btn_auto := Button.new()
	btn_auto.text = "Auto-Escalar"
	GameIcons.apply(btn_auto, "elenco", 20)
	btn_auto.pressed.connect(func():
		_auto_lineup_best()
		_update_full_ui()
	)
	_style_button(btn_auto, false)
	h_hbox.add_child(btn_auto)
	_header_buttons.append(btn_auto)

	var btn_clear := Button.new()
	btn_clear.text = "Limpar"
	GameIcons.apply(btn_clear, "fechar", 18)
	btn_clear.pressed.connect(func():
		for i in range(starting_11.size()):
			starting_11[i] = ""
		_update_full_ui()
	)
	_style_button(btn_clear, false)
	h_hbox.add_child(btn_clear)
	_header_buttons.append(btn_clear)

	var btn_save := Button.new()
	btn_save.text = "Salvar Tática"
	GameIcons.apply(btn_save, "confirmar", 20)
	btn_save.pressed.connect(_on_save_tactics)
	_style_button(btn_save, true)
	h_hbox.add_child(btn_save)
	_header_buttons.append(btn_save)

	var btn_play := Button.new()
	btn_play.text = "Jogar Partida"
	GameIcons.apply(btn_play, "jogar", 20)
	btn_play.pressed.connect(func():
		var router := get_node_or_null("/root/Router")
		if router:
			router.go("prematch")
		else:
			get_tree().change_scene_to_file("res://presentation/match_view/match_view.tscn")
	)
	_style_button(btn_play, true)
	h_hbox.add_child(btn_play)
	_header_buttons.append(btn_play)

	if not embedded:
		var btn_settings := GearButton.new()
		_style_button(btn_settings, false)
		h_hbox.add_child(btn_settings)
		add_to_group("settings_button_host")

	# 2. Conteúdo em 3 Colunas: Esquerda (Tática) / Centro (Campinho) / Direita (Elenco & Banco).
	# Em tela estreita (_apply_responsive) as colunas empilham e a página inteira rola.
	var content_hbox := BoxContainer.new() # BoxContainer genérico: HBoxContainer não troca de eixo
	content_hbox.size_flags_vertical = SIZE_EXPAND_FILL
	content_hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 8)
	_content_box = content_hbox
	var margin_c := MarginContainer.new()
	margin_c.size_flags_vertical = SIZE_EXPAND_FILL
	margin_c.size_flags_horizontal = SIZE_EXPAND_FILL
	margin_c.add_theme_constant_override("margin_left", 8)
	margin_c.add_theme_constant_override("margin_right", 8)
	margin_c.add_theme_constant_override("margin_top", 12)
	margin_c.add_theme_constant_override("margin_bottom", 12)
	margin_c.add_child(content_hbox)
	var page_scroll := ScrollContainer.new()
	page_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_scroll.add_child(margin_c)
	main_vbox.add_child(page_scroll)

	# COLUNA ESQUERDA: Formação, Postura e Papéis
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(280, 0)
	_left_scroll = left_scroll
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_hbox.add_child(left_scroll)

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 12)
	left_scroll.add_child(left_vbox)

	# Card Formação
	var card_form_box := _create_card("Formação Tática", left_vbox)
	var form_grid := GridContainer.new()
	form_grid.columns = 3
	form_grid.add_theme_constant_override("h_separation", 6)
	form_grid.add_theme_constant_override("v_separation", 6)
	card_form_box.add_child(form_grid)

	for f_id in FORMATIONS:
		var btn_f := Button.new()
		btn_f.text = f_id
		btn_f.custom_minimum_size = Vector2(0, 32)
		btn_f.size_flags_horizontal = SIZE_EXPAND_FILL
		btn_f.pressed.connect(func(): _apply_formation(f_id))
		_formation_buttons[f_id] = btn_f
		form_grid.add_child(btn_f)

	# Card Postura Tática
	var card_posture_box := _create_card("Instruções Técnicas", left_vbox)
	var posture_box := VBoxContainer.new()
	posture_box.add_theme_constant_override("separation", 8)
	card_posture_box.add_child(posture_box)

	# Mentalidade
	var lbl_ment := Label.new()
	lbl_ment.text = "Mentalidade:"
	lbl_ment.add_theme_color_override("font_color", TEXT_MUTED)
	lbl_ment.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	lbl_ment.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_MEDIUM))
	posture_box.add_child(lbl_ment)
	# Quebra linha conforme a largura da coluna (7 níveis não cabem lado a lado).
	var ment_grid := HFlowContainer.new()
	ment_grid.add_theme_constant_override("h_separation", 4)
	ment_grid.add_theme_constant_override("v_separation", 4)
	for m_id in GameTerms.MENTALITIES:
		var m := [m_id, GameTerms.mentality(m_id)]
		var b := Button.new()
		b.text = m[1]
		b.tooltip_text = GameTerms.mentality(m_id, true)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
		b.pressed.connect(func():
			mentality = m[0]
			_update_full_ui()
		)
		_mentality_buttons[m[0]] = b
		ment_grid.add_child(b)
	posture_box.add_child(ment_grid)

	# Linha de Marcação
	var lbl_line := Label.new()
	lbl_line.text = "Linha de Marcação:"
	lbl_line.add_theme_color_override("font_color", TEXT_MUTED)
	lbl_line.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	lbl_line.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_MEDIUM))
	posture_box.add_child(lbl_line)
	var line_hbox := HFlowContainer.new()
	for l in [["baixa", "Bloco Baixo"], ["media", "Média"], ["alta", "Linha Alta"]]:
		var b := Button.new()
		b.text = l[1]
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.pressed.connect(func():
			defensive_line = l[0]
			_update_full_ui()
		)
		_def_line_buttons[l[0]] = b
		line_hbox.add_child(b)
	posture_box.add_child(line_hbox)

	# Estilo de Passe
	var lbl_pass := Label.new()
	lbl_pass.text = "Estilo de Passe:"
	lbl_pass.add_theme_color_override("font_color", TEXT_MUTED)
	lbl_pass.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	lbl_pass.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_MEDIUM))
	posture_box.add_child(lbl_pass)
	var pass_hbox := HFlowContainer.new()
	for p in [["curto", "Curto"], ["misto", "Misto"], ["direto", "Longo"]]:
		var b := Button.new()
		b.text = p[1]
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.pressed.connect(func():
			passing_style = p[0]
			_update_full_ui()
		)
		_pass_buttons[p[0]] = b
		pass_hbox.add_child(b)
	posture_box.add_child(pass_hbox)

	# Card Papéis Especiais
	var card_roles_box := _create_card("Liderança & Bolas Paradas", left_vbox)
	var roles_box := VBoxContainer.new()
	roles_box.add_theme_constant_override("separation", 6)
	card_roles_box.add_child(roles_box)

	_opt_captain = _create_role_selector("Capitão do Time (C):", roles_box, func(id: String): captain_id = id)
	_opt_penalty = _create_role_selector("Batedor de Pênaltis (P):", roles_box, func(id: String): penalty_id = id)
	_opt_freekick = _create_role_selector("Cobrador de Faltas (F):", roles_box, func(id: String): freekick_id = id)
	_opt_corner = _create_role_selector("Escanteios (E):", roles_box, func(id: String): corner_id = id)

	# Card Substituições Automáticas
	var card_subs_box := _create_card("Substituições Automáticas", left_vbox)
	var subs_box := VBoxContainer.new()
	subs_box.add_theme_constant_override("separation", 6)
	card_subs_box.add_child(subs_box)

	var lbl_sub1 := Label.new()
	lbl_sub1.text = "Substituir por estamina baixa:"
	lbl_sub1.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	lbl_sub1.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_MEDIUM))
	lbl_sub1.add_theme_color_override("font_color", TEXT_MUTED)
	subs_box.add_child(lbl_sub1)

	var sub1_opt := OptionButton.new()
	sub1_opt.add_item("Quando estamina < 30%", 30)
	sub1_opt.add_item("Quando estamina < 40%", 40)
	sub1_opt.add_item("Quando estamina < 50%", 50)
	sub1_opt.add_item("Desativado", 0)
	sub1_opt.select(1 if auto_sub_stamina == 40 else (2 if auto_sub_stamina == 50 else (3 if auto_sub_stamina == 0 else 0)))
	sub1_opt.item_selected.connect(func(idx: int): auto_sub_stamina = sub1_opt.get_item_id(idx))
	subs_box.add_child(sub1_opt)

	var lbl_sub2 := Label.new()
	lbl_sub2.text = "Substituição programada:"
	lbl_sub2.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	lbl_sub2.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_MEDIUM))
	lbl_sub2.add_theme_color_override("font_color", TEXT_MUTED)
	subs_box.add_child(lbl_sub2)

	var sub2_opt := OptionButton.new()
	sub2_opt.add_item("Aos 60 minutos", 60)
	sub2_opt.add_item("Aos 70 minutos", 70)
	sub2_opt.add_item("Aos 80 minutos", 80)
	sub2_opt.add_item("Desativado", 0)
	sub2_opt.select(0 if auto_sub_minute == 60 else (2 if auto_sub_minute == 80 else (3 if auto_sub_minute == 0 else 1)))
	sub2_opt.item_selected.connect(func(idx: int): auto_sub_minute = sub2_opt.get_item_id(idx))
	subs_box.add_child(sub2_opt)

	# COLUNA CENTRAL: O Campinho Tático
	var center_panel := PanelContainer.new()
	center_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	center_panel.size_flags_vertical = SIZE_EXPAND_FILL
	var center_style := StyleBoxFlat.new()
	center_style.bg_color = BG_CARD
	center_style.border_width_left = 1
	center_style.border_width_top = 1
	center_style.border_width_right = 1
	center_style.border_width_bottom = 1
	center_style.border_color = BORDER
	center_style.corner_radius_top_left = 12
	center_style.corner_radius_top_right = 12
	center_style.corner_radius_bottom_left = 12
	center_style.corner_radius_bottom_right = 12
	center_style.content_margin_left = 12
	center_style.content_margin_right = 12
	center_style.content_margin_top = 12
	center_style.content_margin_bottom = 12
	center_panel.add_theme_stylebox_override("panel", center_style)
	content_hbox.add_child(center_panel)
	_center_panel = center_panel

	var pitch_vbox := VBoxContainer.new()
	pitch_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	pitch_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	pitch_vbox.add_theme_constant_override("separation", 8)
	center_panel.add_child(pitch_vbox)

	_pitch = TacticalPitchClass.new()
	_pitch.size_flags_horizontal = SIZE_EXPAND_FILL
	_pitch.size_flags_vertical = SIZE_EXPAND_FILL
	_pitch.slot_clicked.connect(_on_pitch_slot_clicked)
	pitch_vbox.add_child(_pitch)

	# Banco de Reservas no rodapé do campinho
	var bench_card := PanelContainer.new()
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = BG_INPUT
	b_style.corner_radius_top_left = 8
	b_style.corner_radius_top_right = 8
	b_style.corner_radius_bottom_left = 8
	b_style.corner_radius_bottom_right = 8
	b_style.content_margin_left = 8
	b_style.content_margin_right = 8
	b_style.content_margin_top = 6
	b_style.content_margin_bottom = 6
	bench_card.add_theme_stylebox_override("panel", b_style)
	pitch_vbox.add_child(bench_card)

	var bench_vbox := VBoxContainer.new()
	bench_vbox.add_theme_constant_override("separation", 4)
	bench_card.add_child(bench_vbox)

	var bench_title := Label.new()
	bench_title.text = "BANCO DE RESERVAS (%d VAGAS)" % BENCH_SIZE
	bench_title.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	bench_title.add_theme_font_override("font", DesignTokens.display_font())
	bench_title.add_theme_color_override("font_color", TEXT_MUTED)
	bench_vbox.add_child(bench_title)

	_bench_container = HBoxContainer.new()
	_bench_container.add_theme_constant_override("separation", 6)
	bench_vbox.add_child(_bench_container)

	# COLUNA DIREITA: Elenco Disponível & Filtros
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(330, 0)
	right_panel.size_flags_vertical = SIZE_EXPAND_FILL
	var r_style := StyleBoxFlat.new()
	r_style.bg_color = BG_CARD
	r_style.border_width_left = 1
	r_style.border_width_top = 1
	r_style.border_width_right = 1
	r_style.border_width_bottom = 1
	r_style.border_color = BORDER
	r_style.corner_radius_top_left = 10
	r_style.corner_radius_top_right = 10
	r_style.corner_radius_bottom_left = 10
	r_style.corner_radius_bottom_right = 10
	r_style.content_margin_left = 12
	r_style.content_margin_right = 12
	r_style.content_margin_top = 12
	r_style.content_margin_bottom = 12
	right_panel.add_theme_stylebox_override("panel", r_style)
	content_hbox.add_child(right_panel)
	_right_panel = right_panel

	var r_vbox := VBoxContainer.new()
	r_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	r_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	r_vbox.add_theme_constant_override("separation", 10)
	right_panel.add_child(r_vbox)

	var el_title := Label.new()
	el_title.text = "ELENCO DO CLUBE"
	el_title.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	el_title.add_theme_font_override("font", DesignTokens.display_font())
	el_title.add_theme_color_override("font_color", TEXT_MAIN)
	r_vbox.add_child(el_title)

	# Filtros de Posição
	var filter_hbox := HBoxContainer.new()
	filter_hbox.add_theme_constant_override("separation", 4)
	for f in [["ALL", "Todos"], ["GK", GameTerms.sector("GK")], ["DEF", GameTerms.sector("DEF")], ["MID", GameTerms.sector("MID")], ["FWD", GameTerms.sector("FWD")]]:
		var b := Button.new()
		b.text = f[1]
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.pressed.connect(func():
			active_filter = f[0]
			_render_squad_list()
		)
		filter_hbox.add_child(b)
	r_vbox.add_child(filter_hbox)

	_squad_scroll = ScrollContainer.new()
	_squad_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_squad_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	r_vbox.add_child(_squad_scroll)

	_squad_grid = VBoxContainer.new()
	_squad_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_squad_grid.add_theme_constant_override("separation", 6)
	_squad_scroll.add_child(_squad_grid)


## Paisagem: 3 colunas, cada uma com sua rolagem. Retrato (estreito): campo, elenco e instruções
## empilhados na largura toda, sem rolagens internas (a página rola); botões do topo só com ícone.
func _apply_responsive() -> void:
	if _content_box == null:
		return
	var narrow := size.x < NARROW_WIDTH
	# O título longo repete o da página: só aparece quando sobra largura para os botões.
	_header_title.visible = size.x >= 1400.0
	if narrow == _narrow and _content_box.vertical == narrow:
		return
	_narrow = narrow
	_content_box.vertical = narrow
	_content_box.add_theme_constant_override("separation", 12 if narrow else 8)
	var order: Array = [_center_panel, _right_panel, _left_scroll] if narrow else [_left_scroll, _center_panel, _right_panel]
	for i in order.size():
		_content_box.move_child(order[i], i)
	var inner_mode := ScrollContainer.SCROLL_MODE_DISABLED if narrow else ScrollContainer.SCROLL_MODE_AUTO
	_left_scroll.vertical_scroll_mode = inner_mode
	_squad_scroll.vertical_scroll_mode = inner_mode
	_left_scroll.custom_minimum_size.x = 0.0 if narrow else 280.0
	_right_panel.custom_minimum_size.x = 0.0 if narrow else 330.0
	for c: Control in [_left_scroll, _center_panel, _right_panel]:
		c.size_flags_horizontal = SIZE_EXPAND_FILL if narrow or c == _center_panel else SIZE_FILL
	_pitch.custom_minimum_size = Vector2(0, 620) if narrow else Vector2(480, 580)
	_header_ratings.visible = not narrow
	for b: Button in _bench_container.get_children():
		_fit_bench_button(b)
	for b in _header_buttons:
		if not b.has_meta("full_text"):
			b.set_meta("full_text", b.text)
		b.text = "" if narrow else str(b.get_meta("full_text"))
		b.tooltip_text = str(b.get_meta("full_text"))
		b.custom_minimum_size.x = UiKit.TOUCH if narrow else 0.0


func _create_card(title: String, parent_container: Container) -> VBoxContainer:
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
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	parent_container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
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


func _create_header_ratings() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)

	_lbl_ovr = Label.new()
	_lbl_def = Label.new()
	_lbl_mid = Label.new()
	_lbl_fwd = Label.new()

	for pair in [[_lbl_ovr, "OVR", COLOR_GOLD], [_lbl_def, GameTerms.sector("DEF"), DesignTokens.COLOR_POS_DEF], [_lbl_mid, GameTerms.sector("MID"), DesignTokens.COLOR_POS_MID], [_lbl_fwd, GameTerms.sector("FWD"), DesignTokens.COLOR_POS_FWD]]:
		var lbl: Label = pair[0]
		var tag: String = pair[1]
		var col: Color = pair[2]
		lbl.text = "%s --" % tag
		lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
		lbl.add_theme_color_override("font_color", col)
		hbox.add_child(lbl)

	return hbox


func _create_role_selector(label_text: String, parent: Control, callback: Callable) -> OptionButton:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	lbl.add_theme_color_override("font_color", TEXT_MUTED)
	vbox.add_child(lbl)

	var opt := OptionButton.new()
	opt.size_flags_horizontal = SIZE_EXPAND_FILL
	opt.item_selected.connect(func(idx: int):
		var a_id: String = opt.get_item_metadata(idx)
		callback.call(a_id)
		_pitch.set_special_roles(captain_id, penalty_id, freekick_id)
	)
	vbox.add_child(opt)
	parent.add_child(vbox)
	return opt


func _style_button(btn: Button, is_primary: bool) -> void:
	btn.add_theme_stylebox_override("normal", DesignTokens.compact_margins(DesignTokens.style_button(is_primary, false)))
	btn.add_theme_stylebox_override("hover", DesignTokens.compact_margins(DesignTokens.style_button(is_primary, true)))
	btn.add_theme_stylebox_override("pressed", DesignTokens.compact_margins(DesignTokens.style_button(is_primary, false, true)))
	btn.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)


## Botão de escolha (formação, mentalidade, linha, passe): amarelo quando selecionado, com
## respiro lateral pequeno para caber na coluna estreita.
func _style_toggle(btn: Button, selected: bool) -> void:
	_style_button(btn, selected)
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBox = btn.get_theme_stylebox(st)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		btn.add_theme_stylebox_override(st, sb)


func _apply_formation(f_id: String) -> void:
	current_formation = f_id
	var raw_slots: Array = DemoData.formation(f_id)
	
	# Preserva titulares já alocados
	while starting_11.size() < 11:
		starting_11.append("")
	
	var pitch_slots: Array = []
	var functions: Array = GameTerms.roles_for_formation(raw_slots)
	for i in range(11):
		var s_data: Dictionary = raw_slots[i] if i < raw_slots.size() else {"role": "MID", "x": 0.5, "y": 0.5}
		var a_id := starting_11[i]
		var athlete: Athlete = _find_athlete(a_id)
		pitch_slots.append({
			"role": s_data.get("role", "MID"),
			"function": functions[i] if i < functions.size() else "",
			"x": s_data.get("x", 0.5),
			"y": s_data.get("y", 0.5),
			"athlete_id": a_id,
			"athlete_data": athlete,
		})
	
	_pitch.setup_formation(f_id, pitch_slots, club_kit)
	_pitch.set_special_roles(captain_id, penalty_id, freekick_id)


func _auto_lineup_best() -> void:
	var available: Array[Athlete] = squad.duplicate()
	# Ordena atletas por média de atributos
	available.sort_custom(func(a: Athlete, b: Athlete):
		var sum_a := 0.0
		for v in a.attributes.values(): sum_a += float(v)
		var sum_b := 0.0
		for v in b.attributes.values(): sum_b += float(v)
		return sum_a > sum_b
	)

	starting_11.clear()
	for i in range(11):
		starting_11.append("")

	var raw_slots := DemoData.formation(current_formation)
	var used_ids := {}

	# 1. Encaixa goleiro no slot GK
	for i in range(11):
		if i < raw_slots.size() and raw_slots[i].get("role") == "GK":
			var gk := available.filter(func(a: Athlete): return a.position == "GK" and not used_ids.has(a.id))
			if not gk.is_empty():
				starting_11[i] = gk[0].id
				used_ids[gk[0].id] = true

	# 2. Encaixa defensores, meias e atacantes na posição exata
	for i in range(11):
		if starting_11[i] != "": continue
		var role: String = raw_slots[i].get("role", "MID") if i < raw_slots.size() else "MID"
		var match_ath := available.filter(func(a: Athlete): return a.position == role and not used_ids.has(a.id))
		if not match_ath.is_empty():
			starting_11[i] = match_ath[0].id
			used_ids[match_ath[0].id] = true

	# 3. Preenche eventuais vagas restantes com os melhores disponíveis
	for i in range(11):
		if starting_11[i] == "":
			var rest := available.filter(func(a: Athlete): return not used_ids.has(a.id))
			if not rest.is_empty():
				starting_11[i] = rest[0].id
				used_ids[rest[0].id] = true

	# 4. Banco com os BENCH_SIZE melhores restantes
	bench.clear()
	var bench_candidates := available.filter(func(a: Athlete): return not used_ids.has(a.id))
	for i in range(min(BENCH_SIZE, bench_candidates.size())):
		bench.append(bench_candidates[i].id)

	# 5. Define capitão se ainda não definido
	if captain_id == "" or not used_ids.has(captain_id):
		captain_id = starting_11[0] if not starting_11.is_empty() else ""
	if penalty_id == "":
		penalty_id = starting_11[min(10, starting_11.size() - 1)]
	if freekick_id == "":
		freekick_id = starting_11[min(7, starting_11.size() - 1)]

	_apply_formation(current_formation)


func _on_pitch_slot_clicked(slot_idx: int, ath_id: String) -> void:
	if selected_squad_athlete_id != "":
		# Escala o atleta selecionado da lista neste slot
		_assign_athlete_to_starting_slot(selected_squad_athlete_id, slot_idx)
		selected_squad_athlete_id = ""
		selected_field_slot = -1
	else:
		if selected_field_slot == slot_idx:
			selected_field_slot = -1
		else:
			selected_field_slot = slot_idx
	
	_pitch.select_slot(selected_field_slot)
	_update_full_ui()


func _assign_athlete_to_starting_slot(ath_id: String, slot_idx: int) -> void:
	# Se já estava em outro slot titular, faz a troca direta
	var old_slot := starting_11.find(ath_id)
	var displaced_id := starting_11[slot_idx] if slot_idx < starting_11.size() else ""
	
	starting_11[slot_idx] = ath_id
	if old_slot >= 0:
		starting_11[old_slot] = displaced_id
	
	bench.erase(ath_id)
	if displaced_id != "" and old_slot < 0 and not bench.has(displaced_id) and bench.size() < BENCH_SIZE:
		bench.append(displaced_id)

	_apply_formation(current_formation)
	_update_full_ui()


func _find_athlete(ath_id: String) -> Athlete:
	for a in squad:
		if a.id == ath_id:
			return a
	return null


func _update_full_ui() -> void:
	# Botões de formação ativa
	for f_id in _formation_buttons:
		_style_toggle(_formation_buttons[f_id], f_id == current_formation)

	# Postura buttons
	_update_toggle_group(_mentality_buttons, mentality)
	_update_toggle_group(_def_line_buttons, defensive_line)
	_update_toggle_group(_pass_buttons, passing_style)

	# Atualiza dropdowns de papéis com titulares atuais
	_populate_role_option(_opt_captain, captain_id)
	_populate_role_option(_opt_penalty, penalty_id)
	_populate_role_option(_opt_freekick, freekick_id)
	if _opt_corner:
		_populate_role_option(_opt_corner, corner_id)

	# Renderiza banco e elenco
	_render_bench()
	_render_squad_list()

	# Recalcula força média do time
	_calculate_team_strength()


func _update_toggle_group(btns: Dictionary, active_val: String) -> void:
	for val in btns:
		_style_toggle(btns[val], val == active_val)


func _populate_role_option(opt: OptionButton, cur_id: String) -> void:
	opt.clear()
	var sel_idx := 0
	for i in range(starting_11.size()):
		var a_id := starting_11[i]
		var a := _find_athlete(a_id)
		if a != null:
			opt.add_item("%s (%s)" % [a.name, GameTerms.sector(a.position)])
			opt.set_item_metadata(opt.item_count - 1, a.id)
			if a.id == cur_id:
				sel_idx = opt.item_count - 1
	if opt.item_count > 0:
		opt.selected = sel_idx


func _render_bench() -> void:
	for ch in _bench_container.get_children():
		ch.queue_free()

	for i in range(BENCH_SIZE):
		var a_id := bench[i] if i < bench.size() else ""
		var a := _find_athlete(a_id)
		
		var b_btn := Button.new()
		b_btn.custom_minimum_size = Vector2(58, 44)
		_fit_bench_button(b_btn)
		if a != null:
			var parts := a.name.split(" ")
			var short_n := parts[parts.size() - 1] if parts.size() > 1 else a.name
			b_btn.text = "%s\n%s" % [a.position, short_n.left(7)]
		else:
			b_btn.text = "Res %d\n—" % (i + 1)
		b_btn.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
		b_btn.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_MEDIUM))
		b_btn.pressed.connect(func():
			if a != null and selected_field_slot >= 0:
				_assign_athlete_to_starting_slot(a.id, selected_field_slot)
				selected_field_slot = -1
				_pitch.select_slot(-1)
		)
		_bench_container.add_child(b_btn)


## Estreito (celular): os cinco botões do banco repartem a largura e o nome corta, em vez de
## somarem mais que a tela de 360 dp.
func _fit_bench_button(b: Button) -> void:
	b.clip_text = _narrow
	b.custom_minimum_size.x = 0.0 if _narrow else 58.0
	b.size_flags_horizontal = SIZE_EXPAND_FILL if _narrow else SIZE_FILL


func _render_squad_list() -> void:
	for ch in _squad_grid.get_children():
		ch.queue_free()

	var filtered: Array[Athlete] = []
	for a in squad:
		if active_filter == "ALL" or a.position == active_filter:
			filtered.append(a)

	for a in filtered:
		var card := _create_squad_row(a)
		_squad_grid.add_child(card)


func _create_squad_row(a: Athlete) -> PanelContainer:
	var row := PanelContainer.new()
	var is_starter := starting_11.has(a.id)
	var is_bench := bench.has(a.id)
	var is_selected := (a.id == selected_squad_athlete_id)

	var st := StyleBoxFlat.new()
	st.bg_color = Color(DesignTokens.COLOR_ACCENT_YELLOW, 0.45) if is_selected else (DesignTokens.COLOR_BG_HOVER if is_starter else BG_INPUT)
	st.border_width_left = 2 if is_selected else 1
	st.border_width_top = 2 if is_selected else 1
	st.border_width_right = 2 if is_selected else 1
	st.border_width_bottom = 2 if is_selected else 1
	st.border_color = DesignTokens.COLOR_INK if is_selected else (COLOR_OK if is_starter else DesignTokens.COLOR_BORDER_SUBTLE)
	st.corner_radius_top_left = 6
	st.corner_radius_top_right = 6
	st.corner_radius_bottom_left = 6
	st.corner_radius_bottom_right = 6
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", st)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var thumb := PortraitThumb.new(32)
	thumb.set_athlete(a, club_kit)
	thumb.size_flags_vertical = SIZE_SHRINK_CENTER
	hbox.add_child(thumb)

	var pos_lbl := Label.new()
	pos_lbl.text = GameTerms.sector(a.position)
	pos_lbl.tooltip_text = GameTerms.sector(a.position, false)
	pos_lbl.custom_minimum_size = Vector2(28, 0)
	pos_lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	pos_lbl.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_SEMIBOLD))
	pos_lbl.add_theme_color_override("font_color", DesignTokens.color_for_position(a.position))
	hbox.add_child(pos_lbl)

	var name_lbl := Label.new()
	name_lbl.text = a.name
	name_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.tooltip_text = a.name
	name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	name_lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	name_lbl.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_MEDIUM))
	name_lbl.add_theme_color_override("font_color", TEXT_MAIN)
	hbox.add_child(name_lbl)

	var st_badge := Label.new()
	st_badge.text = "TITULAR" if is_starter else ("BANCO" if is_bench else "ELENCO")
	st_badge.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	st_badge.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_SEMIBOLD))
	st_badge.add_theme_color_override("font_color", COLOR_OK if is_starter else TEXT_MUTED)
	hbox.add_child(st_badge)

	# Botão de escalação rápida
	var btn_action := Button.new()
	btn_action.text = "Escalar" if not is_starter else "Trocar"
	btn_action.custom_minimum_size = Vector2(56, 24)
	btn_action.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	btn_action.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_MEDIUM))
	btn_action.pressed.connect(func():
		if selected_field_slot >= 0:
			_assign_athlete_to_starting_slot(a.id, selected_field_slot)
			selected_field_slot = -1
			_pitch.select_slot(-1)
		else:
			selected_squad_athlete_id = a.id
			_update_full_ui()
	)
	hbox.add_child(btn_action)

	return row


func _calculate_team_strength() -> void:
	var total_avg := 0.0
	var def_avg := 0.0
	var mid_avg := 0.0
	var fwd_avg := 0.0
	var cnt_total := 0
	var cnt_def := 0
	var cnt_mid := 0
	var cnt_fwd := 0

	for a_id in starting_11:
		var a := _find_athlete(a_id)
		if a == null: continue
		var a_ovr := 0.0
		for v in a.attributes.values(): a_ovr += float(v)
		a_ovr /= max(1, a.attributes.size())

		total_avg += a_ovr
		cnt_total += 1

		if a.position in ["GK", "DEF"]:
			def_avg += a_ovr
			cnt_def += 1
		elif a.position == "MID":
			mid_avg += a_ovr
			cnt_mid += 1
		else:
			fwd_avg += a_ovr
			cnt_fwd += 1

	_lbl_ovr.text = "OVR %d" % int(total_avg / max(1, cnt_total))
	_lbl_def.text = "DEF %d" % int(def_avg / max(1, cnt_def))
	_lbl_mid.text = "MEI %d" % int(mid_avg / max(1, cnt_mid))
	_lbl_fwd.text = "ATA %d" % int(fwd_avg / max(1, cnt_fwd))


func _show_toast(msg: String, is_error: bool) -> void:
	if _toast_label:
		_toast_label.text = msg
		_toast_label.add_theme_color_override("font_color", ACCENT if is_error else COLOR_OK)


func _on_save_tactics() -> void:
	var active_starters: Array = starting_11.filter(func(id: String): return id != "")
	if active_starters.size() < 11:
		_show_toast("Escalação incompleta: selecione todos os 11 titulares!", true)
		return

	var has_gk := false
	for a_id in active_starters:
		var a := _find_athlete(a_id)
		if a and a.position == "GK":
			has_gk = true
			break
	if not has_gk:
		_show_toast("É obrigatório ter pelo menos 1 Goleiro titular!", true)
		return

	var unique_check := {}
	for a_id in active_starters:
		if unique_check.has(a_id):
			_show_toast("Há atletas duplicados na escalação!", true)
			return
		unique_check[a_id] = true

	var tactics_data := {
		"formation": current_formation,
		"mentality": mentality,
		"defensive_line": defensive_line,
		"passing_style": passing_style,
		"captain_id": captain_id,
		"penalty_taker_id": penalty_id,
		"freekick_taker_id": freekick_id,
		"corner_taker_id": corner_id,
		"sub_rule_stamina": auto_sub_stamina,
		"sub_rule_minute": auto_sub_minute,
		"starting_11": starting_11.duplicate(),
		"bench": bench.duplicate(),
	}

	var game := get_node_or_null("/root/Game")
	var app_node = get_node_or_null("/root/App")
	if game and game.has_club():
		# O Game grava e avisa as outras telas (Início, Pré-jogo) que a escalação mudou.
		if not game.save_tactics(tactics_data):
			_show_toast("Não foi possível salvar a tática.", true)
			return
	elif app_node and app_node.get("backend") != null:
		var w_dict: Dictionary = app_node.backend.load_world()
		var world := World.from_dict(w_dict)
		if current_club and world.clubs.has(current_club.id):
			world.clubs[current_club.id].ext["tactics"] = tactics_data.duplicate(true)
			app_node.backend.save_world(world.to_dict())
		elif not world.clubs.is_empty():
			var first_id = world.clubs.keys()[0]
			world.clubs[first_id].ext["tactics"] = tactics_data.duplicate(true)
			app_node.backend.save_world(world.to_dict())

	_show_toast("Tática salva com sucesso!", false)
	tactics_saved.emit(tactics_data)
