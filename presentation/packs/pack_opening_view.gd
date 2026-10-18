class_name PackOpeningView
extends Control
## Tela de demonstração da abertura de pacotes (roda sozinha):
##   godot --path jogo res://presentation/packs/pack_opening_view.tscn
##
## Monta um registro próprio a partir de rulesets/dev.json com athlete_generator e packs ligados
## explicitamente (mesmo que o dev.json ainda não os ligue), um mundo com os clubes de
## demonstração (DemoData; o clube Rubro tem 16 atletas e 14 vagas) e concede um pacote de cada
## tipo de packs.types com sementes do LocalBackend.new_seed(). A tela mostra o inventário, a
## prévia do pacote (conteúdo possível e probabilidades), Abrir/Guardar, a revelação carta a carta
## (PackOpeningController + StickerCard, com Tween) e, ao concluir, o elenco atualizado. Elenco sem
## vagas (squad_full) mostra "libere N vagas"; a caixa "Simular elenco cheio" lota o elenco com
## vagas fictícias SÓ nesta demonstração (no jogo, liberar vagas é operação do servidor).
##
## Argumentos (depois de --):
##   --snapshot=<arquivo.png>   abre um pacote sozinho, revela tudo, salva a captura e sai
##   --pack=gol                 tipo aberto no snapshot (padrão: gol)
##   --screen=reveal            tela capturada: reveal | squad | inventory
##   --seed=<int>               sementes dos pacotes derivadas deste número (captura reproduzível)
##   --fill-squad               começa com o elenco lotado (demonstra squad_full)

const DEV_RULESET := "res://rulesets/dev.json"
const REQUIRED_MECHANICS := ["athlete_generator", "packs"]
const DEMO_CLUB_ID := "demo_rubro"
const DEMO_SOURCE := "demo"
const FILLER_PREFIX := "demo_vaga_"
const HOOK_GRANT := "packs.grant"
const HOOK_INVENTORY := "packs.inventory"
const HOOK_TYPES := "packs.types"
const STATUS_SEALED := "sealed"
const ST := PackOpeningController.State
## Aparência do pacote por tipo (a: topo do degradê, b: base, accent: texto).
const PACK_STYLES := {
	"comum": {"a": "#43a06a", "b": "#17482d", "accent": "#eafff0"},
	"raro": {"a": "#4a7cf0", "b": "#162c6b", "accent": "#e3ecff"},
	"gol": {"a": "#f5bd0b", "b": "#a8231b", "accent": "#fff6d1"},
}
const DEFAULT_PACK_STYLE := {"a": "#9aa0a8", "b": "#3f444b", "accent": "#ffffff"}
const TOP_BAR_H := 58.0
const REVEAL_BAR_H := 64.0
const MARGIN := 20.0
const CARD_GAP := 14.0
const MAX_CARD_W := 240.0
## Cartas de slot colecionável são menores que as de atleta.
const RESERVED_SCALE := 0.68
const STAGE_TITLE_H := 34.0
const CAPTION_H := 26.0
const DEAL_STAGGER := 0.06
const DEAL_TIME := 0.32
const FLIP_STAGGER := 0.22
const FLIP_TIME := 0.45
const SQUAD_CARD_W := 112.0
# Tema Golmio (DesignTokens). GOLD virou tinta: é usado em títulos e números, e o dourado não se lê
# sobre o papel creme; a cor de destaque dos botões vem de DesignTokens.style_button.
const BG_A := DesignTokens.COLOR_PAPER
const BG_B := DesignTokens.COLOR_PAPER_SURFACE
const TEXT := DesignTokens.COLOR_TEXT_PRIMARY
const TEXT_DIM := DesignTokens.COLOR_TEXT_SECONDARY
const GOLD := DesignTokens.COLOR_TEXT_PRIMARY

enum Screen {INVENTORY, REVEAL, SQUAD}

var registry: MechanicRegistry = null
var world: World = null
var club: Club = null
var controller: PackOpeningController = null
var kit: Dictionary = {}
var catalog: PortraitCatalog = null

var _types: Dictionary = {}
var _tier_order: Array = []
var _screen: Screen = Screen.INVENTORY
var _selected_pack: Dictionary = {}
var _cards: Array = []            # StickerCard na ordem de revelação
var _athletes_by_id: Dictionary = {}
var _batch_reveal := false
var _batch_index := 0
var _notice := ""
## Pacote cujo Abrir foi clicado e que está na animação de abertura ("" fora dela). Enquanto não
## vazio, o inventário, Abrir e Guardar ficam travados: abrir é irreversível e só pode valer
## para o pacote que o usuário confirmou.
var _opening_pack_id := ""

