class_name TacticalPitch
extends Control
## Campinho Tático Interativo (Godot 4):
##   - Renderiza gramado estilizado com faixas e marcações oficiais de futebol;
##   - Posiciona os 11 slots titulares baseados nas coordenadas da formação (data/formations/*.json);
##   - Animação suave (Tween) de reposicionamento ao alternar formações;
##   - Emite sinais de seleção, troca e atribuição de papéis (Capitão, Pênaltis, Faltas).

signal slot_clicked(slot_index: int, athlete_id: String)
signal slot_right_clicked(slot_index: int, athlete_id: String)

const PITCH_BG_A := Color("#16482d")
const PITCH_BG_B := Color("#1a5435")
const LINE_COLOR := Color(1.0, 1.0, 1.0, 0.45)
const LINE_WIDTH := 2.0
const BORDER_RADIUS := 12.0
const PORTRAIT_SIZE := 40.0

## Slots da formação ativa: [{role, function, x, y, athlete_id, athlete_data}]
## role = setor do motor (GK/DEF/MID/FWD); function = função da vaga (ZAG, LE, VOL...; GameTerms).
var slots: Array = []
var formation_id: String = "4-3-3"
var selected_slot_index: int = -1
var captain_id: String = ""
var penalty_taker_id: String = ""
var freekick_taker_id: String = ""
var club_kit: Dictionary = {}

## Nós visuais dos 11 jogadores no campo
var _slot_nodes: Array[Control] = []


func _ready() -> void:
	custom_minimum_size = Vector2(480, 580)
	clip_contents = true
	resized.connect(_reposition_slots)


func setup_formation(f_id: String, f_slots: Array, kit: Dictionary = {}) -> void:
	formation_id = f_id
	club_kit = kit
	slots.clear()
	
	for s in f_slots:
		slots.append({
			"role": str(s.get("role", "MID")),
			"function": str(s.get("function", "")),
			"x": float(s.get("x", 0.5)),
			"y": float(s.get("y", 0.5)),
			"athlete_id": str(s.get("athlete_id", "")),
			"athlete_data": s.get("athlete_data", null),
		})
	
	_rebuild_slot_nodes()


func set_slot_athlete(index: int, athlete: Athlete) -> void:
	if index < 0 or index >= slots.size():
		return
	if athlete != null:
		slots[index]["athlete_id"] = athlete.id
		slots[index]["athlete_data"] = athlete
	else:
		slots[index]["athlete_id"] = ""
		slots[index]["athlete_data"] = null
	
	_update_slot_visual(index)


func set_special_roles(cap: String, pen: String, fk: String) -> void:
	captain_id = cap
	penalty_taker_id = pen
	freekick_taker_id = fk
	for i in range(slots.size()):
		_update_slot_visual(i)


func select_slot(index: int) -> void:
	selected_slot_index = index
	for i in range(slots.size()):
		_update_slot_visual(i)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	
	# Gramado com cantos arredondados
	draw_rect(rect, PITCH_BG_A)
	
	# Faixas de corte da grama
	var stripes := 8
	var stripe_h := rect.size.y / stripes
	for i in range(stripes):
		if i % 2 == 1:
			draw_rect(Rect2(0, i * stripe_h, rect.size.x, stripe_h), PITCH_BG_B)

	# Borda externa do campo com margem
	var m := 16.0
	var p_rect := Rect2(m, m, rect.size.x - m * 2, rect.size.y - m * 2)
	draw_rect(p_rect, LINE_COLOR, false, LINE_WIDTH)

	# Linha do meio campo
	var mid_y := p_rect.position.y + p_rect.size.y * 0.5
	draw_line(Vector2(p_rect.position.x, mid_y), Vector2(p_rect.end.x, mid_y), LINE_COLOR, LINE_WIDTH)

	# Círculo central
	var center := Vector2(p_rect.position.x + p_rect.size.x * 0.5, mid_y)
	draw_arc(center, p_rect.size.x * 0.16, 0, TAU, 48, LINE_COLOR, LINE_WIDTH)
	draw_circle(center, 3.5, LINE_COLOR)

	# Grande área superior (defesa adversária) e inferior (nossa defesa)
	_draw_penalty_area(p_rect, true)
	_draw_penalty_area(p_rect, false)


