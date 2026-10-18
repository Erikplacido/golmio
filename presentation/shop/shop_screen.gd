class_name ShopScreen
extends ScreenBase
## Loja de Cosméticos do Golmio: Sinks de moeda/créditos sem pay-to-win (GDD e Castronova).
## Itens 100% cosméticos: Estilos de Botão, Padrões de Uniforme/Brasão e Campos/Redes.

const CATALOG: Array = [
	{"id": "disco_vinil", "name_key": "LOJA_ITEM_DISCO_VINIL", "category": "button", "cat_key": "LOJA_CAT_BOTOES", "price": 100, "icon": "clube"},
	{"id": "coroa", "name_key": "LOJA_ITEM_COROA", "category": "button", "cat_key": "LOJA_CAT_BOTOES", "price": 120, "icon": "clube"},
	{"id": "arte_deco", "name_key": "LOJA_ITEM_ARTE_DECO", "category": "button", "cat_key": "LOJA_CAT_BOTOES", "price": 90, "icon": "clube"},
	{"id": "porcelana", "name_key": "LOJA_ITEM_PORCELANA", "category": "button", "cat_key": "LOJA_CAT_BOTOES", "price": 80, "icon": "clube"},
	{"id": "turbina", "name_key": "LOJA_ITEM_TURBINA", "category": "button", "cat_key": "LOJA_CAT_BOTOES", "price": 110, "icon": "clube"},
	{"id": "chevron", "name_key": "LOJA_ITEM_CHEVRON", "category": "uniform", "cat_key": "LOJA_CAT_UNIFORMES", "price": 75, "icon": "uniforme"},
	{"id": "duas_faixas", "name_key": "LOJA_ITEM_DUAS_FAIXAS", "category": "uniform", "cat_key": "LOJA_CAT_UNIFORMES", "price": 75, "icon": "uniforme"},
	{"id": "losangos", "name_key": "LOJA_ITEM_LOSANGOS", "category": "uniform", "cat_key": "LOJA_CAT_UNIFORMES", "price": 85, "icon": "uniforme"},
	{"id": "rede_ouro", "name_key": "LOJA_ITEM_REDE_OURO", "category": "net", "cat_key": "LOJA_CAT_CAMPOS", "price": 150, "icon": "gol"},
	{"id": "gramado_listrado", "name_key": "LOJA_ITEM_GRAMADO_LISTRADO", "category": "pitch", "cat_key": "LOJA_CAT_CAMPOS", "price": 150, "icon": "estadio"},
]

var _filter_cat := "all"