var _squad_label: Label
var _fill_check: Button
var _inventory_screen: Control
var _reveal_screen: Control
var _squad_screen: Control
var _inv_list: VBoxContainer
var _preview_empty: Label
var _preview_box: Control
var _pack_art: PackArt
var _pack_title: Label
var _pack_counts: Label
var _odds_grid: GridContainer
var _guarantee_label: Label
var _open_button: Button
var _keep_button: Button
var _back_button: Button
var _message: Label
var _stage: Control
var _stage_title: Label
var _caption: Label
var _reveal_status: Label
var _next_button: Button
var _all_button: Button
var _finish_button: Button
var _squad_title: Label
var _new_row: HBoxContainer
var _squad_grid: GridContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED   # papel de fundo repetido
	theme = _make_theme()
	registry = build_registry()
	world = build_world()
	club = world.clubs.get(DEMO_CLUB_ID)
	kit = PortraitRenderer.kit_for_club(club)
	catalog = PortraitCatalog.shared()
	var types: Variant = registry.bus.decide(HOOK_TYPES, {})
	if types is Dictionary:
		_types = types.get("types", {})
		_tier_order = types.get("tier_order", [])
	grant_demo_packs(registry, world, club, int(_arg("seed", "-1")))
	controller = PackOpeningController.for_registry(registry, world, club)
	controller.state_changed.connect(_on_state_changed)
	controller.opened.connect(_on_opened)
	controller.card_revealed.connect(_on_card_revealed)
	controller.delivered.connect(_on_delivered)
	controller.failed.connect(_on_failed)
	controller.blocked.connect(_on_blocked)
	_build_ui()
	if OS.get_cmdline_user_args().has("--fill-squad"):
		_fill_check.button_pressed = true
	_show_screen(Screen.INVENTORY)
	_refresh_inventory()
	_sync_ui()
	var snapshot := _arg("snapshot", "")
	if snapshot != "":
		_run_snapshot.call_deferred(snapshot)


func _exit_tree() -> void:
	if registry != null:
		registry.dispose()


# --- montagem do servidor local (estático: usado também pelos testes) ------------------------------

## Registro com as mecânicas de rulesets/dev.json e athlete_generator + packs ligadas à força.
static func build_registry(ruleset_path: String = DEV_RULESET) -> MechanicRegistry:
	var data := Ruleset.load_file(ruleset_path).to_dict()
	var mechanics: Dictionary = (data.get("mechanics", {}) as Dictionary).duplicate(true)
	for mid in REQUIRED_MECHANICS:
		var entry: Dictionary = mechanics.get(mid, {}) if mechanics.get(mid) is Dictionary else {}
		entry["enabled"] = true
		mechanics[mid] = entry
	data["mechanics"] = mechanics
	var reg := MechanicRegistry.new()
	reg.discover()
	reg.apply_ruleset(Ruleset.from_dict(data))
	return reg


## Mundo de demonstração (DemoData: Rubro e Anil, data 2026-09-27).
static func build_world() -> World:
	return DemoData.world()


## Concede ao clube um pacote de cada tipo de packs.types (na ordem dos tipos). base_seed >= 0
## deriva as sementes dele (reproduzível); senão cada uma vem de LocalBackend.new_seed().
## Devolve os pacotes concedidos.
static func grant_demo_packs(reg: MechanicRegistry, w: World, c: Club, base_seed: int = -1) -> Array:
	var granted: Array = []
	var types: Variant = reg.bus.decide(HOOK_TYPES, {})
	if not (types is Dictionary):
		return granted
	var backend := LocalBackend.new()
	for type_id in (types.get("types", {}) as Dictionary):
		if str(type_id) == "starter":
			continue
		var s := AthleteDna.derive_seed(base_seed, "demo:%s" % type_id) if base_seed >= 0 else backend.new_seed()
		var res: Variant = reg.bus.decide(HOOK_GRANT, {"world": w, "club": c, "type": str(type_id),
			"seed": s, "source": DEMO_SOURCE})
		if res is Dictionary and bool(res.get("ok", false)):
			granted.append(res.pack)
	return granted


# --- eventos do controlador --------------------------------------------------------------------------

func _on_state_changed(_from: int, to: int) -> void:
	match to:
		PackOpeningController.State.REVEALING, PackOpeningController.State.COMPLETE:
			_show_screen(Screen.REVEAL)
		PackOpeningController.State.DELIVERED:
			_show_screen(Screen.SQUAD)
		_:
			_show_screen(Screen.INVENTORY)
	_sync_ui()


func _on_opened(result: Dictionary) -> void:
	_athletes_by_id.clear()
	for a in result.get("athletes", []):
		if a is Athlete:
			_athletes_by_id[a.id] = a
	_notice = ""
	_build_cards()
	_refresh_inventory()


func _on_card_revealed(index: int, _card: Dictionary) -> void:
	if index < 0 or index >= _cards.size():
		return
	var delay := 0.0
	if _batch_reveal:
		delay = _batch_index * FLIP_STAGGER
		_batch_index += 1
	var sticker := _cards[index] as StickerCard
	sticker.flip_to_front(FLIP_TIME, delay)
	SfxService.play(SfxService.reveal_sound(int(sticker.style().get("rank", 0))), 0.0, delay + FLIP_TIME * 0.5)
	_sync_ui()


func _on_delivered(athlete_ids: Array) -> void:
	_notice = "%d atleta(s) entregue(s) ao elenco." % athlete_ids.size()
	_build_squad(athlete_ids)
	_refresh_inventory()


func _on_failed(error: String, info: Dictionary) -> void:
	_notice = "Não foi possível abrir o pacote (%s). %s" % [error, str(info.get("detail", ""))]
	SfxService.play("ui_erro")
	_sync_ui()


