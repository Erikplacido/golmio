class_name HomeScreen
extends ScreenBase
## H01 · Início: responde em 2 segundos "o que eu faço agora?". Um único botão amarelo — o jogo
## oficial de hoje quando está disponível; depois dele, o próximo passo útil (amistoso). Abaixo:
## pendências que pedem ação, modos de jogo e os últimos resultados (V/E/D com letra).
## Na estreia (etapa "tour") mostra o tour de 3 dicas (O05).

const TWO_COLUMNS_MIN := 860.0
const RECENT_RESULTS := 5

var _cols := 0
var _countdown: Label
var _timer: Timer
var _main_card: Control


func build() -> void:
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_tick)
	add_child(_timer)


func refresh() -> void:
	var g := game()
	if g == null or not g.has_club():
		show_empty("clube", tr("INICIO_SEM_CLUBE_TITULO"), tr("INICIO_SEM_CLUBE_TEXTO"),
			tr("INICIO_CRIAR_CLUBE"), func() -> void: go("club_creation"))
		return
	_rebuild()
	show_ready()
	if g.onboarding_stage() == GameStore.STAGE_TOUR:
		_start_tour.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and content != null and state == State.READY:
		if _columns_for(size.x) != _cols:
			_rebuild()


func _columns_for(w: float) -> int:
	return 2 if w >= TWO_COLUMNS_MIN else 1


func _rebuild() -> void:
	ScreenBase.clear(content)
	_countdown = null
	_cols = _columns_for(size.x)
	var body := UiKit.vbox(DesignTokens.SPACING_LG)
	content.add_child(UiKit.scroll(body))
	var left := body
	var right := body
	if _cols == 2:
		var row := UiKit.hbox(DesignTokens.SPACING_LG)
		left = UiKit.vbox(DesignTokens.SPACING_LG)
		right = UiKit.vbox(DesignTokens.SPACING_LG)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.size_flags_stretch_ratio = 1.4
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(left)
		row.add_child(right)
		body.add_child(row)
	_main_card = _build_main_card()
	left.add_child(_main_card)
	left.add_child(_build_modes())
	var pend := _build_pending()
	if pend:
		right.add_child(pend)
	right.add_child(_build_recent())
	_timer.stop()
	if _countdown:
		if _timer.is_inside_tree():
			_timer.start()
		else:
			_timer.autostart = true


# --- cartão principal -------------------------------------------------------------------------

func _build_main_card() -> Control:
	var g := game()
	var st := g.official_status()
	if bool(st.get("enabled", false)):
		return _official_card(st)
	return _friendly_card(tr("INICIO_AMISTOSO_TITULO"), tr("INICIO_AMISTOSO_TEXTO"), true)


func _official_card(st: Dictionary) -> Control:
	var g := game()
	var parts := UiKit.titled_card(tr("INICIO_OFICIAL_TITULO"))
	var card: PanelContainer = parts[0]
	var v: VBoxContainer = parts[1]
	card.name = "MainCard"
	var opp := g.official_opponent()
	v.add_child(_matchup(opp))
	if bool(st.get("available", false)):
		v.add_child(UiKit.hint(tr("INICIO_OFICIAL_REGRA")))
		var play := UiKit.button(tr("UI_JOGAR"), "primary", "jogar", 56)
		play.name = "PlayOfficial"
		play.pressed.connect(func() -> void: go("prematch", {"kind": GameStore.KIND_OFFICIAL}))
		v.add_child(play)
	else:
		var res: Dictionary = st.get("today_result", {})
		if not res.is_empty():
			var row := UiKit.hbox(DesignTokens.SPACING_SM)
			row.add_child(UiKit.outcome_badge(res.outcome))
			row.add_child(UiKit.label(tr("INICIO_JA_JOGADO") % [res.goals_for, res.goals_against, res.opponent], UiKit.FONT_BODY, UiKit.INK, true))
			var see := UiKit.button(tr("PARTIDA_VER_RESULTADO"), "secondary", "historico", 42)
			see.name = "SeeResult"
			see.pressed.connect(func() -> void: go("result", {"raw": res.raw}))
			row.add_child(see)
			v.add_child(row)
		_countdown = UiKit.label("", UiKit.FONT_H2)
		_countdown.name = "Countdown"
		v.add_child(_countdown)
		_tick()
		# O destaque passa para o próximo passo útil.
		var friendly := UiKit.button(tr("INICIO_JOGAR_AMISTOSO"), "primary", "jogar", 52)
		friendly.pressed.connect(func() -> void: go("modes"))
		v.add_child(friendly)
	return card


