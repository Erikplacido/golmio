class_name StarterPackScreen
extends ScreenBase
## O02 · Pacote inicial (tela cheia): o primeiro momento de emoção. Os atletas já chegaram ao clube
## na criação (OnboardingService); aqui são revelados: 3 destaques viram um a um (toque ou sozinhos),
## depois o elenco inteiro em grade. Pular sempre disponível; reduzir movimento troca a virada pela
## revelação simples. Continuar leva à primeira escalação (O03).

const HIGHLIGHTS := 3
const FLIP_GAP := 0.7
const BIG_W := 190.0
const SMALL_W := 120.0

var _phase := "highlights"   # highlights | grid
var _cards: Array = []       # StickerCard dos destaques
var _revealed := 0
var _row: HBoxContainer
var _footer: HBoxContainer
var _timer: Timer


func _ready() -> void:
	max_content_width = 1100.0
	super._ready()


func build() -> void:
	var head := UiKit.vbox(DesignTokens.SPACING_XS)
	var t := UiKit.title(tr("ESTREIA_PACOTE_TITULO"), UiKit.FONT_DISPLAY)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.wrap(t)
	head.add_child(t)
	var sub := UiKit.label("", UiKit.FONT_BODY, UiKit.MUTED, true)
	sub.name = "Subtitle"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(sub)
	content.add_child(head)
	_timer = Timer.new()
	_timer.wait_time = FLIP_GAP
	_timer.timeout.connect(_reveal_next)
	add_child(_timer)


func refresh() -> void:
	var g := game()
	if g == null or g.squad().is_empty():
		show_empty("pacotes", tr("ESTREIA_PACOTE_VAZIO"), tr("ESTREIA_PACOTE_VAZIO_TEXTO"),
			tr("UI_CONTINUAR"), _continue)
		return
	if _phase == "grid":
		_show_grid(false)
	else:
		_show_highlights()
	show_ready()


## Melhores primeiro pelo nível da carta e pelo OVR; os destaques viram do menor para o maior.
func _ranked() -> Array:
	var list: Array = game().squad().duplicate()
	list.sort_custom(func(x: Athlete, y: Athlete) -> bool:
		var rx := int(StickerCard.tier_style(x.tier()).get("rank", 0))
		var ry := int(StickerCard.tier_style(y.tier()).get("rank", 0))
		if rx != ry:
			return rx > ry
		return GameStore.overall(x) > GameStore.overall(y))
	return list


func _reduce_motion() -> bool:
	var s := get_node_or_null("/root/Settings")
	return bool(s.get_value("reduce_motion")) if s else false


func _clear_body() -> void:
	for c in content.get_children().slice(1):
		content.remove_child(c)
		c.queue_free()


func _show_highlights() -> void:
	_clear_body()
	var g := game()
	(content.get_child(0).get_node("Subtitle") as Label).text = tr("ESTREIA_PACOTE_TEXTO") % g.squad().size()
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	_row = UiKit.hbox(DesignTokens.SPACING_XL)
	center.add_child(_row)
	_cards.clear()
	_revealed = 0
	var top: Array = _ranked().slice(0, HIGHLIGHTS)
	top.reverse()   # suspense: o melhor vira por último
	var lw := logical_size().x
	var w := minf(BIG_W, (lw - 2.0 * PAD - 2.0 * DesignTokens.SPACING_XL) / HIGHLIGHTS) if lw > 0.0 else BIG_W
	for a: Athlete in top:
		var card := _card(a, w)
		card.set_face_up(false)
		card.pressed.connect(_reveal_next)
		_row.add_child(card)
		_cards.append(card)
	_footer = UiKit.hbox(DesignTokens.SPACING_SM)
	_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	var skip := UiKit.button(tr("UI_PULAR"), "secondary", "pular")
	skip.custom_minimum_size.x = 160
	skip.pressed.connect(func() -> void: _show_grid(true))
	_footer.add_child(skip)
	content.add_child(_footer)
	if _timer.is_inside_tree():
		_timer.start()
	else:
		_timer.autostart = true


func _card(a: Athlete, w: float) -> StickerCard:
	var card := StickerCard.new()
	card.size = Vector2(w, w * StickerCard.ASPECT)
	card.custom_minimum_size = card.size
	card.set_card(GameStore.card_for(a), game().kit(), null, a.attributes)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return card


func _reveal_next() -> void:
	if _phase != "highlights" or _revealed >= _cards.size():
		return
	var card: StickerCard = _cards[_revealed]
	_revealed += 1
	SfxService.play(SfxService.reveal_sound(int(card.style().get("rank", 1))))
	if _reduce_motion():
		card.set_face_up(true)
	else:
		card.flip_to_front()
	if _revealed >= _cards.size():
		_timer.stop()
		_finish_highlights()


func _finish_highlights() -> void:
	ScreenBase.clear(_footer)
	var all := UiKit.button(tr("ESTREIA_VER_ELENCO"), "primary", "elenco")
	all.custom_minimum_size.x = 260
	all.pressed.connect(func() -> void: _show_grid(false))
	_footer.add_child(all)


## Elenco inteiro em grade. `animate`: veio do Pular (vira rápido, em sequência).
func _show_grid(animate: bool) -> void:
	_phase = "grid"
	_timer.stop()
	_clear_body()
	var g := game()
	(content.get_child(0).get_node("Subtitle") as Label).text = tr("ESTREIA_ELENCO_TEXTO") % [g.squad().size(), g.squad_limit()]
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", DesignTokens.SPACING_MD)
	flow.add_theme_constant_override("v_separation", DesignTokens.SPACING_MD)
	var i := 0
	for a: Athlete in _ranked():
		var card := _card(a, SMALL_W)
		card.set_face_up(not animate or _reduce_motion())
		flow.add_child(card)
		if animate and not _reduce_motion():
			card.flip_to_front.call_deferred(0.3, 0.05 * i)
		i += 1
	content.add_child(UiKit.scroll(flow))
	var footer := UiKit.hbox(DesignTokens.SPACING_SM)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	var go_on := UiKit.button(tr("UI_CONTINUAR"), "primary", "jogar")
	go_on.name = "Continue"
	go_on.custom_minimum_size.x = 260
	go_on.pressed.connect(_continue)
	footer.add_child(go_on)
	content.add_child(footer)


func _continue() -> void:
	var g := game()
	if g:
		g.advance_onboarding(GameStore.STAGE_FIRST_LINEUP)
	go("first_lineup")


## Na estreia não há tela anterior: voltar equivale a pular para a grade.
func handle_back() -> bool:
	if _phase == "highlights":
		_show_grid(false)
	return true