func _on_blocked(needed_slots: int, _info: Dictionary) -> void:
	_notice = "Elenco cheio: libere %d vaga%s para abrir este pacote." % [needed_slots, "" if needed_slots == 1 else "s"]
	SfxService.play("ui_erro")
	_sync_ui()


# --- ações da interface --------------------------------------------------------------------------------

func _select_pack(pack: Dictionary) -> void:
	if _opening_pack_id != "":
		return   # animação de Abrir em andamento: o pacote confirmado não pode ser trocado
	if controller.state == PackOpeningController.State.BLOCKED or controller.state == PackOpeningController.State.FAILED:
		controller.back()
	_notice = ""
	_selected_pack = pack.duplicate(true)
	controller.present(pack)
	_refresh_inventory()
	_sync_ui()


func _on_open_pressed() -> void:
	if controller.state != PackOpeningController.State.PREVIEW or _opening_pack_id != "":
		return
	_opening_pack_id = str(controller.pack.get("id", ""))
	_refresh_inventory()
	_sync_ui()
	var tw := create_tween()
	_pack_art.pivot_offset = _pack_art.size / 2.0
	for i in 3:
		tw.tween_property(_pack_art, "rotation", 0.06, 0.05)
		tw.tween_property(_pack_art, "rotation", -0.06, 0.05)
	tw.tween_property(_pack_art, "rotation", 0.0, 0.05)
	tw.parallel().tween_property(_pack_art, "scale", Vector2(1.08, 1.08), 0.1)
	tw.tween_callback(func() -> void:
		_pack_art.scale = Vector2.ONE
		var confirmed := _opening_pack_id
		_opening_pack_id = ""
		# Só abre o pacote confirmado no clique (open devolve false se a prévia mudou).
		if not controller.open(confirmed):
			_refresh_inventory()
			_sync_ui()
	)


func _on_keep_pressed() -> void:
	if _opening_pack_id != "":
		return
	if controller.keep():
		_notice = "Pacote guardado: continua lacrado no inventário."
		controller.back()
		_selected_pack = {}
		_sync_ui()


func _on_back_pressed() -> void:
	var was_blocked := controller.state == PackOpeningController.State.BLOCKED
	controller.back()
	if was_blocked and not _selected_pack.is_empty():
		_notice = ""
		controller.present(_selected_pack)   # volta à prévia do mesmo pacote
	else:
		_notice = ""
		_selected_pack = {}
	_sync_ui()


func _on_next_pressed() -> void:
	controller.reveal_next()


func _on_all_pressed() -> void:
	_reveal_all_staggered()


func _reveal_all_staggered() -> void:
	_batch_reveal = true
	_batch_index = 0
	controller.reveal_all()
	_batch_reveal = false


func _on_finish_pressed() -> void:
	controller.finish()


func _on_squad_back_pressed() -> void:
	controller.back()
	_selected_pack = {}
	_sync_ui()


func _on_card_pressed() -> void:
	if controller.state == PackOpeningController.State.REVEALING:
		controller.reveal_next()


## Demonstração de squad_full: lota o elenco com vagas fictícias (ou as remove).
func _on_fill_toggled(on: bool) -> void:
	var limit := int(registry.ruleset.core_param("squad_limit"))
	if on:
		var i := 0
		while club.athlete_ids.size() < limit:
			var fake := "%s%02d" % [FILLER_PREFIX, i]
			if not club.athlete_ids.has(fake):
				club.athlete_ids.append(fake)
			i += 1
	else:
		club.athlete_ids = club.athlete_ids.filter(func(x: Variant) -> bool: return not str(x).begins_with(FILLER_PREFIX))
	_fill_check.text = "Simular elenco cheio: %s" % ("sim" if on else "não")
	_sync_ui()


# --- telas -------------------------------------------------------------------------------------------

func _show_screen(s: Screen) -> void:
	_screen = s
	_inventory_screen.visible = s == Screen.INVENTORY
	_reveal_screen.visible = s == Screen.REVEAL
	_squad_screen.visible = s == Screen.SQUAD


## Atualiza textos e botões a partir do estado do controlador.
func _sync_ui() -> void:
	var st := controller.state
	var limit := int(registry.ruleset.core_param("squad_limit"))
	_squad_label.text = "Elenco %d/%d" % [club.athlete_ids.size(), limit]
	var showing_pack := st == ST.PREVIEW or st == ST.OPENING or st == ST.BLOCKED or (st == ST.FAILED and not _selected_pack.is_empty())
	_preview_box.visible = showing_pack
	_preview_empty.visible = not showing_pack
	if showing_pack:
		_fill_preview(controller.pack if not controller.pack.is_empty() else _selected_pack)
	_open_button.visible = st == ST.PREVIEW or st == ST.OPENING
	_keep_button.visible = st == ST.PREVIEW or st == ST.OPENING
	var animating := _opening_pack_id != ""
	_open_button.disabled = st != ST.PREVIEW or animating
	_keep_button.disabled = st != ST.PREVIEW or animating
	_back_button.visible = st == ST.BLOCKED or st == ST.FAILED
	_back_button.text = "Voltar à prévia" if st == ST.BLOCKED else "Voltar"
	_message.text = _notice
	_message.visible = _notice != ""
	_message.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_RED if st == ST.BLOCKED or st == ST.FAILED else GOLD)
	_preview_empty.text = "Escolha um pacote no inventário." if _notice == "" else _notice

	var total := controller.cards.size()
	_next_button.disabled = st != ST.REVEALING
	_all_button.disabled = st != ST.REVEALING
	_finish_button.disabled = st != ST.COMPLETE
	if st == ST.COMPLETE:
		_reveal_status.text = "Tudo revelado! Concluir leva ao elenco."
	else:
		_reveal_status.text = "Cartas reveladas: %d de %d — clique numa carta para revelar" % [controller.revealed_count, total]