func _friendly_card(heading: String, text: String, primary: bool) -> Control:
	var parts := UiKit.titled_card(heading)
	var card: PanelContainer = parts[0]
	var v: VBoxContainer = parts[1]
	card.name = "MainCard"
	var g := game()
	var club := g.club()
	var row := UiKit.hbox(DesignTokens.SPACING_MD)
	row.add_child(ClubCrest.for_club(club, 56))
	var info := UiKit.vbox(DesignTokens.SPACING_XS)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UiKit.title(club.name, UiKit.FONT_TITLE))
	var stg := GameStore.strength(g.starters())
	info.add_child(UiKit.label(tr("INICIO_FORCA") % [stg.ovr, stg.def, stg.mid, stg.fwd], UiKit.FONT_SMALL, UiKit.MUTED))
	row.add_child(info)
	v.add_child(row)
	v.add_child(UiKit.hint(text))
	var play := UiKit.button(tr("UI_JOGAR"), "primary" if primary else "info", "jogar", 56)
	play.name = "PlayFriendly"
	play.pressed.connect(func() -> void: go("modes"))
	v.add_child(play)
	return card


## Escudos e nomes: "VOCÊ × ADVERSÁRIO".
func _matchup(opp: Dictionary) -> Control:
	var club := game().club()
	var row := UiKit.hbox(DesignTokens.SPACING_SM)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(ClubCrest.for_club(club, 48))
	var me := UiKit.title(club.short_name, UiKit.FONT_TITLE)
	me.tooltip_text = club.name
	row.add_child(me)
	row.add_child(UiKit.label("×", UiKit.FONT_DISPLAY, UiKit.INK))
	if opp.is_empty():
		row.add_child(UiKit.label("?", UiKit.FONT_TITLE))
	else:
		var them := UiKit.title(str(opp.short_name), UiKit.FONT_TITLE)
		them.tooltip_text = str(opp.name)
		row.add_child(them)
		row.add_child(ClubCrest.for_colors(opp.color, opp.secondary, str(opp.short_name), 48))
	return row


func _tick() -> void:
	if _countdown == null or not is_instance_valid(_countdown):
		return
	var g := game()
	_countdown.text = tr("INICIO_PROXIMO_OFICIAL") % UiKit.countdown_text(g.seconds_to_next_day() if g else 0)


# --- pendências, modos, resultados ------------------------------------------------------------

## Só o que pede ação (o badge não conta novidade passiva). null se não há nada.
func _build_pending() -> Control:
	var g := game()
	var items: Array = []
	var problems := g.lineup_problems()
	if not problems.is_empty():
		items.append({"icon": "tatica", "title": tr("INICIO_PEND_ESCALACAO"), "text": problems[0],
			"action": tr("INICIO_PEND_AJUSTAR"), "go": func() -> void: go("lineup")})
	var sealed := g.pack_inventory().filter(func(p): return str(p.get("status", "")) == "sealed").size()
	if sealed > 0:
		items.append({"icon": "pacotes", "title": tr("INICIO_PEND_PACOTES") % sealed, "text": tr("INICIO_PEND_PACOTES_TEXTO"),
			"action": tr("INICIO_PEND_ABRIR"), "go": func() -> void: router().switch_tab("collection")})
	if items.is_empty():
		return null
	var parts := UiKit.titled_card(tr("INICIO_PENDENCIAS"))
	var v: VBoxContainer = parts[1]
	for it in items:
		var row := UiKit.hbox(DesignTokens.SPACING_SM)
		row.add_child(UiKit.icon(it.icon, 32))
		var txt := UiKit.vbox(2)
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.add_child(UiKit.label(it.title, UiKit.FONT_BODY))
		txt.add_child(UiKit.caption(it.text))
		row.add_child(txt)
		var b := UiKit.button(it.action, "info", "", 42)
		b.pressed.connect(it.go)
		row.add_child(b)
		v.add_child(row)
	return parts[0]


