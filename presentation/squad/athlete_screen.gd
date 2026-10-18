class_name AthleteScreen
extends ScreenBase
## E03 · Ficha do atleta: figurinha, atributos 1–99 com barras e ícones, fase da carreira, procedência
## (DNA e clubes). Atributos de goleiro ficam esmaecidos em atletas de linha e vice-versa (o motivo
## fica no toque/dica). Regras e explicações ficam nas dicas, não na tela. Anterior/Próximo trocam de
## atleta sem voltar à lista (alternativa ao deslizar). As ações de mercado voltam com o mercado.
## params: id (atleta), ids (ordem da lista de onde veio, opcional).

const TWO_COLUMNS_MIN := 760.0
const CARD_W := 250.0
const CARD_W_COMPACT := 118.0
## Atributo (data/attributes.json) -> ícone (GameIcons).
const ATTR_ICONS := {
	"pace": "velocidade", "physical": "forca", "passing": "passe", "finishing": "finalizacao",
	"tackling": "desarme", "positioning": "posicionamento", "reflexes": "reflexos",
	"elasticity": "elasticidade", "stamina": "folego",
}

var _athlete: Athlete
var _cols := 0


func screen_title() -> String:
	return _athlete.name if _athlete else ""


func refresh() -> void:
	var g := game()
	_athlete = g.athlete(str(params.get("id", ""))) if g else null
	if _athlete == null:
		show_empty("elenco", tr("ATLETA_NAO_ENCONTRADO"), tr("ATLETA_NAO_ENCONTRADO_TEXTO"),
			tr("NAV_ELENCO"), func() -> void: go("squad"))
		return
	_rebuild()
	show_ready()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and content != null and state == State.READY:
		if (2 if size.x >= TWO_COLUMNS_MIN else 1) != _cols:
			_rebuild()


func _rebuild() -> void:
	ScreenBase.clear(content)
	var g := game()
	var a := _athlete
	_cols = 2 if size.x >= TWO_COLUMNS_MIN else 1
	content.add_child(_nav_row())
	var body := UiKit.vbox(DesignTokens.SPACING_LG)
	content.add_child(UiKit.scroll(body))
	# Figurinha ao lado da identidade também no celular (menor), para os atributos subirem.
	var top := UiKit.hbox(DesignTokens.SPACING_LG if _cols == 2 else DesignTokens.SPACING_MD)
	body.add_child(top)
	var card_box := CenterContainer.new()
	var card := StickerCard.new()
	var w := CARD_W if _cols == 2 else CARD_W_COMPACT
	card.size = Vector2(w, w * StickerCard.ASPECT)
	card.custom_minimum_size = card.size
	card.set_card(GameStore.card_for(a), g.kit(), null, a.attributes)
	card.set_face_up(true)
	card_box.add_child(card)
	top.add_child(card_box)
	var info := UiKit.vbox(DesignTokens.SPACING_MD)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(_identity(g, a))
	info.add_child(_career(g, a))
	if _cols == 2:
		info.add_child(_attributes(a))
	else:
		body.add_child(_attributes(a))
	body.add_child(_provenance(g, a))


func _nav_row() -> Control:
	var ids: Array = params.get("ids", [])
	if ids.is_empty():
		var g := game()
		ids = g.squad().map(func(x: Athlete) -> String: return x.id) if g else []
	var i := ids.find(_athlete.id)
	var row := UiKit.hbox(DesignTokens.SPACING_SM)
	var prev := UiKit.button(tr("ATLETA_ANTERIOR"), "secondary", "voltar", 40)
	prev.disabled = i <= 0
	prev.pressed.connect(func() -> void: _show_other(ids, i - 1))
	var counter := UiKit.label("%d/%d" % [i + 1, ids.size()] if i >= 0 else "", UiKit.FONT_SMALL, UiKit.MUTED)
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nxt := UiKit.button(tr("ATLETA_PROXIMO"), "secondary", "avancar", 40)
	nxt.disabled = i < 0 or i >= ids.size() - 1
	nxt.pressed.connect(func() -> void: _show_other(ids, i + 1))
	row.add_child(prev)
	row.add_child(counter)
	row.add_child(nxt)
	return row


func _show_other(ids: Array, i: int) -> void:
	if i < 0 or i >= ids.size():
		return
	params["id"] = ids[i]
	params["ids"] = ids
	refresh()


func _identity(g: GameStore, a: Athlete) -> Control:
	var v := UiKit.vbox(DesignTokens.SPACING_XS)
	var row := UiKit.hbox(DesignTokens.SPACING_MD)
	var name_l := UiKit.title(a.name, UiKit.FONT_DISPLAY if _cols == 2 else UiKit.FONT_TITLE)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)
	row.add_child(UiKit.ovr_badge(GameStore.overall(a), 52 if _cols == 2 else 44))
	v.add_child(row)
	var sub := "%s  —  %s" % [GameTerms.sector(a.position, false), tr("ELENCO_IDADE") % floori(g.age(a))]
	v.add_child(UiKit.wrap(UiKit.label(sub, UiKit.FONT_BODY, DesignTokens.color_for_position(a.position))))
	var chips := UiKit.hbox(DesignTokens.SPACING_XS)
	if a.tier() != "":
		chips.add_child(UiKit.chip(GameTerms.card_tier(a.tier()), DesignTokens.color_for_tier(a.tier())))
	if a.nationality != "":
		chips.add_child(UiKit.chip(a.nationality, UiKit.BLUE))
	if not a.is_active():
		chips.add_child(UiKit.chip(tr("ATLETA_APOSENTADO"), UiKit.MUTED, "aposentadoria"))
	v.add_child(chips)
	return v


