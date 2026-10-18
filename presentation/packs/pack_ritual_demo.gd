extends Control
## Protótipo do ritual de abertura GOLMIO (PackRitual) ligado ao servidor local:
##   godot --path jogo res://presentation/packs/pack_ritual_demo.tscn
##
## Ordem garantida: o pacote é aberto no servidor (packs.open: sorteio, nascimento do atleta e
## entrada no elenco) ANTES da animação. O ritual só recebe a carta pronta e a encena. Pular,
## Repetir e fechar a tela não chamam o servidor, então não geram outra recompensa. "Abrir outro"
## é a única ação que abre (e consome) um pacote.
##
## Pacote com vários atletas: o ritual revela o melhor (o último da ordem de revelação).
## "Ensaio" troca só o nível desenhado (bronze..deus) para ajustar o visual de cada raridade; não
## mexe no elenco.
##
## Argumentos (depois de --):
##   --pack=comum               tipo do pacote aberto (padrão: comum)
##   --seed=<int>               sementes dos pacotes derivadas deste número (reproduzível)
##   --tier=deus                ensaio visual com outro nível
##   --speed=0.5                velocidade do ritual
##   --sheet=<arquivo.png>      folha com quadros de cada momento, salva e sai
##   --frame=<arquivo.png> --at=<s>  captura um instante e sai

const REHEARSAL_TIERS := ["", "bronze", "prata", "ouro", "diamante", "deus"]
const BG_A := Color("#0c3a26")
const BG_B := Color("#0e4029")
const TEXT := Color("#f3ead2")
const TEXT_DIM := Color("#b9c9bd")
const GOLD := Color("#f2c230")
const SHEET_COLS := 4
const SHEET_THUMB_W := 360

var registry: MechanicRegistry = null
var world: World = null
var club: Club = null
var kit: Dictionary = {}
var catalog: PortraitCatalog = null

var _ritual: PackRitual
var _pack_type := "comum"
var _card: Dictionary = {}
var _stats: Dictionary = {}
var _rehearsal := 0
var _info: Label
var _status: Label
var _skip_button: Button
var _replay_button: Button
var _next_button: Button
var _rehearsal_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	registry = PackOpeningView.build_registry()
	world = PackOpeningView.build_world()
	club = world.clubs.get(PackOpeningView.DEMO_CLUB_ID)
	kit = PortraitRenderer.kit_for_club(club)
	catalog = PortraitCatalog.shared()
	_pack_type = PackOpeningView._arg("pack", "comum")
	PackOpeningView.grant_demo_packs(registry, world, club, int(PackOpeningView._arg("seed", "-1")))
	var tier_arg := PackOpeningView._arg("tier", "")
	if REHEARSAL_TIERS.has(tier_arg):
		_rehearsal = REHEARSAL_TIERS.find(tier_arg)

	_ritual = PackRitual.new()
	_ritual.speed = float(PackOpeningView._arg("speed", "1"))
	_ritual.reduce_motion = bool(_setting("reduce_motion", false))
	_ritual.finished.connect(_on_finished)
	_ritual.beat.connect(_on_beat)
	add_child(_ritual)
	_build_ui()
	_open_next()

	var sheet := PackOpeningView._arg("sheet", "")
	var shot := PackOpeningView._arg("frame", "")
	if sheet != "":
		_run_sheet.call_deferred(sheet)
	elif shot != "":
		_run_shot.call_deferred(shot, float(PackOpeningView._arg("at", "2.0")))


func _exit_tree() -> void:
	if registry != null:
		registry.dispose()


# --- fluxo ---------------------------------------------------------------------------------------------

## Abre (no servidor) o próximo pacote lacrado do tipo e só então toca o ritual com a carta.
func _open_next() -> void:
	var pack := _first_sealed(_pack_type)
	if pack.is_empty():
		var res: Variant = registry.bus.decide(PackOpeningView.HOOK_GRANT, {"world": world, "club": club,
			"type": _pack_type, "seed": LocalBackend.new().new_seed(), "source": PackOpeningView.DEMO_SOURCE})
		if res is Dictionary and bool(res.get("ok", false)):
			pack = res.pack
	if pack.is_empty():
		_status.text = "Sem pacote do tipo \"%s\"." % _pack_type
		return
	var ctrl := PackOpeningController.for_registry(registry, world, club)
	ctrl.present(pack)
	ctrl.open(str(pack.get("id", "")))
	if ctrl.state != PackOpeningController.State.REVEALING and ctrl.state != PackOpeningController.State.COMPLETE:
		_status.text = "O servidor não abriu o pacote: %s %s" % [ctrl.last_error, str(ctrl.error_info.get("detail", ""))]
		return
	# Recompensa já registrada: o atleta está no elenco antes do primeiro quadro do ritual.
	_card = {}
	for c in ctrl.cards:
		if str((c as Dictionary).get("kind", "")) == StickerCard.KIND_ATHLETE:
			_card = c   # ordem de revelação: o melhor fica por último
	_stats = {}
	for a in ctrl.result.get("athletes", []):
		if a is Athlete and a.id == str(_card.get("athlete_id", "")):
			_stats = a.attributes
	ctrl.reveal_all()
	ctrl.finish()
	_info.text = "Pacote %s aberto no servidor antes da animação · %s · %s · elenco %d/%d" % [
		_pack_type, str(_card.get("name", "?")), str(StickerCard.tier_style(str(_card.get("tier", ""))).label),
		club.athlete_ids.size(), int(registry.ruleset.core_param("squad_limit"))]
	_play()


