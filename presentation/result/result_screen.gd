class_name ResultScreen
extends ScreenBase
## P07 · Resultado: fecha o jogo com placar, números, lances e tudo o que mudou no clube (dias de
## carreira, aniversários, aposentadorias), com sinal e ícone. Celebração proporcional: vitória
## ganha a faixa amarela; derrota, um texto de apoio. Concluir volta ao Início.
## Fonte: params.raw (resultado do histórico), Game.last_report (partida que acabou) ou, sem
## nenhum dos dois, a partida mais recente do histórico.

const TWO_COLUMNS_MIN := 860.0

var _report: Dictionary = {}
var _cols := 0


func refresh() -> void:
	var g := game()
	_report = _load_report(g)
	if _report.is_empty():
		show_empty("historico", tr("RESULTADO_VAZIO_TITULO"), tr("RESULTADO_VAZIO_TEXTO"),
			tr("UI_VOLTAR_INICIO"), func() -> void: go("home"))
		return
	_rebuild()
	show_ready()


func _load_report(g: GameStore) -> Dictionary:
	if g == null:
		return {}
	var raw: Dictionary = params.get("raw", {})
	if raw.is_empty() and not g.last_report.is_empty():
		return g.last_report
	if raw.is_empty():
		var recent := g.recent_results(1)
		raw = recent[0].raw if not recent.is_empty() else {}
	if raw.is_empty():
		return {}
	return {"result": raw, "kind": str(raw.get("kind", "")), "summary": GameStore.summarize(raw, g.club().id if g.club() else ""), "career": {}}


## Voltar depois do jogo leva ao Início (a partida já acabou: não volta ao pré-jogo).
func handle_back() -> bool:
	_finish()
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and content != null and state == State.READY:
		if (2 if size.x >= TWO_COLUMNS_MIN else 1) != _cols:
			_rebuild()


func _rebuild() -> void:
	ScreenBase.clear(content)
	_cols = 2 if size.x >= TWO_COLUMNS_MIN else 1
	var result: Dictionary = _report.result
	var sum: Dictionary = _report.summary
	var body := UiKit.vbox(DesignTokens.SPACING_LG)
	content.add_child(UiKit.scroll(body))
	body.add_child(_score_card(result, sum))
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
	left.add_child(_stats_card(result, sum))
	right.add_child(_highlights_card(result))
	right.add_child(_career_card())
	content.add_child(_actions())


