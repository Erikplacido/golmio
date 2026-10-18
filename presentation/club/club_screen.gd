class_name ClubScreen
extends ScreenBase
## B01 · Clube: painel com escudo, uniforme, elenco e a campanha (V/E/D, gols). Resumo primeiro,
## detalhe a um toque. Liga, torcida, finanças e seleção dependem de mecânicas da Fase 2 em diante e
## aparecem só como abas bloqueadas (o motivo fica na dica; nada de números inventados).

const HISTORY_LIMIT := 200
const TWO_COLUMNS_MIN := 760.0
const KIT_CARD_W := 88.0

var _cols := 0


func refresh() -> void:
	var g := game()
	if g == null or not g.has_club():
		show_empty("clube", tr("INICIO_SEM_CLUBE_TITULO"), tr("INICIO_SEM_CLUBE_TEXTO"),
			tr("INICIO_CRIAR_CLUBE"), func() -> void: go("club_creation"))
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
	_cols = 2 if size.x >= TWO_COLUMNS_MIN else 1
	content.add_child(UiKit.segmented([["panel", tr("CLUBE_PAINEL")], ["league", tr("CLUBE_LIGA")],
		["fans", tr("CLUBE_TORCIDA")], ["finances", tr("CLUBE_FINANCAS")], ["national", tr("CLUBE_SELECAO")]],
		"panel", func(_id: String) -> void: pass, ["league", "fans", "finances", "national"], tr("UI_EM_BREVE")))
	var body := UiKit.vbox(DesignTokens.SPACING_LG)
	content.add_child(UiKit.scroll(body))
	body.add_child(_header(g))
	var row: BoxContainer = UiKit.hbox(DesignTokens.SPACING_LG) if _cols == 2 else UiKit.vbox(DesignTokens.SPACING_LG)
	body.add_child(row)
	var campaign := _campaign(g)
	campaign.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(campaign)
	var kit := _kit_card(g)
	row.add_child(kit)


func _header(g: GameStore) -> Control:
	var club := g.club()
	var card := UiKit.card()
	var h := UiKit.hbox(DesignTokens.SPACING_LG)
	card.add_child(h)
	h.add_child(ClubCrest.for_club(club, 84))
	var v := UiKit.vbox(DesignTokens.SPACING_XS)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_l := UiKit.title(club.name, UiKit.FONT_DISPLAY)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name_l)
	v.add_child(UiKit.label(tr("CLUBE_SIGLA") % club.short_name, UiKit.FONT_BODY, UiKit.MUTED))
	var n := g.squad().size()
	v.add_child(UiKit.label(tr("ELENCO_CONTADOR") % [n, g.squad_limit(), maxi(g.squad_limit() - n, 0)], UiKit.FONT_BODY))
	var stg := GameStore.strength(g.starters())
	v.add_child(UiKit.wrap(UiKit.label(tr("INICIO_FORCA") % [stg.ovr, stg.def, stg.mid, stg.fwd], UiKit.FONT_SMALL, UiKit.MUTED)))
	h.add_child(v)
	return card


## Campanha: totais de vitórias, empates e derrotas (com letra) e saldo de gols.
func _campaign(g: GameStore) -> Control:
	var parts := UiKit.titled_card(tr("CLUBE_CAMPANHA"))
	var v: VBoxContainer = parts[1]
	var results := g.recent_results(HISTORY_LIMIT)
	if results.is_empty():
		v.add_child(UiKit.label(tr("INICIO_SEM_PARTIDAS"), UiKit.FONT_BODY, UiKit.MUTED, true))
		return parts[0]
	var totals := {"win": 0, "draw": 0, "loss": 0}
	var gf := 0
	var ga := 0
	var officials := 0
	for r in results:
		totals[r.outcome] += 1
		gf += int(r.goals_for)
		ga += int(r.goals_against)
		if r.kind == GameStore.KIND_OFFICIAL:
			officials += 1
	var row := UiKit.hbox(DesignTokens.SPACING_MD)
	for o in ["win", "draw", "loss"]:
		var cell := UiKit.hbox(DesignTokens.SPACING_XS)
		cell.add_child(UiKit.outcome_badge(o, 34))
		cell.add_child(UiKit.title(str(totals[o]), UiKit.FONT_TITLE))
		row.add_child(cell)
	v.add_child(row)
	v.add_child(UiKit.key_value(tr("CLUBE_PARTIDAS"), str(results.size())))
	v.add_child(UiKit.key_value(tr("CLUBE_OFICIAIS"), str(officials)))
	v.add_child(UiKit.key_value(tr("CLUBE_GOLS"), "%d : %d" % [gf, ga]))
	var diff := gf - ga
	v.add_child(UiKit.key_value(tr("CLUBE_SALDO"), ("+%d" % diff) if diff > 0 else str(diff),
		UiKit.GREEN if diff > 0 else (UiKit.RED if diff < 0 else UiKit.INK)))
	return parts[0]


## Uniforme principal vestido na figurinha do capitão (ou do primeiro atleta).
func _kit_card(g: GameStore) -> Control:
	var parts := UiKit.titled_card(tr("CLUBE_UNIFORME"))
	var v: VBoxContainer = parts[1]
	var squad := g.squad()
	var model: Athlete = g.athlete(str(g.tactics().get("captain_id", "")))
	if model == null and not squad.is_empty():
		model = squad[0]
	# Figurinha pequena ao lado do botão: o uniforme é o que importa aqui, não o atleta.
	var h := UiKit.hbox(DesignTokens.SPACING_MD)
	v.add_child(h)
	if model:
		var card := StickerCard.new()
		card.size = Vector2(KIT_CARD_W, KIT_CARD_W * StickerCard.ASPECT)
		card.custom_minimum_size = card.size
		card.set_card(GameStore.card_for(model), g.kit(), null, model.attributes)
		card.set_face_up(true)
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.pressed.connect(func() -> void: go("athlete", {"id": model.id}))
		h.add_child(card)
	var edit := UiKit.locked_button(tr("CLUBE_EDITAR_IDENTIDADE"), tr("UI_EM_BREVE"), "editar")
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(edit)
	return parts[0]

