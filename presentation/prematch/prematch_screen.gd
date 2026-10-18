class_name PrematchScreen
extends ScreenBase
## P01 · Pré-jogo: última parada antes de jogar, como o "pre-match hub" dos jogos de gestão.
## Reúne num lugar só o confronto, a força comparada, os alertas (escalação inválida bloqueia o
## JOGAR e diz o motivo), a consequência do jogo antes da decisão (quem ganha dia de carreira e
## quem faz aniversário no oficial; amistoso não envelhece) e a mentalidade em 7 passos.
## No celular (compacto) o essencial cabe sem rolar: confronto, força e mentalidade; alertas, o que o
## jogo muda e a escalação ficam numa janela (botão de detalhes ao lado do JOGAR). Escalação inválida
## continua aparecendo na tela, porque bloqueia o JOGAR.
## params: kind ("official" | "friendly"), opponent (chave do adversário, GameStore.opponent()).

const TWO_COLUMNS_MIN := 860.0

var _kind := GameStore.KIND_FRIENDLY
var _opponent: Dictionary = {}
var _play: Button
var _cols := 0
var _compact := false


func setup(p_route: String, p_params: Dictionary) -> void:
	super.setup(p_route, p_params)
	_kind = str(p_params.get("kind", GameStore.KIND_FRIENDLY))


func screen_title() -> String:
	return tr("PREJOGO_TITULO_OFICIAL") if _kind == GameStore.KIND_OFFICIAL else tr("PREJOGO_TITULO")


func refresh() -> void:
	var g := game()
	if g == null or not g.has_club():
		show_empty("clube", tr("INICIO_SEM_CLUBE_TITULO"), tr("INICIO_SEM_CLUBE_TEXTO"))
		return
	_opponent = _resolve_opponent(g)
	if _opponent.is_empty():
		show_error(tr("ERRO_SEM_ADVERSARIO"))
		return
	if _kind == GameStore.KIND_OFFICIAL and not bool(g.official_status().get("available", false)):
		show_empty("calendario", tr("PREJOGO_OFICIAL_JOGADO"), tr("PREJOGO_OFICIAL_JOGADO_TEXTO"),
			tr("INICIO_JOGAR_AMISTOSO"), func() -> void: go("modes"))
		return
	_rebuild()
	show_ready()


