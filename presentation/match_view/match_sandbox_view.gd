extends "res://presentation/match_view/match_view.gd"
## Laboratório / Sandbox de Atributos da Partida.
## Permite selecionar qualquer atleta em campo (por clique ou lista) e alterar
## seus atributos (Velocidade, Físico, Passe, Finalização, Desarme, etc.) em tempo real,
## observando imediatamente o efeito dessas alterações na movimentação e no jogo.

const SANDBOX_PANEL_W := 380.0
const ATTR_DEFINITIONS := [
	{ "id": "pace",        "label": "Velocidade",     "doc": "Aceleração e velocidade máxima de corrida." },
	{ "id": "physical",    "label": "Físico",         "doc": "Proteção de bola, divididas e resistência à carga." },
	{ "id": "passing",     "label": "Passe",          "doc": "Precisão de passe curto e enfiadas." },
	{ "id": "finishing",   "label": "Finalização",    "doc": "Pontaria, calibre e conversão de chutes." },
	{ "id": "tackling",    "label": "Desarme",        "doc": "Bote limpo e interceptação defensiva." },
	{ "id": "positioning", "label": "Posicionamento", "doc": "Ocupação de espaço e posicionamento tático." },
	{ "id": "reflexes",    "label": "Reflexo (GK)",   "doc": "Tempo de reação a finalizações à queima-roupa." },
	{ "id": "elasticity",  "label": "Elasticidade",   "doc": "Alcance e esticada em bolas no ângulo." },
	{ "id": "stamina",     "label": "Estamina",       "doc": "Reserva de energia e resistência ao cansaço." }
]

## Jogador selecionado para inspeção e tweak
var selected_player: MatchPlayer = null

## Atributos originais dos jogadores na partida: { "athlete_id": { "attr_id": float } }
var original_attributes: Dictionary = {}

## Estado da interface do Sandbox
var is_panel_open: bool = true
var _sandbox_layer: CanvasLayer
var _panel_container: PanelContainer
var _reopen_button: Button

## Controles de UI
var _home_team_btn: Button
var _away_team_btn: Button
var _player_option_btn: OptionButton
var _card_num_badge: Label
var _card_name_label: Label
var _card_role_label: Label
var _card_telemetry_label: Label
var _attr_rows: Dictionary = {} # attr_id -> { "slider": HSlider, "val_lbl": Label }
var _current_team_tab: String = "home" # "home" | "away"


func _ready() -> void:
	super._ready()
	_backup_original_attributes()
	_build_sandbox_ui()
	_select_default_player()
	if _hints:
		_hints.text = "[Espaço] pausa · [Tab] painel · [Clique no atleta] selecionar · [. / N] avançar tick · [1-5] vel · [S] voltar ao jogo"
	_layout_hud()


func new_match(rng_seed: int = -1) -> void:
	super.new_match(rng_seed)
	_backup_original_attributes()
	if _player_option_btn:
		_populate_player_list()
		_select_default_player()


func _backup_original_attributes() -> void:
	original_attributes.clear()
	if engine == null or engine.ctx == null:
		return
	for p: MatchPlayer in engine.ctx.all_players:
		if p.athlete:
			original_attributes[p.athlete.id] = p.athlete.attributes.duplicate()


func _select_default_player() -> void:
	if engine == null or engine.ctx == null:
		return
	# Prioriza um jogador de ataque do mandante para demonstrar velocidade e chute
	var chosen: MatchPlayer = null
	for p: MatchPlayer in engine.ctx.home.players:
		if p.role == "FWD":
			chosen = p
			break
	if chosen == null and not engine.ctx.all_players.is_empty():
		chosen = engine.ctx.all_players[0]
	if chosen:
		select_player(chosen)