func _draw_penalty_area(p: Rect2, top: bool) -> void:
	var area_w := p.size.x * 0.54
	var area_h := p.size.y * 0.16
	var x0 := p.position.x + (p.size.x - area_w) * 0.5
	var y0 := p.position.y if top else p.end.y - area_h
	
	# Grande área
	draw_rect(Rect2(x0, y0, area_w, area_h), LINE_COLOR, false, LINE_WIDTH)
	
	# Pequena área
	var goal_w := p.size.x * 0.28
	var goal_h := p.size.y * 0.06
	var gx0 := p.position.x + (p.size.x - goal_w) * 0.5
	var gy0 := p.position.y if top else p.end.y - goal_h
	draw_rect(Rect2(gx0, gy0, goal_w, goal_h), LINE_COLOR, false, LINE_WIDTH)

	# Ponto do pênalti
	var pen_y := p.position.y + p.size.y * 0.11 if top else p.end.y - p.size.y * 0.11
	draw_circle(Vector2(p.position.x + p.size.x * 0.5, pen_y), 3.0, LINE_COLOR)

	# Arco da grande área
	var arc_center := Vector2(p.position.x + p.size.x * 0.5, pen_y)
	var start_a := 0.2 * PI if top else 1.2 * PI
	var end_a := 0.8 * PI if top else 1.8 * PI
	draw_arc(arc_center, p.size.x * 0.14, start_a, end_a, 24, LINE_COLOR, LINE_WIDTH)


func _rebuild_slot_nodes() -> void:
	for node in _slot_nodes:
		node.queue_free()
	_slot_nodes.clear()

	for i in range(slots.size()):
		var slot_ctrl := _create_player_token(i)
		add_child(slot_ctrl)
		_slot_nodes.append(slot_ctrl)
	
	_reposition_slots()


func _create_player_token(index: int) -> Control:
	var token := PanelContainer.new()
	token.custom_minimum_size = Vector2(80, 80)
	token.mouse_filter = MOUSE_FILTER_STOP
	token.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			var slot_data: Dictionary = slots[index]
			if ev.button_index == MOUSE_BUTTON_LEFT:
				slot_clicked.emit(index, str(slot_data.get("athlete_id", "")))
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				slot_right_clicked.emit(index, str(slot_data.get("athlete_id", "")))
	)
	
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	token.add_child(vbox)

	# Badge de posição e roles (C, P, F)
	var badge_hbox := HBoxContainer.new()
	badge_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	badge_hbox.add_theme_constant_override("separation", 2)
	vbox.add_child(badge_hbox)

	var role_lbl := Label.new()
	role_lbl.name = "RoleLabel"
	role_lbl.text = _slot_label(slots[index])
	role_lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	role_lbl.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_SEMIBOLD))
	role_lbl.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_BLUE)
	badge_hbox.add_child(role_lbl)

	var spec_lbl := Label.new()
	spec_lbl.name = "SpecialLabel"
	spec_lbl.text = ""
	spec_lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	spec_lbl.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_RED)
	badge_hbox.add_child(spec_lbl)

	# Retrato do atleta vestido com o uniforme do clube (mesmo da tela Elenco)
	var avatar_box := CenterContainer.new()
	avatar_box.name = "AvatarBox"
	avatar_box.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_child(avatar_box)

	var thumb := PortraitThumb.new(PORTRAIT_SIZE)
	thumb.name = "Portrait"
	avatar_box.add_child(thumb)

	# Nome do atleta
	var name_lbl := Label.new()
	name_lbl.name = "NameLabel"
	name_lbl.text = "Vazio"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	name_lbl.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_MEDIUM))
	name_lbl.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	vbox.add_child(name_lbl)

	# Overall rating
	var ovr_lbl := Label.new()
	ovr_lbl.name = "OvrLabel"
	ovr_lbl.text = "--"
	ovr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ovr_lbl.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	ovr_lbl.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_SEMIBOLD))
	ovr_lbl.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
	vbox.add_child(ovr_lbl)

	_update_slot_visual(index, token)
	return token


