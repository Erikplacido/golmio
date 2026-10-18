class_name CutsceneOverlay
extends CanvasLayer
## Exibidor responsivo de vinhetas, GIFs e artes de lances (GDD 3, 4).
## Ajusta-se dinamicamente a 16:9 (paisagem / desktop / TV) e 9:16 (retrato / mobile).
## Aceita PNG, JPG, WebP e animações, com fallback seguro para placeholders.

signal cutscene_started(event_id: String)
signal cutscene_finished(event_id: String)

const CUTSCENE_DIR := "res://assets/cutscenes/"

## Mapeamento de eventos para os arquivos de asset
const ASSET_MAP := {
	"foul_yellow": "foul_yellow.png",
	"foul_red": "foul_red.png",
	"foul_simple": "foul_simple.png",
	"penalty": "penalty.png",
	"penalty_kick": "penalty_kick.png",
	"throw_in": "throw_in.png",
	"corner": "corner.png",
	"goal_kick": "goal_kick.png",
	"goal": "goal.png",
	"save": "save.png",
	"offside": "offside.png",
	"substitution": "substitution.png",
	"kickoff": "kickoff.png",
	"period_end": "period_end.png",
	"default": "placeholder_cutscene.png"
}

## Ícone (GameIcons) do banner de cada lance.
const EVENT_ICONS := {
	"goal": "gol", "save": "defesa", "foul_yellow": "amarelo", "foul_red": "vermelho",
	"foul_simple": "falta", "penalty": "penalti", "penalty_kick": "penalti", "offside": "falta",
	"throw_in": "lateral", "corner": "escanteio", "goal_kick": "tiro_de_meta",
	"substitution": "substituicao", "period_end": "falta", "kickoff": "jogar",
}

var is_active := false
var current_event_id := ""
## Preferências (Settings): sem zoom/esmaecimento e multiplicador da duração das vinhetas.
var reduce_motion := false
var duration_scale := 1.0

var _root: Control
var _bg_rect: ColorRect
var _texture_rect: TextureRect
var _vignette: ColorRect
var _banner_panel: PanelContainer
var _lbl_tag: Label
var _lbl_title: Label
var _lbl_desc: Label
var _icon: TextureRect
var _tween: Tween
var _hold_timer: float = 0.0


func _ready() -> void:
	layer = 15  # Acima de HUDs normais
	_build_ui()
	visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)

	# Fundo escurecido semi-transparente
	_bg_rect = ColorRect.new()
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.color = Color(0.02, 0.04, 0.08, 0.85)
	_root.add_child(_bg_rect)

	# Textura do Lance (STRETCH_KEEP_ASPECT_COVERED garante cobertura perfeita em 16:9 e 9:16)
	_texture_rect = TextureRect.new()
	_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_texture_rect)

	# Vinheta degradê para foco central
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.color = Color(0.0, 0.0, 0.0, 0.25)
	_root.add_child(_vignette)

	# Banner inferior com informações do lance
	_banner_panel = PanelContainer.new()
	_banner_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_banner_panel.offset_top = -140.0
	_banner_panel.offset_bottom = -20.0
	_banner_panel.offset_left = 40.0
	_banner_panel.offset_right = -40.0

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.09, 0.16, 0.92)
	panel_style.border_color = Color("#00e5ff")
	panel_style.border_width_left = 3
	panel_style.border_width_bottom = 3
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.content_margin_left = 24
	panel_style.content_margin_right = 24
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12
	_banner_panel.add_theme_stylebox_override("panel", panel_style)
	_root.add_child(_banner_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_banner_panel.add_child(row)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(76, 76)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	row.add_child(_icon)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(vbox)

	_lbl_tag = Label.new()
	_lbl_tag.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	_lbl_tag.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_SEMIBOLD))
	_lbl_tag.add_theme_color_override("font_color", Color("#00e5ff"))
	_lbl_tag.text = "● LANCE CAPITAL · FOTEBA"
	vbox.add_child(_lbl_tag)

	_lbl_title = Label.new()
	_lbl_title.add_theme_font_size_override("font_size", UiKit.FONT_TITLE)
	_lbl_title.add_theme_font_override("font", DesignTokens.display_font())
	_lbl_title.add_theme_color_override("font_color", Color("#ffffff"))
	_lbl_title.text = "TÍTULO DO LANCE"
	vbox.add_child(_lbl_title)

	_lbl_desc = Label.new()
	_lbl_desc.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	_lbl_desc.add_theme_color_override("font_color", Color("#94a3b8"))
	_lbl_desc.text = "Descrição detalhada do momento da partida..."
	vbox.add_child(_lbl_desc)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ESCAPE, KEY_ENTER, KEY_C]:
			dismiss()
	elif event is InputEventMouseButton and event.pressed:
		dismiss()