func _build_modes() -> Control:
	var parts := UiKit.titled_card(tr("INICIO_MODOS"))
	var v: VBoxContainer = parts[1]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", DesignTokens.SPACING_SM)
	grid.add_theme_constant_override("v_separation", DesignTokens.SPACING_SM)
	v.add_child(grid)
	var friendly := UiKit.button(tr("MODO_AMISTOSO"), "info", GameIcons.KIND.friendly, 56)
	friendly.name = "ModeFriendly"
	friendly.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friendly.tooltip_text = tr("MODO_AMISTOSO_DICA")
	friendly.pressed.connect(func() -> void: go("modes"))
	grid.add_child(friendly)
	for m in [["MODO_COPA", GameIcons.KIND.cup], ["MODO_VARZEA", GameIcons.KIND.varzea], ["MODO_CODIGO", "convocacao"]]:
		var b := UiKit.locked_button(tr(m[0]), tr("UI_EM_BREVE"), m[1])
		b.custom_minimum_size.y = 56
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	v.add_child(UiKit.hint(tr("INICIO_MODOS_REGRA")))
	return parts[0]


func _build_recent() -> Control:
	var g := game()
	var parts := UiKit.titled_card(tr("INICIO_ULTIMOS"))
	var v: VBoxContainer = parts[1]
	var recent := g.recent_results(RECENT_RESULTS)
	if recent.is_empty():
		v.add_child(UiKit.label(tr("INICIO_SEM_PARTIDAS"), UiKit.FONT_BODY, UiKit.MUTED, true))
		return parts[0]
	var streak := UiKit.hbox(DesignTokens.SPACING_XS)
	for r in recent:
		var b := UiKit.outcome_badge(r.outcome, 34)
		b.tooltip_text = "%d × %d %s" % [r.goals_for, r.goals_against, r.opponent]
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		streak.add_child(b)
	v.add_child(streak)
	for r in recent.slice(0, 3):
		var row := UiKit.hbox(DesignTokens.SPACING_SM)
		var kind_icon := UiKit.icon(GameIcons.KIND.get(str(r.kind), "amistoso"), 22)
		kind_icon.tooltip_text = tr("TIPO_" + str(r.kind).to_upper())
		kind_icon.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(kind_icon)
		var t := UiKit.label("%d × %d  %s" % [r.goals_for, r.goals_against, r.opponent], UiKit.FONT_BODY)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		row.add_child(UiKit.label(_short_date(str(r.date)), UiKit.FONT_SMALL, UiKit.MUTED))
		v.add_child(row)
	return parts[0]


static func _short_date(iso: String) -> String:
	var p := iso.split("-")
	return "%s/%s" % [p[2], p[1]] if p.size() == 3 else iso


# --- tour do Início (O05) --------------------------------------------------------------------

func _start_tour() -> void:
	var r := router()
	if r == null or r.overlays.has_coach() or not is_visible_in_tree():
		return
	var root := get_tree().root
	var squad_tab := root.find_child("Tab_squad", true, false)
	var coll_tab := root.find_child("Tab_collection", true, false)
	var steps: Array = [{"target": _main_card, "title": tr("TOUR_1_TITULO"), "text": tr("TOUR_1_TEXTO")}]
	if squad_tab:
		steps.append({"target": squad_tab, "title": tr("TOUR_2_TITULO"), "text": tr("TOUR_2_TEXTO")})
	if coll_tab:
		steps.append({"target": coll_tab, "title": tr("TOUR_3_TITULO"), "text": tr("TOUR_3_TEXTO")})
	r.overlays.coach(steps, func(_skipped: bool) -> void:
		var g := game()
		if g:
			g.advance_onboarding(GameStore.STAGE_DONE)
	)