# ------------------------------------------------------------------ SELEÇÃO E APLICAÇÃO DE ATRIBUTOS
func select_player(player: MatchPlayer) -> void:
	if player == null:
		return
	selected_player = player
	_current_team_tab = "home" if player.team == engine.ctx.home else "away"
	_update_team_tab_buttons()
	_populate_player_list()
	_sync_player_header_ui()
	_sync_all_sliders_ui()
	queue_redraw()


func set_player_attribute(attr_id: String, value: float) -> void:
	if selected_player == null or selected_player.athlete == null:
		return
	var val := clampf(value, 1.0, 99.0)
	selected_player.athlete.attributes[attr_id] = val
	selected_player.attrs[attr_id] = val
	if engine and engine.ctx:
		engine.ctx._refresh_player(selected_player)
	_update_slider_label(attr_id, val)
	queue_redraw()


func apply_preset(preset_type: String) -> void:
	if selected_player == null:
		return
	match preset_type:
		"super_99":
			for item in ATTR_DEFINITIONS:
				set_player_attribute(item.id, 99.0)
			_flash("🚀 %s: Todos atributos em 99!" % selected_player.athlete.name)
		"flash_pace":
			set_player_attribute("pace", 99.0)
			set_player_attribute("stamina", 99.0)
			_flash("⚡ %s: Velocidade Máxima 99!" % selected_player.athlete.name)
		"slow_pace":
			set_player_attribute("pace", 1.0)
			_flash("🐌 %s: Velocidade Reduzida a 1!" % selected_player.athlete.name)
		"striker":
			set_player_attribute("finishing", 99.0)
			set_player_attribute("positioning", 95.0)
			set_player_attribute("pace", 90.0)
			set_player_attribute("physical", 85.0)
			_flash("🎯 %s: Modo Artilheiro Implacável!" % selected_player.athlete.name)
		"defender":
			set_player_attribute("tackling", 99.0)
			set_player_attribute("physical", 99.0)
			set_player_attribute("positioning", 95.0)
			set_player_attribute("pace", 85.0)
			_flash("🛡️ %s: Modo Xerife Insuperável!" % selected_player.athlete.name)
		"wall_gk":
			set_player_attribute("reflexes", 99.0)
			set_player_attribute("elasticity", 99.0)
			set_player_attribute("positioning", 95.0)
			_flash("🧤 %s: Modo Goleiro Muralha!" % selected_player.athlete.name)
		"reset_player":
			if original_attributes.has(selected_player.athlete.id):
				var orig: Dictionary = original_attributes[selected_player.athlete.id]
				for k in orig:
					set_player_attribute(k, orig[k])
				_flash("🔄 %s: Atributos originais restaurados." % selected_player.athlete.name)
		"reset_all":
			for p: MatchPlayer in engine.ctx.all_players:
				if p.athlete and original_attributes.has(p.athlete.id):
					var orig: Dictionary = original_attributes[p.athlete.id]
					for k in orig:
						p.athlete.attributes[k] = orig[k]
						p.attrs[k] = orig[k]
					engine.ctx._refresh_player(p)
			_sync_all_sliders_ui()
			_flash("👥 Todos os 22 atletas restaurados ao padrão original.")
	_sync_all_sliders_ui()


func give_ball_to_selected() -> void:
	if selected_player == null or engine == null or engine.ctx == null:
		return
	var ball := engine.ctx.ball
	ball.holder = selected_player
	ball.pos = selected_player.pos + Vector2(selected_player.radius + 1.0, 0.0)
	ball.vel = Vector2.ZERO
	ball.intended = null
	ball.is_shot = false
	selected_player.possession_frames = 1
	_flash("⚽ Bola entregue para #%d %s!" % [selected_player.shirt, selected_player.athlete.name])
	queue_redraw()


func drop_ball_near_selected() -> void:
	if selected_player == null or engine == null or engine.ctx == null:
		return
	var ball := engine.ctx.ball
	ball.holder = null
	var forward := Vector2(selected_player.team.dir * 18.0, 0.0)
	ball.pos = selected_player.pos + forward
	ball.vel = forward * 0.15
	ball.intended = null
	ball.is_shot = false
	_flash("📍 Bola solta na frente de #%d %s!" % [selected_player.shirt, selected_player.athlete.name])
	queue_redraw()