## Dispara a exibição da vinheta/GIF correspondente ao lance.
func play_event(event_key: String, title: String, description: String = "", duration: float = 2.2) -> void:
	duration *= duration_scale
	current_event_id = event_key
	is_active = true
	visible = true

	# Identifica o arquivo
	var filename: String = ASSET_MAP.get(event_key, ASSET_MAP["default"])
	var asset_path := CUTSCENE_DIR + filename

	# Fallbacks se o arquivo específico não existir
	var tex: Texture2D = null
	if ResourceLoader.exists(asset_path):
		tex = load(asset_path) as Texture2D
	if tex == null:
		# Tenta JPG ou fallback padrão
		var jpg_path := asset_path.replace(".png", ".jpg")
		if ResourceLoader.exists(jpg_path):
			tex = load(jpg_path) as Texture2D
		elif ResourceLoader.exists(CUTSCENE_DIR + "placeholder_cutscene.png"):
			tex = load(CUTSCENE_DIR + "placeholder_cutscene.png") as Texture2D
		elif ResourceLoader.exists(CUTSCENE_DIR + "placeholder_cutscene.jpg"):
			tex = load(CUTSCENE_DIR + "placeholder_cutscene.jpg") as Texture2D

	_texture_rect.texture = tex
	_icon.texture = GameIcons.texture(str(EVENT_ICONS.get(event_key, "")))
	_icon.visible = _icon.texture != null

	# Atualiza textos
	_lbl_tag.text = "● LANCE AO VIVO · %s" % event_key.to_upper().replace("_", " ")
	_lbl_title.text = title.to_upper()
	_lbl_desc.text = description if description != "" else "Vinheta oficial de reposição / lance de partida."

	# Cor do tema da borda conforme o lance
	var border_col := Color("#00e5ff")
	if "red" in event_key or "penalty" in event_key or "offside" in event_key:
		border_col = Color("#ea3c36")
	elif "yellow" in event_key or "foul" in event_key or "save" in event_key:
		border_col = Color("#f59e0b")
	elif "goal" in event_key:
		border_col = Color("#10b981")
	elif "throw" in event_key or "corner" in event_key:
		border_col = Color("#3b82f6")

	(_banner_panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color = border_col
	_lbl_tag.add_theme_color_override("font_color", border_col)

	# Animação suave com Tween
	if _tween and _tween.is_valid():
		_tween.kill()

	if reduce_motion:
		_root.modulate = Color.WHITE
		_texture_rect.scale = Vector2.ONE
	else:
		_root.modulate = Color(1, 1, 1, 0)
		_texture_rect.scale = Vector2(1.04, 1.04)
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(_root, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_texture_rect, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	cutscene_started.emit(event_key)

	# Agenda encerramento automático após a duração
	# Respeita a pausa (ex.: painel de configurações aberto): a vinheta espera.
	get_tree().create_timer(duration, false).timeout.connect(func():
		if is_active and current_event_id == event_key:
			dismiss()
	)


## Fecha a vinheta com transição suave.
func dismiss() -> void:
	if not is_active:
		return
	is_active = false

	if _tween and _tween.is_valid():
		_tween.kill()

	if reduce_motion:
		visible = false
		cutscene_finished.emit(current_event_id)
		return

	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 0.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.finished.connect(func():
		visible = false
		cutscene_finished.emit(current_event_id)
	)
