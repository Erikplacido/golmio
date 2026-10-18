class_name FirstLineupScreen
extends ScreenBase
## O03 · Primeira escalação (tela cheia): o time já vem escalado; o jogador só confirma ou troca dois
## atletas de lugar (toca num, depois no outro). Ensina fazendo, com uma dica guiada sobre o campo.
## Mentalidade, pênaltis e regras ficam para depois. "Jogar estreia" leva à partida de estreia (O04),
## um amistoso contra o adversário mais parelho, sem resultado combinado.

var _pitch: TacticalPitch
var _selected := -1
var _strength: Label
var _tip_shown := false


func _ready() -> void:
	max_content_width = 760.0
	super._ready()


func build() -> void:
	var t := UiKit.title(tr("ESTREIA_ESCALACAO_TITULO"), UiKit.FONT_DISPLAY)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.wrap(t)
	content.add_child(t)
	var sub := UiKit.label(tr("ESTREIA_ESCALACAO_TEXTO"), UiKit.FONT_BODY, UiKit.MUTED, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(sub)
	_strength = UiKit.label("", UiKit.FONT_H2)
	_strength.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_strength)
	_pitch = TacticalPitch.new()
	_pitch.name = "Pitch"
	_pitch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pitch.slot_clicked.connect(_on_slot)
	content.add_child(_pitch)
	_pitch.custom_minimum_size = Vector2(240, 300)
	var play := UiKit.button(tr("ESTREIA_JOGAR"), "primary", "jogar", 56)
	play.name = "Play"
	play.pressed.connect(_play)
	content.add_child(play)


func refresh() -> void:
	var g := game()
	if g == null or not g.has_club():
		show_empty("clube", tr("INICIO_SEM_CLUBE_TITULO"), tr("INICIO_SEM_CLUBE_TEXTO"))
		return
	_render()
	show_ready()
	if not _tip_shown:
		_tip_shown = true
		_tip.call_deferred()


func _render() -> void:
	var g := game()
	var t := g.tactics()
	var formation := str(t.get("formation", GameStore.DEFAULT_FORMATION))
	var raw := DemoData.formation(formation)
	var functions := GameTerms.roles_for_formation(raw)
	var starters: Array = t.get("starting_11", [])
	var slots: Array = []
	for i in raw.size():
		var aid := str(starters[i]) if i < starters.size() else ""
		slots.append({"role": raw[i].get("role", "MID"), "function": functions[i], "x": raw[i].x, "y": raw[i].y,
			"athlete_id": aid, "athlete_data": g.athlete(aid)})
	_pitch.setup_formation(formation, slots, g.kit())
	_pitch.set_special_roles(str(t.get("captain_id", "")), str(t.get("penalty_taker_id", "")), str(t.get("freekick_taker_id", "")))
	_pitch.select_slot(_selected)
	var s := GameStore.strength(g.starters())
	_strength.text = tr("INICIO_FORCA") % [s.ovr, s.def, s.mid, s.fwd]


## Toque num atleta e depois em outro: trocam de vaga (alternativa ao arrastar).
func _on_slot(index: int, _athlete_id: String) -> void:
	if _selected < 0:
		_selected = index
		_pitch.select_slot(index)
		return
	if _selected != index:
		var g := game()
		var t := g.tactics()
		var starters: Array = t.get("starting_11", [])
		if _selected < starters.size() and index < starters.size():
			var tmp = starters[_selected]
			starters[_selected] = starters[index]
			starters[index] = tmp
			t["starting_11"] = starters
			g.save_tactics(t)
	_selected = -1
	_render()


func _tip() -> void:
	var r := router()
	if r and is_visible_in_tree():
		r.overlays.coach([{"target": _pitch, "title": tr("ESTREIA_DICA_TROCA_TITULO"), "text": tr("ESTREIA_DICA_TROCA_TEXTO")}])


## Estreia: amistoso contra o adversário de força mais próxima (sem resultado combinado).
func _play() -> void:
	var g := game()
	var mine := int(GameStore.strength(g.starters()).ovr)
	var best: Dictionary = {}
	for o in g.friendly_opponents():
		if best.is_empty() or absi(int(o.strength.ovr) - mine) < absi(int(best.strength.ovr) - mine):
			best = o
	g.advance_onboarding(GameStore.STAGE_DEBUT)
	var res := g.prepare_match(GameStore.KIND_FRIENDLY, best, {"debut": true})
	if not bool(res.get("ok", false)):
		if router():
			router().overlays.toast(str((res.get("errors", [""]) as Array)[0]), "error")
		return
	go("match")


func handle_back() -> bool:
	return true