func step_simulation_tick() -> void:
	if engine == null or engine.is_finished():
		return
	engine.step()
	_update_hud()
	queue_redraw()


# ------------------------------------------------------------------ INPUT E CLIQUE NO CAMPO
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:
				toggle_panel()
				get_viewport().set_input_as_handled()
				return
			KEY_PERIOD, KEY_N:
				step_simulation_tick()
				get_viewport().set_input_as_handled()
				return
			KEY_S:
				get_tree().change_scene_to_file("res://presentation/match_view/match_view.tscn")
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Se clicou na tela do jogo fora da UI do painel
		var p := _pick_player_at_screen_pos(event.position)
		if p:
			select_player(p)
			SfxService.play(SfxService.CLICK)
			get_viewport().set_input_as_handled()
			return

	super._unhandled_input(event)


func _pick_player_at_screen_pos(screen_pos: Vector2) -> MatchPlayer:
	if engine == null or engine.ctx == null:
		return null
	var best_p: MatchPlayer = null
	var best_dist := 36.0 # tolerância de toque/clique em pixels
	for p: MatchPlayer in engine.ctx.all_players:
		var p_scr := _to_screen(p.pos)
		var d := screen_pos.distance_to(p_scr)
		if d < best_dist:
			best_dist = d
			best_p = p
	return best_p


# ------------------------------------------------------------------ LAYOUT E HUD
func _layout_hud() -> void:
	super._layout_hud()
	if _sandbox_layer == null or _panel_container == null:
		return

	var vp := get_viewport_rect().size
	var safe: Vector4 = _settings.safe_margins() if _settings else Vector4.ZERO
	var k := _hud_k
	var panel_w := SANDBOX_PANEL_W

	if is_panel_open:
		_panel_container.visible = true
		_reopen_button.visible = false
		_panel_container.size = Vector2(panel_w, vp.y - safe.y - safe.w - 12.0)
		_panel_container.position = Vector2(vp.x - safe.z - panel_w - 6.0, safe.y + 6.0)

		# Reajusta o campo para caber à esquerda do painel sem nenhuma sobreposição
		var show_bar: bool = _settings.touch_controls_visible() if _settings else false
		var show_hints: bool = _settings.key_hints_visible() if _settings else true
		var bar_h := _touch_bar.bar_height() if show_bar else 0.0
		var top := (HUD_TOP if show_hints else HUD_TOP - 18.0) * k + safe.y
		var bottom := (bar_h + HUD_MSG_H + 6.0) * k + safe.w
		var available_w := vp.x - safe.x - safe.z - 16.0 - panel_w - 12.0
		_fit_pitch(Rect2(safe.x + 8.0, top, available_w, vp.y - top - bottom))
	else:
		_panel_container.visible = false
		_reopen_button.visible = true
		_reopen_button.position = Vector2(vp.x - safe.z - 130.0, safe.y + 10.0)

	queue_redraw()


func toggle_panel() -> void:
	is_panel_open = not is_panel_open
	_layout_hud()


# ------------------------------------------------------------------ DESENHO E DESTAQUE NO CAMPO
func _draw() -> void:
	super._draw()
	if selected_player and is_instance_valid(selected_player):
		_draw_selection_highlight(selected_player)