## Toca (ou repete) o ritual com a carta já sorteada. Não chama o servidor.
func _play() -> void:
	if _card.is_empty():
		return
	var shown := _card.duplicate(true)
	var rehearsal: String = REHEARSAL_TIERS[_rehearsal]
	if rehearsal != "":
		shown["tier"] = rehearsal
	_ritual.play(shown, kit, catalog, _stats)
	_sync()


func _on_finished(skipped: bool) -> void:
	_status.text = "Pulado." if skipped else "Ritual completo (%.2f s)." % _ritual.duration()
	_sync()


func _on_beat(moment: String) -> void:
	_status.text = "Momento: %s" % moment


func _on_rehearsal_pressed() -> void:
	_rehearsal = (_rehearsal + 1) % REHEARSAL_TIERS.size()
	_play()


func _sync() -> void:
	_skip_button.disabled = not _ritual.playing or _ritual.done
	var rehearsal: String = REHEARSAL_TIERS[_rehearsal]
	_rehearsal_button.text = "Ensaio: %s" % ("carta real" if rehearsal == "" else str(StickerCard.tier_style(rehearsal).label))


func _first_sealed(type_id: String) -> Dictionary:
	var inv: Variant = registry.bus.decide(PackOpeningView.HOOK_INVENTORY, {"club": club})
	if inv is Array:
		for p in inv:
			if p is Dictionary and str(p.get("type", "")) == type_id and str(p.get("status", "")) == PackOpeningView.STATUS_SEALED:
				return p
	return {}


func _setting(key: String, fallback: Variant) -> Variant:
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.has_method("get_value"):
		var v: Variant = settings.get_value(key)
		return fallback if v == null else v
	return fallback


# --- interface ------------------------------------------------------------------------------------------

func _build_ui() -> void:
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 10
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	top.add_child(_label("GOLMIO · ritual de abertura (protótipo)", 20, GOLD, true))
	_info = _label("", 14, TEXT)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_info)
	_status = _label("", 13, TEXT_DIM)
	top.add_child(_status)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -58
	bar.offset_bottom = -12
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 10)
	bar.z_index = 10
	add_child(bar)
	_skip_button = _button("Pular", func() -> void: _ritual.skip())
	bar.add_child(_skip_button)
	_replay_button = _button("Repetir", _play)
	bar.add_child(_replay_button)
	_rehearsal_button = _button("Ensaio", _on_rehearsal_pressed)
	bar.add_child(_rehearsal_button)
	_next_button = _button("Abrir outro", _open_next)
	bar.add_child(_next_button)


func _label(text: String, font_px: int, color: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", StickerCard.font(bold))
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE   # Espaço/Enter ficam para pular o ritual
	b.custom_minimum_size = Vector2(0, 42)
	b.add_theme_font_override("font", StickerCard.font(true))
	b.pressed.connect(action)
	return b


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_A)
	var stripe := 90.0
	var x := 0.0
	var i := 0
	while x < size.x:
		if i % 2 == 1:
			draw_rect(Rect2(x, 0, stripe, size.y), BG_B)
		x += stripe
		i += 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


# --- capturas -------------------------------------------------------------------------------------------

func _capture() -> Image:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## Folha com um quadro por instante de cada momento do ritual.
func _run_sheet(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		printerr("pack_ritual_demo --sheet precisa de renderizador: rode sem --headless")
		get_tree().quit(2)
		return
	_ritual.speed = 0.0
	var times: Array = []
	for m in PackRitual.MOMENTS:
		var a := _ritual.moment_start(m)
		var i := PackRitual.MOMENTS.find(m)
		var b := _ritual.moment_start(PackRitual.MOMENTS[i + 1]) if i + 1 < PackRitual.MOMENTS.size() else _ritual.duration()
		times.append(a + (b - a) * 0.35)
		times.append(a + (b - a) * 0.85)
	var thumbs: Array = []
	for t in times:
		_ritual.seek(t)
		_status.text = "t = %.2f s" % t
		var img: Image = await _capture()
		var h := int(img.get_height() * float(SHEET_THUMB_W) / img.get_width())
		img.resize(SHEET_THUMB_W, h, Image.INTERPOLATE_LANCZOS)
		thumbs.append(img)
	var th: int = (thumbs[0] as Image).get_height()
	var rows := ceili(float(thumbs.size()) / SHEET_COLS)
	var sheet := Image.create(SHEET_THUMB_W * SHEET_COLS, th * rows, false, Image.FORMAT_RGBA8)
	for i in thumbs.size():
		var img: Image = thumbs[i]
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i((i % SHEET_COLS) * SHEET_THUMB_W, (i / SHEET_COLS) * th))
	var err := sheet.save_png(path)
	print("pack_ritual_demo: folha %dx%d (%d quadros, ritual %.2f s) salva em %s (%s)" % [sheet.get_width(),
		sheet.get_height(), thumbs.size(), _ritual.duration(), path, error_string(err)])
	get_tree().quit(0 if err == OK else 1)


func _run_shot(path: String, at: float) -> void:
	_ritual.speed = 0.0
	_ritual.seek(at)
	var img: Image = await _capture()
	var err := img.save_png(path)
	print("pack_ritual_demo: captura t=%.2f salva em %s (%s)" % [at, path, error_string(err)])
	get_tree().quit(0 if err == OK else 1)