func _update_slot_visual(index: int, token_override: Control = null) -> void:
	if index < 0 or index >= _slot_nodes.size():
		return
	
	var token: Control = token_override if token_override != null else _slot_nodes[index]
	var s: Dictionary = slots[index]
	var athlete: Athlete = s.get("athlete_data")
	var is_selected: bool = (index == selected_slot_index)

	# Estilo do Token: carta de papel com contorno de tinta; vaga vazia translúcida; selecionada
	# com contorno amarelo grosso.
	var style := StyleBoxFlat.new()
	style.bg_color = DesignTokens.COLOR_BG_CARD if athlete != null else Color(DesignTokens.COLOR_PAPER, 0.55)
	style.set_border_width_all(3 if is_selected else DesignTokens.BORDER_WIDTH)
	style.border_color = DesignTokens.COLOR_ACCENT_YELLOW if is_selected else (DesignTokens.COLOR_INK if athlete != null else Color(DesignTokens.COLOR_INK, 0.35))
	style.set_corner_radius_all(int(DesignTokens.RADIUS_MD))
	style.set_content_margin_all(4)
	if athlete != null:
		style.shadow_color = DesignTokens.COLOR_INK
		style.shadow_size = 1
		style.shadow_offset = DesignTokens.SHADOW_OFFSET
	token.add_theme_stylebox_override("panel", style)

	# Labels
	var role_lbl: Label = token.find_child("RoleLabel", true, false)
	if role_lbl:
		role_lbl.text = _slot_label(s)
		role_lbl.add_theme_color_override("font_color", DesignTokens.color_for_position(str(s["role"])))

	var spec_lbl: Label = token.find_child("SpecialLabel", true, false)
	if spec_lbl:
		var spec_tags: Array = []
		var a_id: String = str(s.get("athlete_id", ""))
		if a_id != "":
			if a_id == captain_id: spec_tags.append("C")
			if a_id == penalty_taker_id: spec_tags.append("P")
			if a_id == freekick_taker_id: spec_tags.append("F")
		spec_lbl.text = "[%s]" % "".join(spec_tags) if not spec_tags.is_empty() else ""

	var name_lbl: Label = token.find_child("NameLabel", true, false)
	var ovr_lbl: Label = token.find_child("OvrLabel", true, false)
	var thumb: PortraitThumb = token.find_child("Portrait", true, false)
	if thumb:
		thumb.set_athlete(athlete, club_kit)
		thumb.modulate.a = 1.0 if athlete != null else 0.35

	if athlete != null:
		if name_lbl:
			var parts := athlete.name.split(" ")
			name_lbl.text = parts[parts.size() - 1] if parts.size() > 1 else athlete.name
		if ovr_lbl:
			var avg := 0.0
			var cnt := 0
			for val in athlete.attributes.values():
				avg += float(val)
				cnt += 1
			ovr_lbl.text = "OVR %d" % int(avg / max(1, cnt))
	else:
		if name_lbl: name_lbl.text = "—"
		if ovr_lbl: ovr_lbl.text = "--"


func _reposition_slots() -> void:
	if _slot_nodes.is_empty():
		return

	var m := 30.0
	var usable_w := size.x - m * 2
	var usable_h := size.y - m * 2

	for i in range(min(slots.size(), _slot_nodes.size())):
		var s: Dictionary = slots[i]
		var token: Control = _slot_nodes[i]
		
		# Coordenadas no campo vertical (Goleiro embaixo, Ataque no topo):
		# s.x no JSON do campo (0=linha de fundo própria, 1=adversária) -> Y vertical invertido (1.0 - x)
		# s.y no JSON (0=esquerda, 1=direita) -> X horizontal
		var target_x := m + float(s["y"]) * usable_w - token.custom_minimum_size.x * 0.5
		var target_y := m + (1.0 - float(s["x"]) * 1.6) * usable_h - token.custom_minimum_size.y * 0.5
		
		# Limita dentro do campo
		target_x = clampf(target_x, 10.0, size.x - token.custom_minimum_size.x - 10.0)
		target_y = clampf(target_y, 10.0, size.y - token.custom_minimum_size.y - 10.0)
		
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(token, "position", Vector2(target_x, target_y), 0.28)


## Rótulo da vaga: a função ("ZAG", "VOL"...) ou, sem ela, o setor ("DEF").
func _slot_label(s: Dictionary) -> String:
	var fn := str(s.get("function", ""))
	return GameTerms.role(fn) if fn != "" else GameTerms.sector(str(s.get("role", "MID")))