func _draw_selection_highlight(p: MatchPlayer) -> void:
	var at := _to_screen(p.pos)
	var k := _xf_scale
	var r := (GK_PIECE_R if p.is_gk() else PIECE_R) * k
	var pulse := sin(Time.get_ticks_msec() / 140.0) * 0.5 + 0.5

	# Anel pulsante dourado com borda de tinta
	var ring_r := r + (5.0 + pulse * 4.5) * k
	draw_arc(at, ring_r + 1.6 * k, 0, TAU, 36, Color.BLACK, 2.8 * k)
	draw_arc(at, ring_r, 0, TAU, 36, DesignTokens.COLOR_ACCENT_YELLOW, 2.0 * k)

	# Marcador em seta apontando para a peça
	var tip_y := -r - (8.0 + pulse * 3.5) * k
	var tip := at + Vector2(0, tip_y)
	var p1 := tip + Vector2(-6.0 * k, -9.0 * k)
	var p2 := tip + Vector2(6.0 * k, -9.0 * k)
	var poly := PackedVector2Array([tip, p1, p2])
	draw_colored_polygon(poly, DesignTokens.COLOR_ACCENT_YELLOW)
	draw_polyline(PackedVector2Array([tip, p1, p2, tip]), Color.BLACK, 1.4 * k)

	# Tag de nome e número flutuando acima da peça
	var tag := "#%d %s" % [p.shirt, p.athlete.name]
	var font_size := maxi(int(UiKit.FONT_CAPTION * k), UiKit.FONT_CAPTION)
	var text_w := _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	var tag_pos := at + Vector2(-text_w / 2.0, tip_y - 12.0 * k)
	var bg_rect := Rect2(tag_pos.x - 4.0 * k, tag_pos.y - font_size * 0.85, text_w + 8.0 * k, font_size * 1.25)

	draw_rect(bg_rect, Color(0.0, 0.0, 0.0, 0.75), true)
	draw_rect(bg_rect, DesignTokens.COLOR_ACCENT_YELLOW, false, 1.2 * k)
	draw_string(_font, tag_pos, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


# ------------------------------------------------------------------ TELEMETRIA EM TEMPO REAL
func _process(delta: float) -> void:
	super._process(delta)
	_update_player_telemetry()


func _update_player_telemetry() -> void:
	if _card_telemetry_label == null or selected_player == null:
		return
	var spd := selected_player.vel.length()
	var state_txt := selected_player.state
	var has_ball := engine and engine.ctx and engine.ctx.ball.holder == selected_player
	var ball_txt := "⚽ [POSSE DE BOLA]" if has_ball else "Sem bola"
	_card_telemetry_label.text = "Vel: %.1f (máx: %.1f) | Estado: %s | %s" % [
		spd, selected_player.max_speed, state_txt, ball_txt
	]


# ------------------------------------------------------------------ CONSTRUÇÃO DA UI (SANDBOX)
func _build_sandbox_ui() -> void:
	_sandbox_layer = CanvasLayer.new()
	_sandbox_layer.layer = 20
	add_child(_sandbox_layer)

	# Botão flutuante para reabrir caso o painel seja minimizado
	_reopen_button = Button.new()
	_reopen_button.text = "🧪 Painel Sandbox"
	_reopen_button.custom_minimum_size = Vector2(120, 34)
	_reopen_button.add_theme_stylebox_override("normal", DesignTokens.style_button(true, false))
	_reopen_button.add_theme_stylebox_override("hover", DesignTokens.style_button(true, true))
	_reopen_button.add_theme_stylebox_override("pressed", DesignTokens.style_button(true, false, true))
	_reopen_button.add_theme_color_override("font_color", DesignTokens.COLOR_INK)
	_reopen_button.pressed.connect(toggle_panel)
	_reopen_button.visible = false
	_sandbox_layer.add_child(_reopen_button)

	# Painel Container Principal do Sandbox
	_panel_container = PanelContainer.new()
	_panel_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_container.add_theme_stylebox_override("panel", DesignTokens.style_card(DesignTokens.RADIUS_MD))
	_sandbox_layer.add_child(_panel_container)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	_panel_container.add_child(main_vbox)

	# 1. Header do Painel
	var header_hbox := HBoxContainer.new()
	main_vbox.add_child(header_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "🧪 LABORATÓRIO DE STATUS"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	title_lbl.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	header_hbox.add_child(title_lbl)

	var exit_btn := Button.new()
	exit_btn.text = "Sair"
	exit_btn.custom_minimum_size = Vector2(44, 26)
	exit_btn.tooltip_text = "Voltar para a partida padrão (atalho: S)"
	exit_btn.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	exit_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://presentation/match_view/match_view.tscn"))
	header_hbox.add_child(exit_btn)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.tooltip_text = "Recolher painel (ou pressione TAB)"
	close_btn.add_theme_stylebox_override("normal", DesignTokens.style_button(false, false))
	close_btn.add_theme_stylebox_override("hover", DesignTokens.style_button(false, true))
	close_btn.pressed.connect(toggle_panel)
	header_hbox.add_child(close_btn)

	# 2. Seleção de Time (Mandante / Visitante)
	var team_hbox := HBoxContainer.new()
	team_hbox.add_theme_constant_override("separation", 6)
	main_vbox.add_child(team_hbox)

	_home_team_btn = Button.new()
	_home_team_btn.text = "Mandante"
	_home_team_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_team_btn.pressed.connect(func(): _on_team_tab_pressed("home"))
	team_hbox.add_child(_home_team_btn)

	_away_team_btn = Button.new()
	_away_team_btn.text = "Visitante"
	_away_team_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_away_team_btn.pressed.connect(func(): _on_team_tab_pressed("away"))
	team_hbox.add_child(_away_team_btn)

	# 3. Dropdown com Jogadores do Time Ativo
	_player_option_btn = OptionButton.new()
	_player_option_btn.custom_minimum_size.y = 32
	_player_option_btn.item_selected.connect(_on_player_option_selected)
	main_vbox.add_child(_player_option_btn)

	var hint_lbl := Label.new()
	hint_lbl.text = "💡 Dica: você também pode clicar no jogador no campo!"
	hint_lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	hint_lbl.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
	main_vbox.add_child(hint_lbl)

	# 4. Cartão de Destaque do Jogador Selecionado
	var card := PanelContainer.new()
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = DesignTokens.COLOR_BG_INPUT
	card_sb.border_color = DesignTokens.COLOR_BORDER_BASE
	card_sb.set_border_width_all(1)
	card_sb.set_corner_radius_all(6)
	card_sb.content_margin_left = 10
	card_sb.content_margin_right = 10
	card_sb.content_margin_top = 8
	card_sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", card_sb)
	main_vbox.add_child(card)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 3)
	card.add_child(card_vbox)

	var card_top_hbox := HBoxContainer.new()
	card_top_hbox.add_theme_constant_override("separation", 8)
	card_vbox.add_child(card_top_hbox)

	_card_num_badge = Label.new()
	_card_num_badge.text = "#0"
	_card_num_badge.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
	_card_num_badge.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_BLUE)
	card_top_hbox.add_child(_card_num_badge)

	_card_name_label = Label.new()
	_card_name_label.text = "Nome do Jogador"
	_card_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_name_label.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	_card_name_label.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	card_top_hbox.add_child(_card_name_label)

	_card_role_label = Label.new()
	_card_role_label.text = "FWD"
	_card_role_label.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	_card_role_label.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
	card_top_hbox.add_child(_card_role_label)

	_card_telemetry_label = Label.new()
	_card_telemetry_label.text = "Vel: 0.0 | Estado: IDLE"
	_card_telemetry_label.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	_card_telemetry_label.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
	card_vbox.add_child(_card_telemetry_label)

	# 5. Área Rolável com Sliders de Atributos e Ações Rápidas
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	var scroll_vbox := VBoxContainer.new()
	scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(scroll_vbox)

	# Título da Seção de Atributos
	var attr_sec_lbl := Label.new()
	attr_sec_lbl.text = "ATRIBUTOS DO ATLETA (1 A 99)"
	attr_sec_lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	attr_sec_lbl.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
	scroll_vbox.add_child(attr_sec_lbl)

	# Sliders para cada atributo
	_attr_rows.clear()
	for def in ATTR_DEFINITIONS:
		var row := _create_attr_row(def.id, def.label, def.doc)
		scroll_vbox.add_child(row)

	# Separador visual
	var sep1 := HSeparator.new()
	scroll_vbox.add_child(sep1)

	# Presets Rápidos
	var presets_lbl := Label.new()
	presets_lbl.text = "PRESETS RÁPIDOS"
	presets_lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	presets_lbl.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
	scroll_vbox.add_child(presets_lbl)

	var preset_grid := GridContainer.new()
	preset_grid.columns = 2
	preset_grid.add_theme_constant_override("h_separation", 6)
	preset_grid.add_theme_constant_override("v_separation", 6)
	scroll_vbox.add_child(preset_grid)

	_add_preset_button(preset_grid, "🚀 Turbo 99", "super_99", "Coloca todos os atributos em 99")
	_add_preset_button(preset_grid, "⚡ Flash (Pace 99)", "flash_pace", "Velocidade máxima")
	_add_preset_button(preset_grid, "🐌 Lesma (Pace 1)", "slow_pace", "Velocidade mínima")
	_add_preset_button(preset_grid, "🎯 Artilheiro 99", "striker", "Finalização e posicionamento 99")
	_add_preset_button(preset_grid, "🛡️ Xerife 99", "defender", "Desarme e físico 99")
	_add_preset_button(preset_grid, "🧤 Muralha 99", "wall_gk", "Reflexo e elasticidade 99")
	_add_preset_button(preset_grid, "🔄 Resetar Jogador", "reset_player", "Voltar atributos originais deste atleta")
	_add_preset_button(preset_grid, "👥 Resetar Todos", "reset_all", "Restaurar todos os 22 atletas")

	# Separador visual
	var sep2 := HSeparator.new()
	scroll_vbox.add_child(sep2)

	# Ações de Partida e Bola
	var actions_lbl := Label.new()
	actions_lbl.text = "AÇÕES DE CAMPO & JOGO"
	actions_lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	actions_lbl.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
	scroll_vbox.add_child(actions_lbl)

	var act_grid := GridContainer.new()
	act_grid.columns = 2
	act_grid.add_theme_constant_override("h_separation", 6)
	act_grid.add_theme_constant_override("v_separation", 6)
	scroll_vbox.add_child(act_grid)

	var give_ball_btn := Button.new()
	give_ball_btn.text = "⚽ Dar a Bola"
	give_ball_btn.tooltip_text = "Passa imediatamente a posse de bola para este jogador"
	give_ball_btn.pressed.connect(give_ball_to_selected)
	act_grid.add_child(give_ball_btn)

	var drop_ball_btn := Button.new()
	drop_ball_btn.text = "📍 Bola na Frente"
	drop_ball_btn.tooltip_text = "Coloca a bola solta à frente do jogador para disputa"
	drop_ball_btn.pressed.connect(drop_ball_near_selected)
	act_grid.add_child(drop_ball_btn)

	var step_btn := Button.new()
	step_btn.text = "⏯️ Avançar Tick"
	step_btn.tooltip_text = "Avança 1 frame de física/IA da simulação (atalho: . ou N)"
	step_btn.pressed.connect(step_simulation_tick)
	act_grid.add_child(step_btn)

	var pause_btn := Button.new()
	pause_btn.text = "⏸️ Pausar / Play"
	pause_btn.tooltip_text = "Pausa ou retoma o fluxo do jogo (atalho: Espaço)"
	pause_btn.pressed.connect(func(): _do_action("pause"))
	act_grid.add_child(pause_btn)


