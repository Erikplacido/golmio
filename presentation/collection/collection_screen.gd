class_name CollectionScreen
extends ScreenBase
## Coleção: sub-abas Pacotes (C01) · Álbum (C05) · Itens (C06).
##   Pacotes: inventário de pacotes fechados (mecânica packs) com o tipo e a quantidade; a abertura
##            no clube (C02–C04) chega com a Fase 3, e a demonstração do ritual fica a um toque.
##   Álbum:   as figurinhas do clube (cada uma é um atleta único: sem duplicatas), ativos e
##            aposentados.
##   Itens:   cosméticos (Fase 6), sempre "aparência sem bônus de desempenho".
## params: tab ("packs" | "album" | "items").

const CARD_W := 150.0

var _tab := "packs"
var _album_filter := "active"
var _body: VBoxContainer


func setup(p_route: String, p_params: Dictionary) -> void:
	super.setup(p_route, p_params)
	_tab = str(p_params.get("tab", _tab))


func build() -> void:
	var tabs := UiKit.hbox(0)
	tabs.name = "Tabs"
	content.add_child(tabs)
	_body = UiKit.vbox(DesignTokens.SPACING_MD)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_body)


func refresh() -> void:
	var g := game()
	if g == null or not g.has_club():
		show_empty("clube", tr("INICIO_SEM_CLUBE_TITULO"), tr("INICIO_SEM_CLUBE_TEXTO"))
		return
	var tabs: HBoxContainer = content.get_node("Tabs")
	ScreenBase.clear(tabs)
	var seg := UiKit.segmented([["packs", tr("COLECAO_PACOTES")], ["album", tr("COLECAO_ALBUM")], ["items", tr("COLECAO_ITENS")]],
		_tab, func(id: String) -> void:
			_tab = id
			refresh())
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(seg)
	ScreenBase.clear(_body)
	match _tab:
		"album":
			_album(g)
		"items":
			_items()
		_:
			_packs(g)
	show_ready()


func _packs(g: GameStore) -> void:
	var sealed := g.pack_inventory().filter(func(p): return str(p.get("status", "")) == "sealed")
	var n := g.squad().size()
	var free := maxi(g.squad_limit() - n, 0)
	_body.add_child(UiKit.label(tr("COLECAO_VAGAS") % [free, n, g.squad_limit()], UiKit.FONT_BODY, UiKit.MUTED))
	if sealed.is_empty():
		_body.add_child(UiKit.empty_state("pacotes", tr("COLECAO_SEM_PACOTES"), tr("COLECAO_SEM_PACOTES_TEXTO"),
			tr("COLECAO_VER_DEMO"), func() -> void: go("packs_demo")))
		return
	var counts := {}
	for p in sealed:
		var t := str(p.get("type", ""))
		counts[t] = int(counts.get(t, 0)) + 1
	var list := UiKit.vbox(DesignTokens.SPACING_SM)
	for t in counts:
		var row := UiKit.list_row()
		var h := UiKit.hbox(DesignTokens.SPACING_MD)
		row.add_child(h)
		h.add_child(UiKit.icon("pacotes", 44))
		var info := UiKit.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiKit.title(tr("COLECAO_PACOTE") % GameTerms.pack(t), UiKit.FONT_H2))
		info.add_child(UiKit.label(tr("COLECAO_PACOTE_QTD") % counts[t], UiKit.FONT_SMALL, UiKit.MUTED))
		h.add_child(info)
		h.add_child(UiKit.locked_button(tr("COLECAO_ABRIR"), tr("COLECAO_ABRIR_EM_BREVE"), "pacotes"))
		list.add_child(row)
	_body.add_child(UiKit.scroll(list))
	var demo := UiKit.button(tr("COLECAO_VER_DEMO"), "secondary", "replay")
	demo.pressed.connect(func() -> void: go("packs_demo"))
	_body.add_child(demo)


func _album(g: GameStore) -> void:
	var filt := UiKit.segmented([["active", tr("COLECAO_ATIVOS")], ["retired", tr("COLECAO_APOSENTADOS")]], _album_filter,
		func(id: String) -> void:
			_album_filter = id
			refresh())
	_body.add_child(filt)
	var club := g.club()
	var athletes: Array = []
	for aid in g.world.athletes:
		var a: Athlete = g.world.athletes[aid]
		var with_club := club.athlete_ids.has(aid) or a.club_history.any(func(h): return str(h.get("club_id", "")) == club.id)
		if with_club and (a.is_active() == (_album_filter == "active")):
			athletes.append(a)
	if athletes.is_empty():
		_body.add_child(UiKit.empty_state("album", tr("COLECAO_ALBUM_VAZIO"), tr("COLECAO_ALBUM_VAZIO_TEXTO")))
		return
	athletes.sort_custom(func(x: Athlete, y: Athlete) -> bool:
		return GameStore.overall(x) > GameStore.overall(y) if GameStore.overall(x) != GameStore.overall(y) else x.name < y.name)
	_body.add_child(UiKit.label(tr("COLECAO_ALBUM_TOTAL") % athletes.size(), UiKit.FONT_BODY, UiKit.MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", DesignTokens.SPACING_MD)
	flow.add_theme_constant_override("v_separation", DesignTokens.SPACING_MD)
	var kit := g.kit()
	var ids: Array = athletes.map(func(a: Athlete) -> String: return a.id)
	for a: Athlete in athletes:
		var card := StickerCard.new()
		card.size = Vector2(CARD_W, CARD_W * StickerCard.ASPECT)
		card.custom_minimum_size = card.size
		card.set_card(GameStore.card_for(a), kit, null, a.attributes)
		card.set_face_up(true)
		card.tooltip_text = a.name
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.pressed.connect(func() -> void: go("athlete", {"id": a.id, "ids": ids}))
		flow.add_child(card)
	_body.add_child(UiKit.scroll(flow))


func _items() -> void:
	var note := UiKit.card(Color("#e3f0f6"), "ui_aviso")
	note.add_child(UiKit.label(tr("LOJA_SEM_BONUS"), UiKit.FONT_BODY, UiKit.INK, true))
	_body.add_child(note)
	_body.add_child(UiKit.empty_state("vazio", tr("COLECAO_ITENS_VAZIO"), tr("COLECAO_ITENS_VAZIO_TEXTO")))
