class_name ModesScreen
extends ScreenBase
## H02 · Modos e adversário: escolher o amistoso e o adversário, sabendo antes que não vale idade
## nem tabela (a regra de ouro fica no topo). Adversários com a força comparada à do seu time;
## filtro Mais fraco · Parelho · Mais forte. Código (H04) e Várzea chegam depois e aparecem
## bloqueados com o motivo.

## Diferença de OVR até a qual o adversário conta como "parelho".
const EVEN_RANGE := 3

var _filter := "all"
var _list: VBoxContainer


func build() -> void:
	var tabs := UiKit.segmented([["friendly", tr("MODO_AMISTOSO")], ["code", tr("MODO_CODIGO")]],
		"friendly", func(_id: String) -> void: pass, ["code"], tr("UI_EM_BREVE"))
	content.add_child(tabs)
	var rule := UiKit.card(Color("#e3f0f6"), "ui_aviso")
	var rh := UiKit.hbox(DesignTokens.SPACING_SM)
	rh.add_child(UiKit.icon("calendario", 32))
	var rv := UiKit.vbox(2)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(UiKit.title(tr("MODOS_REGRA_TITULO"), UiKit.FONT_H2))
	rv.add_child(UiKit.label(tr("MODOS_REGRA_TEXTO"), UiKit.FONT_BODY, UiKit.INK, true))
	rh.add_child(rv)
	rule.add_child(rh)
	content.add_child(rule)
	var filters := UiKit.hbox(DesignTokens.SPACING_XS)
	filters.name = "Filters"
	content.add_child(filters)
	_list = UiKit.vbox(DesignTokens.SPACING_SM)
	_list.name = "Opponents"
	content.add_child(UiKit.scroll(_list))


func refresh() -> void:
	var g := game()
	if g == null or not g.has_club():
		show_empty("clube", tr("INICIO_SEM_CLUBE_TITULO"), tr("INICIO_SEM_CLUBE_TEXTO"))
		return
	_render_filters()
	var mine := GameStore.strength(g.starters())
	var opps := g.friendly_opponents().filter(func(o: Dictionary) -> bool: return _passes(o, mine))
	ScreenBase.clear(_list)
	if g.friendly_opponents().is_empty():
		show_empty("olheiros", tr("MODOS_SEM_ADVERSARIOS"), tr("MODOS_SEM_ADVERSARIOS_TEXTO"))
		return
	if opps.is_empty():
		_list.add_child(UiKit.label(tr("MODOS_FILTRO_VAZIO"), UiKit.FONT_BODY, UiKit.MUTED, true))
	for o in opps:
		_list.add_child(_opponent_row(o, mine))
	show_ready()


func _render_filters() -> void:
	var box: HBoxContainer = content.get_node("Filters")
	ScreenBase.clear(box)
	box.add_child(UiKit.segmented([["all", tr("MODOS_TODOS")], ["weaker", tr("MODOS_MAIS_FRACO")],
		["even", tr("MODOS_PARELHO")], ["stronger", tr("MODOS_MAIS_FORTE")]], _filter,
		func(id: String) -> void:
			_filter = id
			refresh()
	))
	box.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _passes(o: Dictionary, mine: Dictionary) -> bool:
	var diff := int(o.strength.ovr) - int(mine.ovr)
	match _filter:
		"weaker":
			return diff < -EVEN_RANGE
		"even":
			return absi(diff) <= EVEN_RANGE
		"stronger":
			return diff > EVEN_RANGE
	return true


func _opponent_row(o: Dictionary, mine: Dictionary) -> Control:
	var row := UiKit.list_row()
	# Fluxo: numa tela larga é uma linha só; no celular o selo e o Escolher descem para a direita.
	var h := HFlowContainer.new()
	h.alignment = FlowContainer.ALIGNMENT_END
	h.add_theme_constant_override("h_separation", DesignTokens.SPACING_MD)
	h.add_theme_constant_override("v_separation", DesignTokens.SPACING_SM)
	row.add_child(h)
	h.add_child(ClubCrest.for_colors(o.color, o.secondary, str(o.short_name), 44))
	var info := UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UiKit.title(str(o.name), UiKit.FONT_H2))
	var s: Dictionary = o.strength
	info.add_child(UiKit.label(tr("INICIO_FORCA") % [s.ovr, s.def, s.mid, s.fwd], UiKit.FONT_SMALL, UiKit.MUTED))
	h.add_child(info)
	var diff := int(s.ovr) - int(mine.ovr)
	var tag := tr("MODOS_PARELHO")
	var col := UiKit.BLUE
	if diff > EVEN_RANGE:
		tag = tr("MODOS_MAIS_FORTE_N") % diff
		col = UiKit.RED
	elif diff < -EVEN_RANGE:
		tag = tr("MODOS_MAIS_FRACO_N") % -diff
		col = UiKit.GREEN
	h.add_child(UiKit.chip(tag, col))
	var pick := UiKit.button(tr("MODOS_ESCOLHER"), "info", "confirmar", 44)
	pick.pressed.connect(func() -> void:
		go("prematch", {"kind": GameStore.KIND_FRIENDLY, "opponent": str(o.key)}))
	h.add_child(pick)
	return row