func _create_attr_row(attr_id: String, label_text: String, doc: String) -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)
	container.tooltip_text = doc

	var top_box := HBoxContainer.new()
	container.add_child(top_box)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	lbl.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	top_box.add_child(lbl)

	var val_lbl := Label.new()
	val_lbl.text = "50"
	val_lbl.custom_minimum_size.x = 28
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	top_box.add_child(val_lbl)

	var slider := HSlider.new()
	slider.min_value = 1.0
	slider.max_value = 99.0
	slider.step = 1.0
	slider.value = 50.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float): _on_slider_value_changed(attr_id, v))
	container.add_child(slider)

	_attr_rows[attr_id] = { "slider": slider, "val_lbl": val_lbl }
	return container


func _add_preset_button(parent: Control, text: String, preset_id: String, tooltip: String) -> void:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	btn.pressed.connect(func(): apply_preset(preset_id))
	parent.add_child(btn)


# ------------------------------------------------------------------ ATUALIZAÇÃO DA UI
func _on_team_tab_pressed(team_side: String) -> void:
	_current_team_tab = team_side
	_update_team_tab_buttons()
	_populate_player_list()
	if _player_option_btn.item_count > 0:
		_player_option_btn.select(0)
		_on_player_option_selected(0)


func _update_team_tab_buttons() -> void:
	if engine == null or engine.ctx == null:
		return
	var is_home := _current_team_tab == "home"
	_home_team_btn.text = "Mandante: %s" % engine.ctx.home.name
	_away_team_btn.text = "Visitante: %s" % engine.ctx.away.name

	_home_team_btn.add_theme_stylebox_override("normal", DesignTokens.style_button(is_home, false))
	_home_team_btn.add_theme_stylebox_override("hover", DesignTokens.style_button(is_home, true))
	_away_team_btn.add_theme_stylebox_override("normal", DesignTokens.style_button(not is_home, false))
	_away_team_btn.add_theme_stylebox_override("hover", DesignTokens.style_button(not is_home, true))