func _score_card(result: Dictionary, sum: Dictionary) -> Control:
	var tone: Dictionary = {
		"win": {"key": "RESULTADO_VITORIA", "fill": DesignTokens.COLOR_ACCENT_YELLOW, "text": "RESULTADO_VITORIA_TEXTO"},
		"draw": {"key": "RESULTADO_EMPATE", "fill": DesignTokens.COLOR_BG_CARD, "text": "RESULTADO_EMPATE_TEXTO"},
		"loss": {"key": "RESULTADO_DERROTA", "fill": DesignTokens.COLOR_BG_CARD, "text": "RESULTADO_DERROTA_TEXTO"},
	}[str(sum.outcome)]
	var card := UiKit.card(tone.fill)
	var v := UiKit.vbox(DesignTokens.SPACING_SM)
	card.add_child(v)
	var top := UiKit.hbox(DesignTokens.SPACING_SM)
	var kind := str(result.get("kind", "friendly"))
	top.add_child(UiKit.chip(tr("TIPO_" + kind.to_upper()), UiKit.BLUE, GameIcons.KIND.get(kind, "amistoso")))
	top.add_child(UiKit.spacer())
	top.add_child(UiKit.label(tr("PARTIDA_FIM"), UiKit.FONT_SMALL, UiKit.MUTED))
	v.add_child(top)
	var row := UiKit.hbox(DesignTokens.SPACING_MD)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var home: Dictionary = result.get("home", {})
	var away: Dictionary = result.get("away", {})
	row.add_child(_crest_for(str(home.get("club_id", "")), str(home.get("name", ""))))
	var score := UiKit.title("%d × %d" % [int(home.get("goals", 0)), int(away.get("goals", 0))], 48)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(score)
	row.add_child(_crest_for(str(away.get("club_id", "")), str(away.get("name", ""))))
	v.add_child(row)
	var names := UiKit.label("%s  —  %s" % [home.get("name", ""), away.get("name", "")], UiKit.FONT_BODY, UiKit.INK, true)
	names.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(names)
	var so: Array = sum.get("shootout", [])
	if not so.is_empty():
		var pen := UiKit.label(tr("RESULTADO_PENALTIS") % [so[0], so[1]], UiKit.FONT_H2)
		pen.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(pen)
	var head := UiKit.hbox(DesignTokens.SPACING_SM)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(UiKit.outcome_badge(str(sum.outcome), 36))
	head.add_child(UiKit.title(tr(tone.key), UiKit.FONT_TITLE))
	v.add_child(head)
	var t := UiKit.label(tr(tone.text), UiKit.FONT_BODY, UiKit.INK, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	return card


func _crest_for(club_id: String, club_name: String) -> Control:
	var g := game()
	if g and g.club() and g.club().id == club_id:
		return ClubCrest.for_club(g.club(), 64)
	var look: Dictionary = g.club_look(club_id) if g else {}
	if not look.is_empty():
		return ClubCrest.for_colors(look.color, look.secondary, str(look.short_name), 64)
	return ClubCrest.for_colors(DesignTokens.COLOR_TEXT_MUTED, Color.WHITE, club_name.left(3).to_upper(), 64)


func _stats_card(result: Dictionary, _sum: Dictionary) -> Control:
	var parts := UiKit.titled_card(tr("RESULTADO_NUMEROS"))
	var v: VBoxContainer = parts[1]
	var stats := MatchStats.from_result(result)
	var hc := _team_color(str(result.get("home", {}).get("club_id", "")), UiKit.BLUE)
	var ac := _team_color(str(result.get("away", {}).get("club_id", "")), UiKit.RED)
	if GameStore._color_distance(hc, ac) < GameStore.COLOR_CLASH:
		ac = UiKit.INK
	for r in MatchStats.rows(stats):
		v.add_child(CompareBar.make(r[0], r[1], r[2], hc, ac, r[3]))
	return parts[0]


func _team_color(club_id: String, fallback: Color) -> Color:
	var g := game()
	var look: Dictionary = g.club_look(club_id) if g else {}
	return look.get("color", fallback)


func _highlights_card(result: Dictionary) -> Control:
	var parts := UiKit.titled_card(tr("RESULTADO_LANCES"))
	var v: VBoxContainer = parts[1]
	var names := _names(result)
	var lances := MatchStats.highlights(result.get("events", []))
	if lances.is_empty():
		v.add_child(UiKit.label(tr("RESULTADO_SEM_LANCES"), UiKit.FONT_BODY, UiKit.MUTED, true))
	for h in lances:
		var row := UiKit.hbox(DesignTokens.SPACING_SM)
		row.add_child(UiKit.icon(MatchStats.icon_for(h), 22))
		var side_name := str(result.get(str(h.team), {}).get("name", ""))
		var l := UiKit.label(MatchStats.describe(h, names), UiKit.FONT_BODY, UiKit.INK, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UiKit.label(side_name, UiKit.FONT_CAPTION, UiKit.MUTED))
		v.add_child(row)
	return parts[0]


## Nomes dos atletas dos dois times (mundo do jogador e clubes de demonstração).
func _names(result: Dictionary) -> Dictionary:
	var out := {}
	var g := game()
	if g:
		for aid in g.world.athletes:
			out[aid] = g.world.athletes[aid].name
	for path in GameStore.FRIENDLY_OPPONENTS:
		var ts := DemoData.team_setup(path)
		for a: Athlete in ts.lineup + ts.bench:
			out[a.id] = a.name
	return out


## O que mudou no clube por causa do jogo (sinal e ícone, nunca só cor).
func _career_card() -> Control:
	var parts := UiKit.titled_card(tr("RESULTADO_CARREIRA"))
	var v: VBoxContainer = parts[1]
	var career: Dictionary = _report.get("career", {})
	var kind := str(_report.get("kind", ""))
	if career.is_empty():
		v.add_child(UiKit.label(tr("RESULTADO_HISTORICO"), UiKit.FONT_BODY, UiKit.MUTED, true))
		return parts[0]
	if kind != GameStore.KIND_OFFICIAL:
		v.add_child(UiKit.label(tr("MODOS_REGRA_TEXTO"), UiKit.FONT_BODY, UiKit.INK, true))
		return parts[0]
	var days := int(career.get("days_gained", 0))
	var row := UiKit.hbox(DesignTokens.SPACING_SM)
	row.add_child(UiKit.icon("calendario", 24))
	row.add_child(UiKit.label(tr("RESULTADO_DIAS") % days if days > 0 else tr("RESULTADO_SEM_DIAS"), UiKit.FONT_BODY, UiKit.INK, true))
	v.add_child(row)
	for b in career.get("birthdays", []):
		var r := UiKit.hbox(DesignTokens.SPACING_SM)
		r.add_child(UiKit.icon("evolucao", 24))
		r.add_child(UiKit.label(tr("RESULTADO_ANIVERSARIO") % [b.name, int(b.age)], UiKit.FONT_BODY, UiKit.INK, true))
		v.add_child(r)
	for a in career.get("retired", []):
		var r := UiKit.hbox(DesignTokens.SPACING_SM)
		r.add_child(UiKit.icon("aposentadoria", 24))
		r.add_child(UiKit.label(tr("RESULTADO_APOSENTOU") % a.name, UiKit.FONT_BODY, UiKit.INK, true))
		v.add_child(r)
	return parts[0]


func _actions() -> Control:
	var row := UiKit.hbox(DesignTokens.SPACING_SM)
	var kind := str(_report.get("kind", ""))
	if kind == GameStore.KIND_FRIENDLY and not bool(_report.get("debut", false)) and _report.has("opponent"):
		var again := UiKit.button(tr("RESULTADO_JOGAR_DE_NOVO"), "secondary", "replay", 56)
		again.pressed.connect(func() -> void:
			go("prematch", {"kind": GameStore.KIND_FRIENDLY, "opponent": str(_report.opponent.get("key", ""))}))
		row.add_child(again)
	var done := UiKit.button(tr("RESULTADO_CONCLUIR"), "primary", "confirmar", 56)
	done.name = "Done"
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(_finish)
	row.add_child(done)
	return row


func _finish() -> void:
	go("home")