func _resolve_opponent(g: GameStore) -> Dictionary:
	if _kind == GameStore.KIND_OFFICIAL:
		return g.official_opponent()
	var key := str(params.get("opponent", ""))
	if key != "":
		return g.opponent(key)
	var opps := g.friendly_opponents()
	return opps[0] if not opps.is_empty() else {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and content != null and state == State.READY:
		if (2 if size.x >= TWO_COLUMNS_MIN else 1) != _cols or (size.x < AppShell.COMPACT_MAX) != _compact:
			_rebuild()


func _rebuild() -> void:
	ScreenBase.clear(content)
	var g := game()
	_cols = 2 if size.x >= TWO_COLUMNS_MIN else 1
	_compact = size.x < AppShell.COMPACT_MAX
	var body := UiKit.vbox(DesignTokens.SPACING_MD if _compact else DesignTokens.SPACING_LG)
	content.add_child(UiKit.scroll(body))
	var left := body
	var right := body
	if _cols == 2:
		var row := UiKit.hbox(DesignTokens.SPACING_LG)
		left = UiKit.vbox(DesignTokens.SPACING_LG)
		right = UiKit.vbox(DesignTokens.SPACING_LG)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(left)
		row.add_child(right)
		body.add_child(row)
	var problems := g.lineup_problems()
	if _compact and not problems.is_empty():
		left.add_child(_alerts_card(g, problems))
	left.add_child(_matchup_card(g))
	left.add_child(_strength_card(g))
	left.add_child(_mentality_card(g))
	if not _compact:
		right.add_child(_alerts_card(g, problems))
		right.add_child(_consequences_card(g))
		right.add_child(_lineup_card(g))
	content.add_child(_actions(problems))


func _matchup_card(g: GameStore) -> Control:
	var club := g.club()
	var parts := UiKit.titled_card("" if _compact else tr("TIPO_" + _kind.to_upper()))
	var v: VBoxContainer = parts[1]
	var row := UiKit.hbox(DesignTokens.SPACING_MD)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(ClubCrest.for_club(club, 60))
	var mid := UiKit.vbox(2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _compact:
		# No lugar da faixa "AMISTOSO"/"OFICIAL": o ícone do tipo de jogo (o nome fica na dica).
		var kind_icon := GameIcons.rect(GameIcons.KIND.get(_kind, "amistoso"), 30)
		kind_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		kind_icon.tooltip_text = tr("TIPO_" + _kind.to_upper())
		kind_icon.mouse_filter = Control.MOUSE_FILTER_PASS
		mid.add_child(kind_icon)
	# No celular os escudos deixam ~160 px lógicos para as siglas: um degrau abaixo na escala.
	var names := UiKit.title("%s  ×  %s" % [club.short_name, _opponent.short_name],
		UiKit.FONT_TITLE if _compact else UiKit.FONT_DISPLAY)
	names.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.wrap(names)
	mid.add_child(names)
	var sub := UiKit.label("%s  —  %s" % [club.name, _opponent.name], UiKit.FONT_SMALL, UiKit.MUTED, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(sub)
	row.add_child(mid)
	# Mesmas cores do seu time: o visitante joga com a segunda cor (como na partida).
	var their: Color = _opponent.color
	var their2: Color = _opponent.secondary
	if GameStore._color_distance(club.primary_color(), their) < GameStore.COLOR_CLASH:
		their = _opponent.secondary
		their2 = _opponent.color
	row.add_child(ClubCrest.for_colors(their, their2, str(_opponent.short_name), 60))
	v.add_child(row)
	return parts[0]


func _strength_card(g: GameStore) -> Control:
	var parts := UiKit.titled_card(tr("PREJOGO_FORCA"))
	var v: VBoxContainer = parts[1]
	var mine := GameStore.strength(g.starters())
	var theirs: Dictionary = _opponent.strength
	var my_color := g.club().primary_color()
	var their_color: Color = _opponent.color
	if GameStore._color_distance(my_color, their_color) < GameStore.COLOR_CLASH:
		their_color = _opponent.secondary
	for row in [["ovr", "PREJOGO_OVR"], ["def", "POS_DEF_CURTA"], ["mid", "POS_MID_CURTA"], ["fwd", "POS_FWD_CURTA"]]:
		v.add_child(CompareBar.make(tr(row[1]), maxf(mine[row[0]], 0), maxf(theirs[row[0]], 0), my_color, their_color))
	return parts[0]


## Mentalidade em 7 passos: o nome do nível em destaque, a descrição e ‹ › para mudar.
func _mentality_card(g: GameStore) -> Control:
	var parts := UiKit.titled_card(tr("PREJOGO_MENTALIDADE"))
	var v: VBoxContainer = parts[1]
	var cur := str(g.tactics().get("mentality", "equilibrado"))
	var idx := maxi(GameTerms.MENTALITIES.find(cur), 0)
	var row := UiKit.hbox(DesignTokens.SPACING_SM)
	var minus := UiKit.icon_only(UiKit.button("", "secondary", "defensivo", 44))
	minus.custom_minimum_size.x = 48
	minus.tooltip_text = tr("PREJOGO_MAIS_DEFENSIVO")
	minus.disabled = idx == 0
	minus.pressed.connect(func() -> void: _set_mentality(idx - 1))
	var plus := UiKit.icon_only(UiKit.button("", "secondary", "ofensivo", 44))
	plus.custom_minimum_size.x = 48
	plus.tooltip_text = tr("PREJOGO_MAIS_OFENSIVO")
	plus.disabled = idx == GameTerms.MENTALITIES.size() - 1
	plus.pressed.connect(func() -> void: _set_mentality(idx + 1))
	var level := UiKit.title(GameTerms.mentality(cur), UiKit.FONT_H2)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(minus)
	row.add_child(level)
	row.add_child(plus)
	v.add_child(row)
	var pips := UiKit.hbox(DesignTokens.SPACING_XS)
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in GameTerms.MENTALITIES.size():
		var pip := Button.new()
		pip.custom_minimum_size = Vector2(30, 14)
		pip.tooltip_text = GameTerms.mentality(GameTerms.MENTALITIES[i])
		pip.focus_mode = Control.FOCUS_NONE
		UiKit.style_button(pip, "primary" if i == idx else "secondary")
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			DesignTokens.compact_margins(pip.get_theme_stylebox(st), 0, 0)
		var target := i
		pip.pressed.connect(func() -> void: _set_mentality(target))
		pips.add_child(pip)
	v.add_child(pips)
	var hint := UiKit.hint(GameTerms.mentality(cur, true))
	if _compact:
		# A lâmpada sobe para a linha do título (uma linha a menos); o texto abre embaixo, como antes.
		var head := UiKit.hbox(DesignTokens.SPACING_SM)
		var section: Control = v.get_child(0)
		v.remove_child(section)
		head.add_child(section)
		head.add_child(UiKit.spacer())
		var bulb: Control = hint.get_child(0)
		var text: Control = hint.get_child(1)
		hint.remove_child(bulb)
		hint.remove_child(text)
		head.add_child(bulb)
		v.add_child(head)
		v.move_child(head, 0)
		v.add_child(text)
		hint.queue_free()
	else:
		v.add_child(hint)
	return parts[0]


func _set_mentality(i: int) -> void:
	var g := game()
	if g and i >= 0 and i < GameTerms.MENTALITIES.size():
		g.set_mentality(GameTerms.MENTALITIES[i])
		_rebuild()


func _alerts_card(g: GameStore, problems: PackedStringArray) -> Control:
	var alerts: Array = []
	for p in problems:
		alerts.append({"icon": "bloqueado", "text": p, "error": true})
	var bench: Array = g.tactics().get("bench", [])
	if bench.is_empty():
		alerts.append({"icon": "substituicao", "text": tr("PREJOGO_ALERTA_SEM_BANCO"), "error": false})
	var parts := UiKit.titled_card(tr("PREJOGO_ALERTAS"))
	var v: VBoxContainer = parts[1]
	if alerts.is_empty():
		var ok := UiKit.hbox(DesignTokens.SPACING_SM)
		ok.add_child(UiKit.icon("confirmar", 24))
		ok.add_child(UiKit.label(tr("PREJOGO_TUDO_CERTO"), UiKit.FONT_BODY, UiKit.GREEN, true))
		v.add_child(ok)
	for a in alerts:
		var row := UiKit.hbox(DesignTokens.SPACING_SM)
		row.add_child(UiKit.icon(a.icon, 24))
		var l := UiKit.label(a.text, UiKit.FONT_BODY, UiKit.RED if a.error else UiKit.INK, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		v.add_child(row)
	return parts[0]


## O que este jogo muda, antes da decisão.
func _consequences_card(g: GameStore) -> Control:
	var parts := UiKit.titled_card(tr("PREJOGO_NESTE_JOGO"))
	var v: VBoxContainer = parts[1]
	if _kind != GameStore.KIND_OFFICIAL:
		v.add_child(UiKit.label(tr("MODOS_REGRA_TEXTO"), UiKit.FONT_BODY, UiKit.INK, true))
		return parts[0]
	v.add_child(UiKit.label(tr("PREJOGO_OFICIAL_TABELA"), UiKit.FONT_BODY, UiKit.INK, true))
	if not g.is_enabled("career_aging"):
		return parts[0]
	var starters: Array = g.starters().filter(func(a): return a != null)
	v.add_child(UiKit.label(tr("PREJOGO_DIAS") % starters.size(), UiKit.FONT_BODY, UiKit.INK, true))
	for a: Athlete in starters:
		var c := g.career(a)
		if int(c.days_in_year) == int(c.days_per_year) - 1:
			var row := UiKit.hbox(DesignTokens.SPACING_SM)
			row.add_child(UiKit.icon("evolucao", 22))
			row.add_child(UiKit.label(tr("PREJOGO_ANIVERSARIO") % [a.name, floori(float(c.age)) + 1], UiKit.FONT_BODY, UiKit.INK, true))
			v.add_child(row)
	v.add_child(UiKit.hint(tr("PREJOGO_RESERVAS_NAO_ENVELHECEM")))
	return parts[0]


func _lineup_card(g: GameStore) -> Control:
	var t := g.tactics()
	var parts := UiKit.titled_card(tr("PREJOGO_ESCALACAO"))
	var v: VBoxContainer = parts[1]
	var starters: Array = g.starters()
	var count := starters.filter(func(a): return a != null).size()
	v.add_child(UiKit.label(tr("PREJOGO_ESCALACAO_RESUMO") % [str(t.get("formation", GameStore.DEFAULT_FORMATION)),
		count, (t.get("bench", []) as Array).size()], UiKit.FONT_BODY))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", DesignTokens.SPACING_XS)
	flow.add_theme_constant_override("v_separation", DesignTokens.SPACING_XS)
	var kit := g.kit()
	for a in starters:
		if a is Athlete:
			flow.add_child(UiKit.athlete_chip(a, kit))
	v.add_child(flow)
	return parts[0]


func _actions(problems: PackedStringArray) -> Control:
	var row := UiKit.hbox(DesignTokens.SPACING_SM)
	var adjust := UiKit.button(tr("PREJOGO_AJUSTAR"), "secondary", "tatica", 56)
	adjust.pressed.connect(func() -> void: go("lineup"))
	row.add_child(adjust)
	if _compact:
		var more := UiKit.button(tr("PREJOGO_DETALHES"), "secondary", "estatisticas", 56)
		more.name = "Details"
		more.pressed.connect(_open_details)
		row.add_child(more)
	_play = UiKit.button(tr("UI_JOGAR"), "primary", "jogar", 56)
	_play.name = "Play"
	_play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not problems.is_empty():
		_play.disabled = true
		_play.tooltip_text = problems[0]
	_play.pressed.connect(_on_play)
	row.add_child(_play)
	return row


## Celular: alertas, o que o jogo muda e a escalação numa janela rolável.
func _open_details() -> void:
	var g := game()
	if g == null or router() == null:
		return
	# Seções planas (sem cartão dentro da janela): cabe inteiro até em celular de 640 px de altura.
	var v := UiKit.vbox(DesignTokens.SPACING_SM)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sections := [["pendencia", _alerts_card(g, g.lineup_problems())], ["calendario", _consequences_card(g)],
		["tatica", _lineup_card(g)]]
	for i in sections.size():
		if i > 0:
			v.add_child(UiKit.separator())
		v.add_child(_flat_section(sections[i][0], sections[i][1]))
	var scroll := UiKit.scroll(v)
	router().overlays.modal(tr("PREJOGO_DETALHES"), "", [
		{"label": tr("UI_ENTENDI"), "kind": "primary", "cancel": true}], "estatisticas", scroll)


## Tira o conteúdo de um cartão titulado e o devolve como seção plana: ícone + título pequeno.
func _flat_section(icon_id: String, card: Control) -> Control:
	var inner: VBoxContainer = card.get_child(0)
	var band: Control = inner.get_child(0)
	var heading := str((band.get_child(0) as Label).text)
	inner.remove_child(band)
	band.queue_free()
	card.remove_child(inner)
	card.queue_free()
	inner.add_theme_constant_override("separation", DesignTokens.SPACING_XS)
	var head := UiKit.hbox(DesignTokens.SPACING_XS)
	head.add_child(UiKit.icon(icon_id, 22))
	head.add_child(UiKit.title(heading.to_upper(), UiKit.FONT_BODY))
	inner.add_child(head)
	inner.move_child(head, 0)
	return inner


func _on_play() -> void:
	if _kind == GameStore.KIND_OFFICIAL and router():
		router().overlays.confirm(tr("PREJOGO_CONFIRMAR_TITULO"), tr("PREJOGO_CONFIRMAR_TEXTO"),
			tr("UI_JOGAR"), _start)
		return
	_start()


func _start() -> void:
	var g := game()
	_play.disabled = true   # trava: impede partida dupla
	var res := g.prepare_match(_kind, _opponent)
	if not bool(res.get("ok", false)):
		_play.disabled = false
		if router():
			router().overlays.toast(str((res.get("errors", [""]) as Array)[0]), "error")
		return
	go("match")