func _fill_preview(pack: Dictionary) -> void:
	var type_id := str(pack.get("type", ""))
	var def: Dictionary = _types.get(type_id, {})
	var label := str(def.get("label", type_id))
	var n_ath := int(def.get("athletes", 0))
	var n_slots := int(def.get("collectible_slots", 0))
	_pack_art.setup(type_id, label, n_ath, n_slots, pack_style(type_id))
	_pack_title.text = "Pacote %s" % label
	_pack_counts.text = "%d atleta%s novo%s + %d colecionáve%s (em breve)" % [n_ath, "" if n_ath == 1 else "s",
		"" if n_ath == 1 else "s", n_slots, "l" if n_slots == 1 else "is"]
	for child in _odds_grid.get_children():
		_odds_grid.remove_child(child)
		child.queue_free()
	var weights: Dictionary = def.get("tier_weights", {})
	var total := 0.0
	for t in _tier_order:
		total += maxf(0.0, float(weights.get(t, 0)))
	for t in _tier_order:
		var w := maxf(0.0, float(weights.get(t, 0)))
		var style := StickerCard.tier_style(str(t))
		var chip := ColorRect.new()
		chip.color = Color(style.mid)
		chip.custom_minimum_size = Vector2(14, 14)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_odds_grid.add_child(chip)
		_odds_grid.add_child(_label(str(style.label), 15, TEXT))
		var pct := 100.0 * w / total if total > 0.0 else 0.0
		var pl := _label(("%.1f" % pct).replace(".", ",") + "%", 15, GOLD, true)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_odds_grid.add_child(pl)
	var g: Variant = def.get("guarantee")
	if g is Dictionary:
		var gs := StickerCard.tier_style(str(g.get("min_tier", "")))
		var cnt := int(g.get("count", 1))
		_guarantee_label.text = "Garantia: pelo menos %d atleta%s %s ou melhor." % [cnt, "" if cnt == 1 else "s", str(gs.label)]
	else:
		_guarantee_label.text = "Sem garantia de tier."
	_guarantee_label.visible = true


func _refresh_inventory() -> void:
	for child in _inv_list.get_children():
		_inv_list.remove_child(child)
		child.queue_free()
	var inv: Variant = registry.bus.decide(HOOK_INVENTORY, {"club": club})
	if not (inv is Array) or (inv as Array).is_empty():
		_inv_list.add_child(_label("Nenhum pacote.", 15, TEXT_DIM))
		return
	for pack in inv:
		_inv_list.add_child(_pack_row(pack))


func _pack_row(pack: Dictionary) -> Button:
	var type_id := str(pack.get("type", ""))
	var def: Dictionary = _types.get(type_id, {})
	var sealed := str(pack.get("status", "")) == STATUS_SEALED
	var selected := sealed and str(pack.get("id", "")) == str(_selected_pack.get("id", "-"))
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 62)
	b.text = "%s\n%s" % [str(def.get("label", type_id)),
		("Lacrado · %d atleta%s" % [int(def.get("athletes", 0)), "" if int(def.get("athletes", 0)) == 1 else "s"]) if sealed
		else "Aberto em %s" % str(pack.get("opened_on", ""))]
	var ps := pack_style(type_id)
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ps.b).darkened(0.1) if state_name != "hover" else Color(ps.b).lightened(0.12)
		if state_name == "disabled":
			sb.bg_color = DesignTokens.COLOR_BG_HOVER
		if state_name == "focus":
			sb.draw_center = false
			sb.border_color = Color(ps.accent, 0.8)
			sb.set_border_width_all(2)
		else:
			sb.border_color = Color(ps.a)
			sb.border_width_left = 8
			if selected:
				sb.border_color = Color(ps.accent)
				sb.set_border_width_all(3)
				sb.border_width_left = 8
				sb.bg_color = Color(ps.b).lightened(0.12)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 20
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		b.add_theme_stylebox_override(state_name, sb)
	b.add_theme_color_override("font_color", Color(ps.accent))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
	b.disabled = not sealed or _opening_pack_id != ""
	b.pressed.connect(_select_pack.bind(pack))
	return b