## Barras 1–99. Atributos do outro grupo (goleiro × linha) ficam esmaecidos, com a legenda.
func _attributes(a: Athlete) -> Control:
	var parts := UiKit.titled_card(tr("ATLETA_ATRIBUTOS"))
	var v: VBoxContainer = parts[1]
	for row_d in AttributeCatalog.data().attributes:
		var id := str(row_d.id)
		var group := str(row_d.get("group", "all"))
		var off := (group == "goalkeeper" and not a.is_goalkeeper()) or (group == "outfield" and a.is_goalkeeper())
		var val := a.attr(id)
		var row := UiKit.hbox(DesignTokens.SPACING_SM)
		row.add_child(UiKit.icon(ATTR_ICONS.get(id, "estatisticas"), 24))
		var l := UiKit.label(AttributeCatalog.label(id), UiKit.FONT_BODY)
		l.custom_minimum_size.x = 130
		l.tooltip_text = str(row_d.get("doc", ""))
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(l)
		var bar := UiKit.progress(val, AttributeCatalog.max_value(), _bar_color(val))
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		var num := UiKit.label(_fmt(val), UiKit.FONT_H2)
		num.custom_minimum_size.x = 40
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(num)
		if off:
			row.modulate = Color(1, 1, 1, 0.4)
			row.tooltip_text = tr("ATLETA_ATRIBUTO_GOLEIRO") if group == "goalkeeper" else tr("ATLETA_ATRIBUTO_LINHA")
		v.add_child(row)
	parts[0].tooltip_text = tr("ATLETA_LEGENDA_GOLEIRO") if not a.is_goalkeeper() else tr("ATLETA_LEGENDA_LINHA")
	return parts[0]


static func _bar_color(v: float) -> Color:
	if v >= 80.0:
		return UiKit.GREEN
	if v >= 60.0:
		return UiKit.YELLOW
	if v >= 40.0:
		return UiKit.BLUE
	return UiKit.RED


## Inteiro quando é inteiro; uma casa no declínio (frações de 0,5).
static func _fmt(v: float) -> String:
	return str(roundi(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v).replace(".", ",")


## Fase da carreira em uma linha: selo da fase e o dia no ano de carreira. A regra fica na dica.
func _career(g: GameStore, a: Athlete) -> Control:
	var c := g.career(a)
	var v := UiKit.vbox(DesignTokens.SPACING_XS)
	v.tooltip_text = tr("ATLETA_CARREIRA_REGRA") if bool(c.aging) else tr("ATLETA_CARREIRA_PARADA")
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(UiKit.chip(tr("FASE_" + str(c.phase).to_upper()), UiKit.YELLOW, GameIcons.PHASE.get(str(c.phase), "evolucao")))
	var bar := UiKit.progress(float(c.days_in_year), maxf(float(c.days_per_year), 1.0), UiKit.BLUE, 8.0)
	bar.tooltip_text = tr("ATLETA_IDADE_DIAS") % [floori(float(c.age)), int(c.days_in_year), int(c.days_per_year)]
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(bar)
	return v


## Procedência: origem gravada no DNA e a trajetória de clubes.
func _provenance(g: GameStore, a: Athlete) -> Control:
	var parts := UiKit.titled_card(tr("ATLETA_PROCEDENCIA"))
	var v: VBoxContainer = parts[1]
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", DesignTokens.SPACING_SM)
	flow.add_theme_constant_override("v_separation", DesignTokens.SPACING_XS)
	var origin: Dictionary = a.dna.get("origin", {})
	var source := str(origin.get("source", a.dna.get("generator", "")))
	flow.add_child(UiKit.chip(tr("ATLETA_ORIGEM") % _origin_label(source), UiKit.BLUE, "historico"))
	for h in a.club_history:
		var cid := str(h.get("club_id", ""))
		var c: Club = g.world.clubs.get(cid)
		flow.add_child(UiKit.label(">", UiKit.FONT_H2, UiKit.MUTED))
		flow.add_child(UiKit.chip("%s  %s" % [c.name if c else cid, _short_date(str(h.get("from", "")))], UiKit.GREEN if str(h.get("to", "")) == "" else UiKit.MUTED, "clube"))
	v.add_child(flow)
	if a.dna_hash() != "":
		parts[0].tooltip_text = tr("ATLETA_DNA") % a.dna_hash().left(12)
	return parts[0]


func _origin_label(source: String) -> String:
	match source:
		"pack":
			return tr("ATLETA_ORIGEM_PACOTE")
		"onboarding":
			return tr("ATLETA_ORIGEM_ESTREIA")
		"demo":
			return tr("ATLETA_ORIGEM_DEMO")
	return tr("ATLETA_ORIGEM_FUNDACAO")


static func _short_date(iso: String) -> String:
	var p := iso.split("-")
	return "%s/%s/%s" % [p[2], p[1], p[0]] if p.size() == 3 else iso
