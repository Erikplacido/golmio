class_name MatchSummaryOverlay
extends CanvasLayer
## Intervalo (P05) e fim de jogo da partida do jogador: placar, posse, chutes e xG, lances do período
## e uma ação ("Continuar" no intervalo, "Ver resultado" no fim). Sem decisões táticas: no oficial o
## resultado já está resolvido (PLANO_DE_TELAS, decisões em aberto).

signal action_pressed

const CARD_MAX_W := 560.0

var _root: Control
var _settings: Node


func _ready() -> void:
	layer = 18   # acima das vinhetas (15), abaixo das sobreposições do sistema (90)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings = get_node_or_null("/root/Settings")
	visible = false


func is_open() -> bool:
	return visible


## `final`: fim de jogo (todos os lances); senão o intervalo (só o 1º tempo).
func open(ctx: MatchContext, final: bool, names: Dictionary) -> void:
	if _root:
		_root.queue_free()
	var k: float = _settings.readability_scale() if _settings else 1.0
	var vp := get_viewport().get_visible_rect().size
	_root = Control.new()
	_root.theme = DesignTokens.base_theme()
	_root.scale = Vector2(k, k)
	_root.size = vp / k
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var card := UiKit.card(DesignTokens.COLOR_BG_CARD, "ui_janela")
	var w := minf(CARD_MAX_W, _root.size.x - 24.0)
	card.custom_minimum_size.x = w
	_root.add_child(card)
	var v := UiKit.vbox(DesignTokens.SPACING_SM)
	card.add_child(v)
	_settle_card.call_deferred(card, w)
	var head := UiKit.title(tr("PARTIDA_FIM") if final else tr("PARTIDA_INTERVALO"), UiKit.FONT_TITLE)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var score := UiKit.title("%s  %d × %d  %s" % [ctx.home.setup.short_name, ctx.home.stats.goals,
		ctx.away.stats.goals, ctx.away.setup.short_name], UiKit.FONT_DISPLAY)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(score)
	var stats := MatchStats.from_ctx(ctx)
	for r in MatchStats.rows(stats).slice(0, 4):
		v.add_child(CompareBar.make(r[0], r[1], r[2], ctx.home.color, ctx.away.color, r[3]))
	var lances := MatchStats.highlights(ctx.events, "" if final else "1T")
	if not lances.is_empty():
		v.add_child(UiKit.separator())
		for h in lances.slice(maxi(lances.size() - 6, 0)):
			var row := UiKit.hbox(DesignTokens.SPACING_SM)
			row.add_child(UiKit.icon(MatchStats.icon_for(h), 20))
			var l := UiKit.label(MatchStats.describe(h, names), UiKit.FONT_SMALL, UiKit.INK, true)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.custom_minimum_size.x = w - 90.0
			row.add_child(l)
			v.add_child(row)
	var b := UiKit.button(tr("PARTIDA_VER_RESULTADO") if final else tr("PARTIDA_CONTINUAR"), "primary", "jogar", 56)
	b.name = "Action"
	b.pressed.connect(func() -> void: action_pressed.emit())
	v.add_child(b)
	card.reset_size()
	var sz := card.get_combined_minimum_size()
	card.size = Vector2(w, sz.y)
	card.position = (_root.size - card.size) / 2.0
	visible = true
	b.grab_focus.call_deferred()


## Recentraliza depois que o layout assentou (rótulos com quebra de linha mudam de altura).
func _settle_card(card: Control, w: float) -> void:
	if not is_instance_valid(card) or _root == null:
		return
	card.size = Vector2(w, card.get_combined_minimum_size().y)
	card.position = (_root.size - card.size) / 2.0


func close() -> void:
	visible = false
	if _root:
		_root.queue_free()
		_root = null