## Cartas do pacote aberto, viradas para baixo, "distribuídas" com Tween.
func _build_cards() -> void:
	for c in _cards:
		_stage.remove_child(c)
		c.queue_free()
	_cards.clear()
	var type_def: Dictionary = _types.get(str(controller.pack.get("type", "")), {})
	var ps := pack_style(str(controller.pack.get("type", "")))
	for i in controller.cards.size():
		var card: Dictionary = controller.cards[i]
		var sc := StickerCard.new()
		sc.back_colors = [Color(ps.b).darkened(0.15), Color(ps.b)]
		var stats: Dictionary = {}
		var athlete: Athlete = _athletes_by_id.get(str(card.get("athlete_id", "")))
		if athlete != null:
			stats = athlete.attributes
		sc.set_card(card, kit, catalog, stats)
		sc.pressed.connect(_on_card_pressed)
		_stage.add_child(sc)
		_cards.append(sc)
	_stage_title.text = "Pacote %s — %d cartas" % [str(type_def.get("label", "")), _cards.size()]
	_layout_stage()
	for i in _cards.size():
		var sc: StickerCard = _cards[i]
		var final_pos := sc.position
		sc.position = final_pos + Vector2(0, 40)
		sc.modulate.a = 0.0
		var tw := sc.create_tween()
		tw.tween_interval(i * DEAL_STAGGER)
		tw.tween_property(sc, "position", final_pos, DEAL_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(sc, "modulate:a", 1.0, DEAL_TIME)


## Posiciona as cartas no palco: atletas numa grade (colunas que maximizam o tamanho) e os slots
## colecionáveis numa fileira menor embaixo, tudo centrado.
func _layout_stage() -> void:
	if _stage == null:
		return
	var area := _stage.size
	var n_a := 0
	for c in _cards:
		if (c as StickerCard).is_athlete():
			n_a += 1
	var n_r := _cards.size() - n_a
	var has_r := 1.0 if n_r > 0 else 0.0
	var best_w := 0.0
	var best_cols := 1
	for cols in range(1, maxi(1, n_a) + 1):
		var rows := ceili(float(maxi(1, n_a)) / cols)
		var by_w := (area.x - (cols - 1) * CARD_GAP) / cols
		var by_h := (area.y - STAGE_TITLE_H - (rows - 1) * CARD_GAP - has_r * (CAPTION_H + CARD_GAP)) \
			/ (StickerCard.ASPECT * (rows + has_r * RESERVED_SCALE))
		var w := minf(minf(by_w, by_h), MAX_CARD_W)
		if w > best_w:
			best_w = w
			best_cols = cols
	var cw := maxf(best_w, 40.0)
	var ch := cw * StickerCard.ASPECT
	var rows_a := ceili(float(n_a) / best_cols) if n_a > 0 else 0
	var rw := cw * RESERVED_SCALE
	var rh := rw * StickerCard.ASPECT
	var block_h := STAGE_TITLE_H + rows_a * ch + maxf(0.0, rows_a - 1) * CARD_GAP + has_r * (CARD_GAP + CAPTION_H + rh)
	var y0 := maxf(0.0, (area.y - block_h) / 2.0)
	_stage_title.position = Vector2(0, y0)
	_stage_title.size = Vector2(area.x, STAGE_TITLE_H)
	var y := y0 + STAGE_TITLE_H
	var k := 0
	for r in rows_a:
		var in_row := mini(best_cols, n_a - r * best_cols)
		var row_w := in_row * cw + (in_row - 1) * CARD_GAP
		var x := (area.x - row_w) / 2.0
		for j in in_row:
			var sc: StickerCard = _cards[k]
			sc.size = Vector2(cw, ch)
			sc.position = Vector2(x + j * (cw + CARD_GAP), y + r * (ch + CARD_GAP))
			sc.pivot_offset = sc.size / 2.0
			k += 1
	y += rows_a * ch + maxf(0.0, rows_a - 1) * CARD_GAP
	_caption.visible = n_r > 0
	if n_r > 0:
		y += CARD_GAP
		_caption.position = Vector2(0, y)
		_caption.size = Vector2(area.x, CAPTION_H)
		y += CAPTION_H
		var row_w := n_r * rw + (n_r - 1) * CARD_GAP
		var x := (area.x - row_w) / 2.0
		for j in n_r:
			var sc: StickerCard = _cards[k]
			sc.size = Vector2(rw, rh)
			sc.position = Vector2(x + j * (rw + CARD_GAP), y)
			sc.pivot_offset = sc.size / 2.0
			k += 1


## Elenco depois da entrega: as figurinhas novas em cima e a lista completa embaixo.
func _build_squad(new_ids: Array) -> void:
	for child in _new_row.get_children():
		_new_row.remove_child(child)
		child.queue_free()
	for child in _squad_grid.get_children():
		_squad_grid.remove_child(child)
		child.queue_free()
	var limit := int(registry.ruleset.core_param("squad_limit"))
	_squad_title.text = "Elenco atualizado — %s (%d/%d)" % [club.name, club.athlete_ids.size(), limit]
	for c in controller.cards:
		if str(c.get("kind", "")) != StickerCard.KIND_ATHLETE:
			continue
		var sc := StickerCard.new()
		sc.custom_minimum_size = Vector2(SQUAD_CARD_W, SQUAD_CARD_W * StickerCard.ASPECT)
		sc.size = sc.custom_minimum_size
		var athlete: Athlete = _athletes_by_id.get(str(c.get("athlete_id", "")))
		sc.set_card(c, kit, catalog, athlete.attributes if athlete != null else {})
		sc.set_face_up(true)
		sc.glow = 0.0
		_new_row.add_child(sc)
	for aid in club.athlete_ids:
		_squad_grid.add_child(_squad_row(str(aid), new_ids.has(aid)))


func _squad_row(aid: String, is_new: bool) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = DesignTokens.COLOR_BG_SURFACE if not is_new else Color(DesignTokens.COLOR_ACCENT_YELLOW, 0.35)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(330, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var athlete: Athlete = world.athletes.get(aid)
	var chip := ColorRect.new()
	chip.custom_minimum_size = Vector2(8, 18)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)
	if athlete == null:
		chip.color = Color("#555555")
		row.add_child(_label("vaga ocupada (demonstração)", 14, TEXT_DIM))
		return panel
	var style := StickerCard.tier_style(athlete.tier())
	chip.color = Color(style.mid) if athlete.tier() != "" else Color("#6b7b72")
	var pos := _label(StickerCard.position_label(athlete.position), 13, GOLD, true)
	pos.custom_minimum_size = Vector2(34, 0)
	row.add_child(pos)
	var name_label := _label(athlete.name, 14, TEXT, is_new)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	row.add_child(_label(athlete.nationality, 13, TEXT_DIM))
	if is_new:
		row.add_child(_label("NOVO · %s" % str(style.label).to_upper(), 12, GOLD, true))
	return panel


# --- construção da interface -------------------------------------------------------------------------

func _build_ui() -> void:
	# Barra do topo.
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = TOP_BAR_H
	var top_sb := StyleBoxFlat.new()
	top_sb.bg_color = DesignTokens.COLOR_BG_SURFACE
	top_sb.border_color = GOLD
	top_sb.border_width_bottom = 2
	top_sb.content_margin_left = MARGIN
	top_sb.content_margin_right = MARGIN
	top.add_theme_stylebox_override("panel", top_sb)
	add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 18)
	top.add_child(bar)
	bar.add_child(_label("FOTEBA · Pacotes de figurinhas", 22, GOLD, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var crest := ColorRect.new()
	crest.color = club.primary_color()
	crest.custom_minimum_size = Vector2(16, 16)
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(crest)
	bar.add_child(_label(club.name, 17, TEXT, true))
	_squad_label = _label("", 17, TEXT)
	bar.add_child(_squad_label)
	_fill_check = _button("Simular elenco cheio: não", false)
	_fill_check.toggle_mode = true
	_fill_check.custom_minimum_size = Vector2(0, 36)
	_fill_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fill_check.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	_fill_check.toggled.connect(_on_fill_toggled)
	bar.add_child(_fill_check)
	var settings_btn := GearButton.new()
	settings_btn.theme_type_variation = &"SecondaryButton"
	settings_btn.custom_minimum_size = Vector2(42, 42)
	settings_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(settings_btn)
	add_to_group("settings_button_host")

	var body := Control.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.offset_top = TOP_BAR_H + 10.0
	body.offset_left = MARGIN
	body.offset_right = -MARGIN
	body.offset_bottom = -12.0
	add_child(body)
	_inventory_screen = _build_inventory_screen()
	body.add_child(_inventory_screen)
	_reveal_screen = _build_reveal_screen()
	body.add_child(_reveal_screen)
	_squad_screen = _build_squad_screen()
	body.add_child(_squad_screen)


func _build_inventory_screen() -> Control:
	var screen := HBoxContainer.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_theme_constant_override("separation", 18)

	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	screen.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	left.add_child(lv)
	lv.add_child(_label("Inventário", 20, GOLD, true))
	_inv_list = VBoxContainer.new()
	_inv_list.add_theme_constant_override("separation", 10)
	lv.add_child(_inv_list)
	var hint := _label("Guardar mantém o pacote lacrado. Os atletas só nascem quando ele é aberto.", 13, TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(hint)

	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.add_child(right)
	var center := CenterContainer.new()
	right.add_child(center)
	var stack := VBoxContainer.new()
	center.add_child(stack)
	_preview_empty = _label("Escolha um pacote no inventário.", 20, TEXT_DIM)
	_preview_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_empty.custom_minimum_size = Vector2(420, 0)
	_preview_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_preview_empty)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 36)
	_preview_box = box
	stack.add_child(box)
	_pack_art = PackArt.new()
	_pack_art.custom_minimum_size = Vector2(230, 320)
	box.add_child(_pack_art)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	info.custom_minimum_size = Vector2(330, 0)
	box.add_child(info)
	_pack_title = _label("", 28, GOLD, true)
	info.add_child(_pack_title)
	_pack_counts = _label("", 16, TEXT)
	_pack_counts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_pack_counts)
	info.add_child(_label("Chance de cada tier (por atleta)", 14, TEXT_DIM))
	_odds_grid = GridContainer.new()
	_odds_grid.columns = 3
	_odds_grid.add_theme_constant_override("h_separation", 12)
	_odds_grid.add_theme_constant_override("v_separation", 4)
	info.add_child(_odds_grid)
	_guarantee_label = _label("", 14, TEXT)
	_guarantee_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_guarantee_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	info.add_child(buttons)
	_open_button = _button("Abrir", true)
	_open_button.pressed.connect(_on_open_pressed)
	_open_button.set_meta(SfxService.META, "ui_confirmar")
	buttons.add_child(_open_button)
	_keep_button = _button("Guardar", false)
	_keep_button.pressed.connect(_on_keep_pressed)
	buttons.add_child(_keep_button)
	_back_button = _button("Voltar", false)
	_back_button.pressed.connect(_on_back_pressed)
	_back_button.set_meta(SfxService.META, "ui_voltar")
	buttons.add_child(_back_button)
	_message = _label("", 15, GOLD, true)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(330, 0)
	info.add_child(_message)
	return screen


