class_name SquadScreen
extends ScreenBase
## E01 · Elenco: as figurinhas do clube em dois blocos, Titulares (os 11 da escalação salva) e
## Reservas (o resto do elenco). Sub-abas Atletas · Escalação · Mercado só com ícone; o mercado
## aparece bloqueado com o motivo até a Fase 3. Busca, setor e ordenação ficam numa janela aberta pelo
## botão de filtro (que fica amarelo quando há filtro ativo), para a grade ter a tela toda: no
## celular os titulares cabem inteiros, sem figurinha cortada. Idade, papel e atributos ficam na
## ficha (E03), aberta com um toque.

const SORTS := [["ovr", "ELENCO_ORDEM_OVR"], ["age", "ELENCO_ORDEM_IDADE"], ["name", "ELENCO_ORDEM_NOME"], ["sector", "ELENCO_ORDEM_SETOR"]]
const SECTOR_ORDER := ["GK", "DEF", "MID", "FWD"]
## Largura mínima de cada figurinha (px lógicos). Abaixo disso a arte vira borrão.
const CARD_MIN_W := 72.0
const COLS_MIN := 3
const COLS_MAX := 8
## Altura do título de cada bloco (ícone + nome + contagem).
const SECTION_H := 34.0

var _query := ""
var _sector := "ALL"
var _sort := "ovr"
var _counter: Label
var _filter_btn: Button
var _scroll: ScrollContainer
var _list: VBoxContainer
var _cols := 0


func _init() -> void:
	max_content_width = 0.0


func build() -> void:
	content.add_theme_constant_override("separation", DesignTokens.SPACING_SM)
	var head := UiKit.hbox(DesignTokens.SPACING_SM)
	var tabs := UiKit.segmented([["athletes", tr("ELENCO_ATLETAS"), "elenco"], ["lineup", tr("ESCALACAO_TITULO"), "tatica"],
		["market", tr("ELENCO_MERCADO"), "mercado"]], "athletes", _on_subtab, ["market"], tr("ELENCO_MERCADO_EM_BREVE"))
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tabs)
	# Vagas: "11/30" ao lado do ícone; a frase inteira fica na dica.
	var count_box := UiKit.hbox(DesignTokens.SPACING_XS)
	count_box.add_child(UiKit.icon("elenco", 22))
	_counter = UiKit.label("", UiKit.FONT_BODY, UiKit.INK)
	_counter.name = "Counter"
	_counter.add_theme_font_override("font", DesignTokens.display_font())
	_counter.mouse_filter = Control.MOUSE_FILTER_PASS
	count_box.add_child(_counter)
	head.add_child(count_box)
	_filter_btn = UiKit.icon_only(UiKit.button(tr("ELENCO_FILTROS"), "secondary", "filtrar", 44))
	_filter_btn.name = "FilterButton"
	_filter_btn.pressed.connect(_open_filters)
	head.add_child(_filter_btn)
	content.add_child(head)
	_list = UiKit.vbox(DesignTokens.SPACING_SM)
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll = UiKit.scroll(_list)
	_scroll.resized.connect(func() -> void:
		if state == State.READY:
			_render_list())
	content.add_child(_scroll)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _list != null and state == State.READY:
		_render_list()


func _on_subtab(id: String) -> void:
	if id == "lineup":
		go("lineup")


func refresh() -> void:
	var g := game()
	if g == null or not g.has_club():
		show_empty("clube", tr("INICIO_SEM_CLUBE_TITULO"), tr("INICIO_SEM_CLUBE_TEXTO"))
		return
	var n := g.squad().size()
	var limit := g.squad_limit()
	_counter.text = "%d/%d" % [n, limit]
	_counter.tooltip_text = tr("ELENCO_CONTADOR") % [n, limit, maxi(limit - n, 0)]
	_render_list()
	show_ready()


func _filtered() -> bool:
	return _query != "" or _sector != "ALL" or _sort != "ovr"