func _populate_player_list() -> void:
	if _player_option_btn == null or engine == null or engine.ctx == null:
		return
	_player_option_btn.clear()
	var team: MatchTeam = engine.ctx.home if _current_team_tab == "home" else engine.ctx.away
	var idx := 0
	var select_idx := 0
	for p: MatchPlayer in team.players:
		var item_text := "#%02d [%s] %s" % [p.shirt, p.role, p.athlete.name]
		_player_option_btn.add_item(item_text, idx)
		_player_option_btn.set_item_metadata(idx, p)
		if p == selected_player:
			select_idx = idx
		idx += 1
	_player_option_btn.select(select_idx)


func _on_player_option_selected(idx: int) -> void:
	var p: MatchPlayer = _player_option_btn.get_item_metadata(idx)
	if p:
		select_player(p)


func _sync_player_header_ui() -> void:
	if selected_player == null:
		return
	_card_num_badge.text = "#%d" % selected_player.shirt
	_card_name_label.text = selected_player.athlete.name
	_card_role_label.text = "%s (%s)" % [
		selected_player.role,
		"Mandante" if selected_player.team == engine.ctx.home else "Visitante"
	]


func _sync_all_sliders_ui() -> void:
	if selected_player == null or selected_player.athlete == null:
		return
	for def in ATTR_DEFINITIONS:
		var val := float(selected_player.athlete.attributes.get(def.id, 50.0))
		if _attr_rows.has(def.id):
			var data: Dictionary = _attr_rows[def.id]
			var slider: HSlider = data.slider
			slider.set_value_no_signal(val)
			_update_slider_label(def.id, val)


func _on_slider_value_changed(attr_id: String, value: float) -> void:
	set_player_attribute(attr_id, value)


func _update_slider_label(attr_id: String, val: float) -> void:
	if not _attr_rows.has(attr_id):
		return
	var val_lbl: Label = _attr_rows[attr_id].val_lbl
	val_lbl.text = str(int(val))

	# Cores de leitura rápida do nível
	if val >= 80.0:
		val_lbl.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_EMERALD)
	elif val >= 60.0:
		val_lbl.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_PRIMARY)
	else:
		val_lbl.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_RED)