func _build_reveal_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.offset_bottom = -REVEAL_BAR_H
	_stage.resized.connect(_layout_stage)
	screen.add_child(_stage)
	_stage_title = _label("", 22, GOLD, true)
	_stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_child(_stage_title)
	_caption = _label("Colecionáveis — em breve", 14, TEXT_DIM, true)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage.add_child(_caption)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -REVEAL_BAR_H + 10.0
	bar.add_theme_constant_override("separation", 12)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	screen.add_child(bar)
	_reveal_status = _label("", 15, TEXT)
	_reveal_status.custom_minimum_size = Vector2(430, 0)
	bar.add_child(_reveal_status)
	_next_button = _button("Revelar próxima", false)
	_next_button.pressed.connect(_on_next_pressed)
	bar.add_child(_next_button)
	_all_button = _button("Revelar todas", false)
	_all_button.pressed.connect(_on_all_pressed)
	bar.add_child(_all_button)
	_finish_button = _button("Concluir", true)
	_finish_button.pressed.connect(_on_finish_pressed)
	bar.add_child(_finish_button)
	return screen


func _build_squad_screen() -> Control:
	var screen := VBoxContainer.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_theme_constant_override("separation", 12)
	var head := HBoxContainer.new()
	screen.add_child(head)
	_squad_title = _label("", 22, GOLD, true)
	_squad_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_squad_title)
	var back := _button("Voltar ao inventário", true)
	back.pressed.connect(_on_squad_back_pressed)
	back.set_meta(SfxService.META, "ui_voltar")
	head.add_child(back)
	_new_row = HBoxContainer.new()
	_new_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_new_row.add_theme_constant_override("separation", 12)
	screen.add_child(_new_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	screen.add_child(scroll)
	_squad_grid = GridContainer.new()
	_squad_grid.columns = 3
	_squad_grid.add_theme_constant_override("h_separation", 10)
	_squad_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_squad_grid)
	return screen