func refresh() -> void:
	ScreenBase.clear(content)
	var g := game()
	if g == null or not g.has_club():
		show_empty("loja", tr("LOJA_EM_BREVE"), tr("LOJA_EM_BREVE_TEXTO"))
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox := UiKit.vbox(DesignTokens.SPACING_MD)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	content.add_child(scroll)

	# 1. Cabeçalho de Saldo e Regra Ética
	var header_card := UiKit.card(UiKit.PAPER, "ui_cartao")
	var hh := UiKit.hbox(DesignTokens.SPACING_MD)
	hh.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bal_box := UiKit.hbox(DesignTokens.SPACING_SM)
	bal_box.add_child(UiKit.icon("colecao", 28))
	var bal_lbl := UiKit.label(tr("LOJA_SALDO_CREDITOS") % g.credits(), UiKit.FONT_TITLE, UiKit.YELLOW, true)
	bal_lbl.name = "CreditsBalance"
	bal_box.add_child(bal_lbl)
	hh.add_child(bal_box)

	var rule_box := UiKit.hbox(DesignTokens.SPACING_SM)
	rule_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule_box.alignment = BoxContainer.ALIGNMENT_END
	rule_box.add_child(UiKit.icon("confirmar", 20))
	rule_box.add_child(UiKit.label(tr("LOJA_SEM_BONUS"), UiKit.FONT_SMALL, UiKit.MUTED, false))
	hh.add_child(rule_box)

	header_card.add_child(hh)
	vbox.add_child(header_card)

	# 2. Filtros de Categoria
	var cat_flow := HFlowContainer.new()
	cat_flow.add_theme_constant_override("h_separation", DesignTokens.SPACING_SM)
	cat_flow.add_theme_constant_override("v_separation", DesignTokens.SPACING_SM)

	var filter_all := UiKit.button(tr("LOJA_CAT_TODOS"), "primary" if _filter_cat == "all" else "secondary", "colecao", 36)
	filter_all.pressed.connect(func() -> void:
		_filter_cat = "all"
		refresh()
	)
	cat_flow.add_child(filter_all)

	for cat_info in [["button", "LOJA_CAT_BOTOES", "clube"], ["uniform", "LOJA_CAT_UNIFORMES", "uniforme"], ["pitch", "LOJA_CAT_CAMPOS", "estadio"]]:
		var c_id: String = cat_info[0]
		var c_key: String = cat_info[1]
		var c_icon: String = cat_info[2]
		var btn := UiKit.button(tr(c_key), "primary" if _filter_cat == c_id else "secondary", c_icon, 36)
		btn.pressed.connect(func() -> void:
			_filter_cat = c_id
			refresh()
		)
		cat_flow.add_child(btn)
	vbox.add_child(cat_flow)

	# 3. Grid de Itens Cosméticos
	var grid := GridContainer.new()
	grid.columns = 2 if size.x < 700.0 else 3
	grid.add_theme_constant_override("h_separation", DesignTokens.SPACING_MD)
	grid.add_theme_constant_override("v_separation", DesignTokens.SPACING_MD)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for item in CATALOG:
		if _filter_cat != "all" and item.category != _filter_cat and not (_filter_cat == "pitch" and item.category in ["pitch", "net"]):
			continue
		grid.add_child(_create_item_card(g, item))

	vbox.add_child(grid)
	show_ready()


func _create_item_card(g: GameStore, item: Dictionary) -> Control:
	var card := UiKit.card(UiKit.PAPER, "ui_cartao")
	card.custom_minimum_size = Vector2(160, 140)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cv := UiKit.vbox(DesignTokens.SPACING_SM)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var top_row := UiKit.hbox(DesignTokens.SPACING_SM)
	top_row.add_child(UiKit.icon(item.icon, 24))
	var name_lbl := UiKit.label(tr(item.name_key), UiKit.FONT_BODY, UiKit.INK, true)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(name_lbl)
	cv.add_child(top_row)

	var cat_lbl := UiKit.label(tr(item.cat_key), UiKit.FONT_SMALL, UiKit.MUTED, false)
	cv.add_child(cat_lbl)

	var item_id: String = item.id
	var item_cat: String = item.category
	var price: int = int(item.price)

	var is_unlocked := g.is_cosmetic_unlocked(item_id)
	var is_equipped := g.active_cosmetic(item_cat) == item_id

	if is_equipped:
		var btn_equipped := UiKit.button(tr("LOJA_BTN_EQUIPADO"), "secondary", "confirmar", 36)
		btn_equipped.name = "Equipped_" + item_id
		btn_equipped.disabled = true
		cv.add_child(btn_equipped)
	elif is_unlocked:
		var btn_equip := UiKit.button(tr("LOJA_BTN_EQUIPAR"), "primary", "confirmar", 36)
		btn_equip.name = "Equip_" + item_id
		btn_equip.pressed.connect(func() -> void:
			g.equip_cosmetic(item_cat, item_id)
			refresh()
		)
		cv.add_child(btn_equip)
	else:
		var can_buy := g.can_afford(price)
		var btn_buy := UiKit.button(tr("LOJA_BTN_COMPRAR") % price, "primary" if can_buy else "secondary", "colecao", 36)
		btn_buy.name = "Buy_" + item_id
		btn_buy.disabled = not can_buy
		if not can_buy:
			btn_buy.tooltip_text = tr("LOJA_SALDO_INSUFICIENTE")
		else:
			btn_buy.pressed.connect(func() -> void:
				g.buy_cosmetic(item_id, price)
				g.equip_cosmetic(item_cat, item_id)
				refresh()
			)
		cv.add_child(btn_buy)

	card.add_child(cv)
	return card