# ------------------------------------------------------------------ janela de filtros
func _open_filters() -> void:
	var r := router()
	if r == null:
		return
	var box := UiKit.vbox(DesignTokens.SPACING_MD)
	var search := LineEdit.new()
	search.name = "Search"
	search.placeholder_text = tr("ELENCO_BUSCAR")
	search.right_icon = GameIcons.texture("buscar")
	search.clear_button_enabled = true
	search.text = _query
	search.custom_minimum_size.y = 48
	search.text_changed.connect(func(t: String) -> void:
		_query = t.strip_edges().to_lower()
		_render_list())
	box.add_child(search)
	var sectors := [["ALL", tr("ELENCO_TODOS")]]
	for s in SECTOR_ORDER:
		sectors.append([s, GameTerms.sector(s)])
	var sector_host := UiKit.vbox(0)
	box.add_child(sector_host)
	var sort_host := UiKit.vbox(0)
	var sort_row := UiKit.hbox(DesignTokens.SPACING_SM)
	sort_row.add_child(UiKit.icon("ordenar", 26))
	sort_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sort_row.add_child(sort_host)
	box.add_child(sort_row)
	var draw_sectors := func(again: Callable) -> void:
		ScreenBase.clear(sector_host)
		sector_host.add_child(UiKit.segmented(sectors, _sector, func(id: String) -> void:
			_sector = id
			_render_list()
			again.call(again)))
	var draw_sort := func(again: Callable) -> void:
		ScreenBase.clear(sort_host)
		var items := SORTS.map(func(s: Array) -> Array: return [s[0], tr(s[1])])
		sort_host.add_child(UiKit.segmented(items, _sort, func(id: String) -> void:
			_sort = id
			_render_list()
			again.call(again)))
	draw_sectors.call(draw_sectors)
	draw_sort.call(draw_sort)
	r.overlays.modal(tr("ELENCO_FILTROS"), "", [
		{"label": tr("ELENCO_LIMPAR"), "kind": "secondary", "callback": func() -> void:
			_query = ""
			_sector = "ALL"
			_sort = "ovr"
			_render_list()},
		{"label": tr("UI_ENTENDI"), "kind": "primary", "cancel": true},
	], "filtrar", box)


# ------------------------------------------------------------------ lista
func _visible_athletes(pool: Array) -> Array:
	var g := game()
	var list: Array = pool.filter(func(a: Athlete) -> bool:
		return (_sector == "ALL" or a.position == _sector) and (_query == "" or a.name.to_lower().contains(_query)))
	var ages := {}
	for a: Athlete in list:
		ages[a.id] = g.age(a)
	list.sort_custom(func(x: Athlete, y: Athlete) -> bool:
		match _sort:
			"age":
				return ages[x.id] < ages[y.id] if ages[x.id] != ages[y.id] else x.name < y.name
			"name":
				return x.name.naturalnocasecmp_to(y.name) < 0
			"sector":
				var sx := SECTOR_ORDER.find(x.position)
				var sy := SECTOR_ORDER.find(y.position)
				return sx < sy if sx != sy else GameStore.overall(x) > GameStore.overall(y)
		var ox := GameStore.overall(x)
		var oy := GameStore.overall(y)
		return ox > oy if ox != oy else x.name < y.name)
	return list


## Titulares e reservas do elenco (sem filtro).
func _split() -> Array:
	var g := game()
	var starters := {}
	for a in g.starters():
		if a != null:
			starters[(a as Athlete).id] = true
	var first: Array = []
	var rest: Array = []
	for a: Athlete in g.squad():
		(first if starters.has(a.id) else rest).append(a)
	return [first, rest]


func _grid_width() -> float:
	var available := size.x
	if max_content_width > 0.0:
		available = minf(available, max_content_width)
	var w := available - 2.0 * PAD
	return maxf(w - 4.0, CARD_MIN_W)