func _label(text: String, font_px: int, color: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", StickerCard.font(bold))
	return l


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	if not primary:
		b.theme_type_variation = &"SecondaryButton"
	return b


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = StickerCard.font(false)
	th.default_font_size = DesignTokens.TYPE_BODY
	var styles := {
		"Button": [DesignTokens.COLOR_ACCENT_PRIMARY, DesignTokens.COLOR_TEXT_PRIMARY],
		"SecondaryButton": [DesignTokens.COLOR_BG_INPUT, DesignTokens.COLOR_TEXT_PRIMARY],
	}
	for type_name in styles:
		var bg: Color = styles[type_name][0]
		var fg: Color = styles[type_name][1]
		if type_name != "Button":
			th.set_type_variation(type_name, "Button")
		var variants := {"normal": bg, "hover": bg.lightened(0.15), "pressed": bg.darkened(0.15),
			"disabled": Color(bg.darkened(0.45), 0.6), "focus": bg}
		var primary: bool = type_name == "Button"
		for v in variants:
			var sb: StyleBox
			match v:
				"hover": sb = DesignTokens.style_button(primary, true)
				"pressed": sb = DesignTokens.style_button(primary, false, true)
				"focus": sb = DesignTokens.style_focus()
				_: sb = DesignTokens.style_button(primary, false)
			if v != "focus":
				sb.content_margin_left = 18
				sb.content_margin_right = 18
			th.set_stylebox(v, type_name, sb)
		th.set_color("font_color", type_name, fg)
		th.set_color("font_hover_color", type_name, fg)
		th.set_color("font_pressed_color", type_name, fg)
		th.set_color("font_focus_color", type_name, fg)
		th.set_color("font_disabled_color", type_name, Color(fg, 0.45))
		th.set_font("font", type_name, StickerCard.font(true))
		th.set_font_size("font_size", type_name, DesignTokens.TYPE_BODY)
	var panel := StyleBoxFlat.new()
	panel.bg_color = DesignTokens.COLOR_PAPER_SURFACE
	panel.border_color = DesignTokens.COLOR_INK
	panel.set_border_width_all(DesignTokens.BORDER_WIDTH)
	panel.shadow_color = DesignTokens.COLOR_INK
	panel.shadow_size = 1
	panel.shadow_offset = DesignTokens.SHADOW_OFFSET
	panel.set_corner_radius_all(14)
	panel.content_margin_left = 16
	panel.content_margin_right = 16
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_color("font_color", "Label", TEXT)
	return th


## Fundo: papel creme (textura repetida, ou a cor do papel).
func _draw() -> void:
	var paper := UiFrames.piece("ui_papel")
	if paper:
		draw_texture_rect(paper, Rect2(Vector2.ZERO, size), true)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), BG_A)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


static func pack_style(type_id: String) -> Dictionary:
	return PACK_STYLES.get(type_id, DEFAULT_PACK_STYLE)


# --- snapshot ----------------------------------------------------------------------------------------

func _run_snapshot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		printerr("pack_opening_view --snapshot precisa de renderizador: rode sem --headless")
		get_tree().quit(2)
		return
	await get_tree().process_frame
	var screen := _arg("screen", "reveal")
	var pack := _first_sealed(_arg("pack", "gol"))
	if pack.is_empty():
		printerr("snapshot: nenhum pacote lacrado do tipo pedido")
		get_tree().quit(1)
		return
	_select_pack(pack)
	var ok := true
	if screen != "inventory":
		controller.open()
		ok = controller.state == PackOpeningController.State.REVEALING
		if not ok:
			printerr("snapshot: abertura terminou em %s (%s)" % [PackOpeningController.state_name(controller.state), controller.last_error])
		await get_tree().process_frame
		_reveal_all_staggered()
		var wait := DEAL_TIME + _cards.size() * (DEAL_STAGGER + FLIP_STAGGER) + FLIP_TIME + 0.8
		await get_tree().create_timer(wait).timeout
		if screen == "squad" and controller.finish():
			await get_tree().create_timer(0.5).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("pack_opening_view: captura %dx%d (%s, estado %s) salva em %s (%s)" % [img.get_width(), img.get_height(),
		screen, PackOpeningController.state_name(controller.state), path, error_string(err)])
	get_tree().quit(0 if err == OK and ok else 1)


func _first_sealed(type_id: String) -> Dictionary:
	var inv: Variant = registry.bus.decide(HOOK_INVENTORY, {"club": club})
	if inv is Array:
		for p in inv:
			if p is Dictionary and str(p.get("type", "")) == type_id and str(p.get("status", "")) == STATUS_SEALED:
				return p
	return {}


static func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return fallback


## Arte do pacote lacrado: saquinho com bordas serrilhadas, degradê do tipo, brilho e rótulo.
class PackArt:
	extends Control
	var type_id := ""
	var label := ""
	var athletes := 0
	var slots := 0
	var style: Dictionary = {}

	func setup(p_type: String, p_label: String, p_athletes: int, p_slots: int, p_style: Dictionary) -> void:
		type_id = p_type
		label = p_label
		athletes = p_athletes
		slots = p_slots
		style = p_style
		queue_redraw()

	func _draw() -> void:
		if style.is_empty():
			return
		var w := size.x
		var h := size.y
		var tooth := 10.0
		var crimp := 14.0
		var top_pts := PackedVector2Array()
		var n := int(w / tooth)
		for i in n + 1:
			top_pts.append(Vector2(i * w / n, crimp if i % 2 == 0 else crimp * 0.35))
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var ca := Color(style.a)
		var cb := Color(style.b)
		for p in top_pts:
			pts.append(p)
			cols.append(ca)
		for i in range(n, -1, -1):
			pts.append(Vector2(i * w / n, h - (crimp if i % 2 == 0 else crimp * 0.35)))
			cols.append(cb)
		# Sombra.
		var shadow := PackedVector2Array()
		for p in pts:
			shadow.append(p + Vector2(6, 8))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
		draw_polygon(pts, cols)
		# Faixas de brilho diagonais.
		for k in 3:
			var x0 := w * (0.15 + 0.3 * k)
			var band := PackedVector2Array([Vector2(x0, 0), Vector2(x0 + 26, 0),
				Vector2(x0 - 60, h), Vector2(x0 - 86, h)])
			for piece in Geometry2D.intersect_polygons(band, pts):
				draw_colored_polygon(piece, Color(1, 1, 1, 0.07 + 0.03 * k))
		# Faixas serrilhadas (costura) em cima e embaixo.
		draw_rect(Rect2(0, crimp + 4, w, 3), Color(1, 1, 1, 0.25))
		draw_rect(Rect2(0, h - crimp - 7, w, 3), Color(0, 0, 0, 0.25))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0, 0, 0, 0.55), 2.0, true)
		# Selo.
		var bold := StickerCard.font(true)
		var accent := Color(style.accent)
		var c := Vector2(w / 2.0, h * 0.42)
		draw_circle(c, w * 0.3, Color(0, 0, 0, 0.22))
		draw_arc(c, w * 0.3, 0.0, TAU, 64, Color(accent, 0.85), 3.0, true)
		StickerCard.draw_text_centered(self, bold, "FOTEBA", Vector2(w / 2.0, crimp + 30), 16.0, accent,
			Color(0, 0, 0, 0.4), 3.0)
		StickerCard.draw_text_centered(self, bold, label, c, 44.0 if label.length() <= 5 else 30.0, Color.WHITE,
			Color(0, 0, 0, 0.55), 6.0)
		StickerCard.draw_text_centered(self, bold, "%d atleta%s" % [athletes, "" if athletes == 1 else "s"],
			Vector2(w / 2.0, h * 0.72), 18.0, accent, Color(0, 0, 0, 0.4), 3.0)
		StickerCard.draw_text_centered(self, StickerCard.font(false), "+ %d colecionáve%s" % [slots, "l" if slots == 1 else "is"],
			Vector2(w / 2.0, h * 0.72 + 24.0), 13.0, Color(accent, 0.85))
		StickerCard.draw_text_centered(self, StickerCard.font(false), "PACOTE DE FIGURINHAS",
			Vector2(w / 2.0, h - crimp - 24.0), 11.0, Color(accent, 0.75))