## Colunas: as menos possíveis (figurinhas maiores) com que os 11 titulares cabem inteiros na
## altura visível; em tela larga, o que a largura comportar.
func _columns() -> int:
	var w := _grid_width()
	var gap := float(DesignTokens.SPACING_SM)
	var max_cols := clampi(floori((w + gap) / (CARD_MIN_W + gap)), COLS_MIN, COLS_MAX)
	var h := _scroll.size.y if _scroll else 0.0
	if h <= 0.0:
		return mini(4, max_cols)
	var n := maxi(game().lineup_size() if game() else 11, 1)
	for c in range(COLS_MIN, max_cols + 1):
		var cw := (w - (c - 1) * gap) / c
		var rows := ceili(float(n) / c)
		if SECTION_H + rows * cw * StickerCard.ASPECT + (rows - 1) * gap <= h:
			return c
	return max_cols


func _render_list() -> void:
	var g := game()
	if g == null or _list == null:
		return
	ScreenBase.clear(_list)
	UiKit.style_button(_filter_btn, "primary" if _filtered() else "secondary")
	_cols = _columns()
	var parts := _split()
	var first := _visible_athletes(parts[0])
	var rest := _visible_athletes(parts[1])
	if first.is_empty() and rest.is_empty():
		_list.add_child(UiKit.empty_state("buscar", tr("ELENCO_FILTRO_VAZIO"), tr("ELENCO_FILTRO_VAZIO_TEXTO")))
		return
	var kit := g.kit()
	var ids: Array = (first + rest).map(func(a: Athlete) -> String: return a.id)
	var gap := float(DesignTokens.SPACING_SM)
	var w := floorf((_grid_width() - (_cols - 1) * gap) / _cols)
	_section("titular", tr("ELENCO_TITULARES"), first, kit, ids, w, "")
	_section("reserva", tr("ELENCO_RESERVAS"), rest, kit, ids, w,
		"" if _filtered() else tr("ELENCO_SEM_RESERVAS"))


func _section(icon_id: String, heading: String, athletes: Array, kit: Dictionary, ids: Array, w: float, empty_text: String) -> void:
	if athletes.is_empty() and empty_text == "":
		return
	var head := UiKit.hbox(DesignTokens.SPACING_XS)
	head.name = "Section_" + icon_id
	head.custom_minimum_size.y = SECTION_H - DesignTokens.SPACING_SM
	head.add_child(UiKit.icon(icon_id, 24))
	var t := UiKit.title(heading.to_upper(), UiKit.FONT_BODY)
	head.add_child(t)
	head.add_child(UiKit.label(str(athletes.size()), UiKit.FONT_BODY, UiKit.MUTED))
	_list.add_child(head)
	if athletes.is_empty():
		var c := UiKit.caption(empty_text)
		_list.add_child(c)
		return
	var grid := GridContainer.new()
	grid.name = "Grid_" + icon_id
	grid.columns = _cols
	grid.add_theme_constant_override("h_separation", DesignTokens.SPACING_SM)
	grid.add_theme_constant_override("v_separation", DesignTokens.SPACING_SM)
	for a: Athlete in athletes:
		grid.add_child(_card(a, kit, ids, w))
	_list.add_child(grid)


## Todas as figurinhas visíveis (titulares e reservas), na ordem da tela.
func cards() -> Array:
	return _list.find_children("Card_*", "", true, false)


## Figurinha do atleta; um toque abre a ficha.
func _card(a: Athlete, kit: Dictionary, ids: Array, w: float) -> Control:
	var card := StickerCard.new()
	card.name = "Card_" + a.id
	card.size = Vector2(w, w * StickerCard.ASPECT)
	card.custom_minimum_size = card.size
	card.set_card(GameStore.card_for(a), kit, null, a.attributes)
	card.set_face_up(true)
	card.tooltip_text = "%s · %d" % [a.name, GameStore.overall(a)]
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.pressed.connect(func() -> void: go("athlete", {"id": a.id, "ids": ids}))
	return card
