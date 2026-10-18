class_name TitleScreen
extends Control
## Tela de abertura: estádio em camadas (assets/abertura/, exportadas de "Estádio iluminado, gramado e
## torcida.tif" por visuais/abertura/Exportar Abertura.command), torcida pulando, bandeiras ao
## vento, feixes de luz, flashes, confete e o logo GOL MIO. O botão JOGAR (ou Enter/Espaço/controle)
## começa; embaixo, opções e som.
##
## Entrada no estilo das aberturas de jogos mobile: a tela abre do escuro com a câmera avançando, o
## logo despenca grande e bate (tremor, clarão, onda de choque, faíscas e papel picado), quica, os
## raios acendem atrás dele, um reflexo cruza o logo e os botões saltam um a um. Depois o logo
## flutua, os raios giram, o JOGAR respira e os reflexos voltam de tempos em tempos.
##
## Formato: a arte é vertical (9:16). Em telas em pé ela cobre tudo; em telas deitadas fica
## inteira no centro, com as laterais preenchidas pelo fundo escurecido e as bordas dissolvidas.
## "Reduzir movimento" (Settings) deixa a cena parada: sem pulos, confete, flashes, entrada nem quique.

signal started

const DIR := "res://assets/abertura/"
const MANIFEST := DIR + "camadas.json"
const LOGO := "res://assets/Logo GOL MIO com acabamento artesanal.png"
## Trilha composta em Strudel (fontes em tools/strudel/): o tema em loop e o efeito da entrada do
## logo (apito, impacto no instante em que ele bate, "GOOOL" da torcida com eco).
const MUSIC := "res://assets/audio/tema_abertura.ogg"
const GOL_SFX := "res://assets/audio/grito_gol.ogg"
const MUSIC_DB := -6.0
const LayerShader := preload("res://presentation/title/title_layer.gdshader")
const LightsShader := preload("res://presentation/title/title_lights.gdshader")
const BlurShader := preload("res://presentation/title/title_blur.gdshader")
const RaysShader := preload("res://presentation/title/title_rays.gdshader")
const RingShader := preload("res://presentation/title/title_ring.gdshader")
const ShineShader := preload("res://presentation/title/title_shine.gdshader")
const SettingsService := preload("res://presentation/settings/settings_service.gd")

## Movimento de cada camada: [modo do shader, amplitude (px da arte), velocidade, frequência, semente]
## Modos: 0 parada, 1 torcida pulando, 2 bandeira tremulando. Camadas ao fundo pulam menos e mais
## rápido (estão mais longe).
const MOTION := {
	"bandeiras": [2, 6.0, 3.2, 0.03, 0.0],
	"torcida_superior": [1, 5.0, 9.5, 0.09, 1.3],
	"torcida_inferior_fundo": [1, 7.0, 8.0, 0.06, 4.2],
	"torcida_inferior_frente": [1, 9.0, 7.0, 0.05, 2.7],
}
## Diagramação (px da arte 941 × 1672): logo no alto, centrado entre os refletores; JOGAR sobre o
## círculo central; opções e som lado a lado no pé.
const LOGO_WIDTH := 0.52            # fração da largura da arte
const LOGO_TOP := 325.0
const PLAY_RECT := Rect2(175, 1130, 590, 180)
const ICON_RADIUS := 46.0
const ICON_SPACING := 124.0         # entre os centros de opções e som
const ICON_Y := 1535.0
const BOTTOM_GAP := 28.0            # folga mínima entre os ícones e a borda visível de baixo
## Em telas pequenas (celular deitado) os botões crescem até os ícones terem MIN_ICON_PX de
## diâmetro na tela, no máximo MAX_UI_SCALE vezes.
const MIN_ICON_PX := 44.0
const MAX_UI_SCALE := 1.6
## Faixa da arquibancada onde surgem flashes (px da arte).
const FLASH_AREA := Rect2(30, 560, 880, 300)
const SIDE_FADE := 0.16

## Paralaxe (px da arte no deslocamento máximo): quanto mais perto, mais mexe. O estádio e a torcida
## se movem em bloco (estão desenhados também no "fundo"; mover só uma camada mostraria a cópia).
const PARALLAX_BACK := 5.0
const PARALLAX_LOGO := 10.0
const PARALLAX_BALL := 18.0
const PARALLAX_CONFETTI := 26.0
const BACK_MARGIN := 1.015          # escala do bloco de fundo: margem para mexer sem mostrar a borda
## Bola: círculo medido na arte (centro e raio em px). Ela também está desenhada no "fundo": fica
## BALL_SCALE maior a partir do centro para sempre cobrir a cópia parada, e parte de BALL_BASE (para
## a esquerda e para baixo) para as bordas cortadas da arte nunca entrarem na tela.
const BALL_CENTER := Vector2(-13.5, 1610.1)
const BALL_SCALE := 1.2
const BALL_BASE := Vector2(-30.0, 18.0)
const BALL_ROLL_DEG := 2.0
## Sem mouse nem inclinação, o paralaxe deriva sozinho; o mouse assume por AUTO_AFTER s após mexer.
const AUTO_AFTER := 2.5

var _canvas := Vector2(941, 1672)
var _side: TextureRect
var _stage: Control
var _layers: Array[TextureRect] = []
var _logo: TextureRect
var _logo_rest := Vector2.ZERO
var _logo_shine: ShaderMaterial
var _rays: ColorRect
var _ring: ColorRect
var _sparks: CPUParticles2D
var _burst: CPUParticles2D
var _ui: Control                   # grupo dos botões; origem no centro do JOGAR
var _play: TitleButton
var _gear_btn: TitleButton
var _sound_btn: TitleButton
var _flash: ColorRect
var _cover: ColorRect
var _fade: ColorRect
var _audio: AudioStreamPlayer     # tema em loop
var _gol: AudioStreamPlayer       # efeito da entrada
var _confetti: CPUParticles2D
var _flashes: CPUParticles2D
var _lights: ColorRect
var _back: Control
var _ball: TextureRect
var _ball_rest := Vector2.ZERO
var _logo_holder: Control
var _confetti_rest := Vector2.ZERO
var _par := Vector2.ZERO
var _stage_base := Vector2.ZERO
var _shake := 0.0                  # px da arte; decai sozinho
var _zoom := 0.0                   # avanço da câmera sobre o fundo (0 = repouso)
var _idle := false
var _idle_time := 0.0
var _mouse_at := -100.0
var _gravity0 := Vector3.ZERO     # postura em que o aparelho estava ao abrir = olhar neutro
var _settings: Node
var _ready_at := 0.0
var _starting := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_settings = get_node_or_null("/root/Settings")
	add_to_group(SettingsService.HOST_GROUP)   # a abertura tem o próprio botão de opções
	_build()
	resized.connect(_layout)
	_layout()
	_intro()
	_ready_at = Time.get_ticks_msec() / 1000.0 + 0.35


func _reduce_motion() -> bool:
	return _settings != null and bool(_settings.get_value("reduce_motion"))


# --- montagem --------------------------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#07101f")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var info := _manifest()
	_canvas = Vector2(info.get("canvas", {}).get("w", 941), info.get("canvas", {}).get("h", 1672))

	# Laterais em telas deitadas: o fundo da arte ampliado e escurecido.
	_side = TextureRect.new()
	_side.texture = _load(DIR + "fundo.png")
	_side.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_side.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_side.modulate = Color(0.5, 0.53, 0.62)
	var blur := ShaderMaterial.new()
	blur.shader = BlurShader
	_side.material = blur
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_side)

	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.size = _canvas
	# Sem clip_contents: o recorte geraria uma borda dura nas laterais (telas deitadas); o que passa
	# da arte (bola ampliada) já some pelo esmaecimento das bordas, e o confete pode cair por cima.
	add_child(_stage)

	# Bloco de fundo (tudo menos bola, confete e logo): mexe junto, pouco.
	_back = Control.new()
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.size = _canvas
	_back.pivot_offset = _canvas / 2.0
	_back.scale = Vector2(BACK_MARGIN, BACK_MARGIN)
	_stage.add_child(_back)

	var still := _reduce_motion()
	for entry in info.get("layers", []):
		var id := str(entry.get("id", ""))
		var tex := _load(DIR + id + ".png")
		if tex == null:
			continue
		var r := TextureRect.new()
		r.name = id
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.position = Vector2(entry.x, entry.y)
		r.size = Vector2(entry.w, entry.h)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = LayerShader
		var motion: Array = MOTION.get(id, [0, 0.0, 0.0, 0.0, 0.0])
		m.set_shader_parameter("mode", 0 if still else motion[0])
		m.set_shader_parameter("amplitude", motion[1])
		m.set_shader_parameter("speed", motion[2])
		m.set_shader_parameter("frequency", motion[3])
		m.set_shader_parameter("seed", motion[4])
		m.set_shader_parameter("canvas_size", _canvas)
		m.set_shader_parameter("layer_rect", Vector4(entry.x, entry.y, entry.w, entry.h))
		r.material = m
		_layers.append(r)
		if id == "bola":
			# Primeiro plano: ampliada a partir do centro do círculo; o paralaxe move a partir daqui.
			r.pivot_offset = BALL_CENTER - r.position
			r.scale = Vector2(BALL_SCALE, BALL_SCALE)
			r.position += BALL_BASE
			_ball_rest = r.position
			_ball = r
			_stage.add_child(r)
		else:
			_back.add_child(r)
		match id:
			"bandeiras":
				_add_lights()
			"torcida_superior":
				_add_flashes(still)

	_add_confetti(still)

	_logo_holder = Control.new()
	_logo_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_logo_holder)

	_logo = TextureRect.new()
	_logo.texture = _load(LOGO)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lw := _canvas.x * LOGO_WIDTH
	var ts := _logo.texture.get_size() if _logo.texture else Vector2(1, 1.2)
	_logo.size = Vector2(lw, lw * ts.y / ts.x)
	_logo.position = Vector2((_canvas.x - lw) / 2.0, LOGO_TOP)
	_logo.pivot_offset = _logo.size / 2.0
	_logo_rest = _logo.position
	_logo_shine = ShaderMaterial.new()
	_logo_shine.shader = ShineShader
	_logo_shine.set_shader_parameter("rect_size", _logo.size)
	_logo.material = _logo_shine
	var center := _logo.position + _logo.size / 2.0
	if _lights:
		(_lights.material as ShaderMaterial).set_shader_parameter("sun", center / _canvas)

	_rays = _fx_rect(RaysShader, center, 1400.0)
	(_rays.material as ShaderMaterial).set_shader_parameter("spin", 0.0 if still else 0.12)
	_logo_holder.add_child(_rays)
	_ring = _fx_rect(RingShader, center, 1100.0)
	_ring.visible = false
	_logo_holder.add_child(_ring)
	_logo_holder.add_child(_logo)
	_logo_holder.pivot_offset = center
	_add_impact_particles(center)

	_ui = Control.new()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_ui)
	_play = _add_button(TitleButton.Kind.PLAY, Vector2.ZERO, PLAY_RECT.size, _text("ABERTURA_JOGAR", "JOGAR"))
	_play.set_meta(SfxService.META, "")   # o som sai em _start, que também atende Enter e controle
	_play.pressed.connect(_start)
	var icon_y := ICON_Y - PLAY_RECT.get_center().y
	var icon_size := Vector2.ONE * ICON_RADIUS * 2.0
	_gear_btn = _add_button(TitleButton.Kind.SETTINGS, Vector2(-ICON_SPACING / 2.0, icon_y), icon_size)
	_gear_btn.tooltip_text = "Configurações (F10)"
	_gear_btn.pressed.connect(_open_settings)
	_sound_btn = _add_button(TitleButton.Kind.SOUND, Vector2(ICON_SPACING / 2.0, icon_y), icon_size)
	_sound_btn.tooltip_text = "Som"
	_sound_btn.pressed.connect(_toggle_sound)
	_sync_sound()
	if _settings and _settings.has_signal("changed"):
		_settings.changed.connect(_on_setting_changed)

	_flash = ColorRect.new()
	_flash.color = Color(1.0, 0.97, 0.86, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_cover = ColorRect.new()
	_cover.color = Color(0.01, 0.02, 0.05, 0.0)
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)

	_fade = ColorRect.new()
	_fade.color = Color(DesignTokens.COLOR_PAPER, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	if ResourceLoader.exists(MUSIC):
		_audio = AudioStreamPlayer.new()
		_audio.stream = load(MUSIC)
		if _audio.stream is AudioStreamOggVorbis:
			(_audio.stream as AudioStreamOggVorbis).loop = true
		_audio.bus = "Music" if AudioServer.get_bus_index("Music") != -1 else "Master"
		_audio.volume_db = MUSIC_DB
		add_child(_audio)
	if ResourceLoader.exists(GOL_SFX):
		_gol = AudioStreamPlayer.new()
		_gol.stream = load(GOL_SFX)
		_gol.bus = "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
		add_child(_gol)


func _add_lights() -> void:
	_lights = ColorRect.new()
	_lights.size = _canvas
	_lights.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = LightsShader
	m.set_shader_parameter("aspect", _canvas.x / _canvas.y)
	if _reduce_motion():
		m.set_shader_parameter("sweep", 0.0)
	_lights.material = m
	_back.add_child(_lights)


## Flashes de celular e câmera na arquibancada: pontos que acendem e somem em ~0,1 s.
func _add_flashes(still: bool) -> void:
	_flashes = CPUParticles2D.new()
	_flashes.position = FLASH_AREA.get_center()
	_flashes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_flashes.emission_rect_extents = FLASH_AREA.size / 2.0
	_flashes.amount = 24
	_flashes.lifetime = 0.14
	_flashes.preprocess = 0.5
	_flashes.gravity = Vector2.ZERO
	_flashes.initial_velocity_min = 0.0
	_flashes.initial_velocity_max = 0.0
	_flashes.scale_amount_min = 0.35
	_flashes.scale_amount_max = 1.0
	_flashes.texture = _dot_texture(24)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.25, Color(1, 1, 0.92, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
	_flashes.color_ramp = fade
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flashes.material = mat
	_flashes.emitting = not still
	_flashes.visible = not still
	_back.add_child(_flashes)


## Papel picado caindo na frente de tudo, como os papéis da arte: vermelho, azul e creme (cores
## amostradas das bandeiras), peças grandes girando.
func _add_confetti(still: bool) -> void:
	_confetti = CPUParticles2D.new()
	_confetti.position = Vector2(_canvas.x / 2.0, -20)
	_confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_confetti.emission_rect_extents = Vector2(_canvas.x * 0.6, 10)
	_confetti.amount = 45
	_confetti.lifetime = 9.0
	_confetti.preprocess = 9.0
	_confetti.direction = Vector2(0, 1)
	_confetti.spread = 25.0
	_confetti.gravity = Vector2(0, 38)
	_confetti.initial_velocity_min = 20.0
	_confetti.initial_velocity_max = 70.0
	_confetti.angular_velocity_min = -220.0
	_confetti.angular_velocity_max = 220.0
	_confetti.angle_min = 0.0
	_confetti.angle_max = 360.0
	_confetti.tangential_accel_min = -18.0
	_confetti.tangential_accel_max = 18.0
	_confetti.damping_min = 4.0
	_confetti.damping_max = 10.0
	_confetti.scale_amount_min = 0.8
	_confetti.scale_amount_max = 1.6
	_confetti.texture = _rect_texture(8, 13)
	var colors := Gradient.new()
	colors.set_color(0, Color("#f7130c"))
	colors.add_point(0.4, Color("#0170d3"))
	colors.add_point(0.75, Color("#fbf1ce"))
	colors.remove_point(colors.get_point_count() - 1)
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	_confetti.color_initial_ramp = colors
	_confetti.emitting = not still
	_confetti.visible = not still
	_confetti_rest = _confetti.position
	_stage.add_child(_confetti)


## Retângulo de efeito (raios, onda de choque) de lado `side`, centrado em `center`.
func _fx_rect(shader: Shader, center: Vector2, side: float) -> ColorRect:
	var r := ColorRect.new()
	r.size = Vector2(side, side)
	r.position = center - r.size / 2.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = shader
	r.material = m
	return r


## Impacto do logo: faíscas douradas (somadas à luz) e um estouro de papel picado, os dois de uma
## vez só a partir do centro do logo.
func _add_impact_particles(center: Vector2) -> void:
	_sparks = CPUParticles2D.new()
	_sparks.position = center
	_sparks.one_shot = true
	_sparks.emitting = false
	_sparks.explosiveness = 1.0
	_sparks.amount = 70
	_sparks.lifetime = 1.0
	_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 140.0
	_sparks.spread = 180.0
	_sparks.gravity = Vector2(0, 700)
	_sparks.initial_velocity_min = 420.0
	_sparks.initial_velocity_max = 1100.0
	_sparks.damping_min = 300.0
	_sparks.damping_max = 600.0
	_sparks.scale_amount_min = 0.6
	_sparks.scale_amount_max = 1.5
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	_sparks.scale_amount_curve = shrink
	_sparks.texture = _dot_texture(32)
	var hot := Gradient.new()
	hot.set_color(0, Color(1.0, 0.98, 0.8, 1.0))
	hot.add_point(0.35, Color(1.0, 0.76, 0.18, 1.0))
	hot.set_color(hot.get_point_count() - 1, Color(1.0, 0.45, 0.05, 0.0))
	_sparks.color_ramp = hot
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sparks.material = add
	_logo_holder.add_child(_sparks)

	_burst = CPUParticles2D.new()
	_burst.position = center
	_burst.one_shot = true
	_burst.emitting = false
	_burst.explosiveness = 0.95
	_burst.amount = 60
	_burst.lifetime = 2.6
	_burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_burst.emission_sphere_radius = 160.0
	_burst.direction = Vector2(0, -1)
	_burst.spread = 110.0
	_burst.gravity = Vector2(0, 520)
	_burst.initial_velocity_min = 500.0
	_burst.initial_velocity_max = 1150.0
	_burst.damping_min = 280.0
	_burst.damping_max = 420.0
	_burst.angular_velocity_min = -540.0
	_burst.angular_velocity_max = 540.0
	_burst.angle_min = 0.0
	_burst.angle_max = 360.0
	_burst.scale_amount_min = 1.0
	_burst.scale_amount_max = 2.0
	_burst.texture = _rect_texture(8, 13)
	_burst.color_initial_ramp = _confetti.color_initial_ramp if _confetti else null
	_stage.add_child(_burst)   # na frente do logo


func _add_button(kind: TitleButton.Kind, center: Vector2, button_size: Vector2, label := "") -> TitleButton:
	var b := TitleButton.new(kind, label)
	b.size = button_size
	b.position = center - button_size / 2.0
	_ui.add_child(b)
	return b


func _open_settings() -> void:
	if _settings:
		_settings.open_panel()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "mute":
		_sync_sound()


func _toggle_sound() -> void:
	if _settings:
		_settings.set_value("mute", not bool(_settings.get_value("mute")))
	else:
		AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
	_sync_sound()


func _sync_sound() -> void:
	if _sound_btn:
		_sound_btn.muted = bool(_settings.get_value("mute")) if _settings else AudioServer.is_bus_mute(0)


# --- layout ----------------------------------------------------------------------------------------

func _layout() -> void:
	if _stage == null:
		return
	var vp := size
	var art_aspect := _canvas.x / _canvas.y
	var deitada := vp.x / maxf(vp.y, 1.0) > art_aspect + 0.01
	# Em pé: cobre a tela (corta um pouco das bordas). Deitada: a arte inteira na altura da tela.
	var k := vp.y / _canvas.y if deitada else maxf(vp.x / _canvas.x, vp.y / _canvas.y)
	_stage.scale = Vector2(k, k)
	_stage_base = (vp - _canvas * k) / 2.0
	_stage.position = _stage_base
	_side.visible = deitada
	var fade := SIDE_FADE if deitada else 0.0
	for r in _layers:
		(r.material as ShaderMaterial).set_shader_parameter("edge_fade", fade)

	# Botões: no lugar da diagramação, ampliados em telas pequenas e erguidos se a parte de baixo
	# da arte ficar fora da tela (telas em pé mais largas que 9:16) ou sob a área segura.
	var ui_k := clampf(MIN_ICON_PX / (ICON_RADIUS * 2.0 * k), 1.0, MAX_UI_SCALE)
	_ui.scale = Vector2(ui_k, ui_k)
	var vis_bottom := minf(_canvas.y, (vp.y - _stage_base.y) / k)
	var safe_bottom: float = (_settings.safe_margins().w if _settings else 0.0) / k
	var anchor := PLAY_RECT.get_center()
	var ui_bottom := (ICON_Y + ICON_RADIUS - anchor.y) * ui_k
	anchor.y = minf(anchor.y, vis_bottom - safe_bottom - BOTTOM_GAP - ui_bottom)
	_ui.position = anchor


# --- paralaxe -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _stage == null:
		return
	if _shake > 0.05:
		var j := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
		_stage.position = _stage_base + j * _stage.scale.x
		_shake *= exp(-delta * 10.0)
	elif _shake > 0.0:
		_shake = 0.0
		_stage.position = _stage_base
	if _reduce_motion():
		return
	var target := _parallax_target()
	_par = _par.lerp(target, 1.0 - exp(-delta * 3.0))
	var off := -_par                  # o que está perto vai para o lado oposto do olhar
	_back.position = off * PARALLAX_BACK
	_back.scale = Vector2.ONE * BACK_MARGIN * (1.0 + _zoom)
	_logo_holder.position = off * PARALLAX_LOGO
	if _ball:
		_ball.position = _ball_rest + off * PARALLAX_BALL
		_ball.rotation_degrees = off.x * BALL_ROLL_DEG
	if _confetti:
		_confetti.position = _confetti_rest + off * PARALLAX_CONFETTI
	if _idle:
		# Logo flutuando: sobe e desce, balança e respira, em ritmos que não batem entre si.
		_idle_time += delta
		_logo.position = _logo_rest + Vector2(0, sin(_idle_time * 1.6) * 9.0)
		_logo.rotation_degrees = sin(_idle_time * 1.1) * 1.1
		var b := 1.0 + sin(_idle_time * 2.2) * 0.012
		_logo.scale = Vector2(b, b)


## Direção do olhar em -1..1: mouse (desktop), inclinação do aparelho (celular) ou deriva lenta.
func _parallax_target() -> Vector2:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _mouse_at < AUTO_AFTER and size.x > 0.0 and size.y > 0.0:
		var m := get_local_mouse_position() / size * 2.0 - Vector2.ONE
		return m.clamp(Vector2(-1, -1), Vector2(1, 1))
	var g := Input.get_gravity()
	if g.length() > 1.0:
		if _gravity0 == Vector3.ZERO:
			_gravity0 = g
		var d := (g - _gravity0) / 3.0          # ~3 m/s² de inclinação = deslocamento máximo
		return Vector2(clampf(d.x, -1.0, 1.0), clampf(-d.y, -1.0, 1.0))
	return Vector2(sin(now * 0.35), sin(now * 0.27 + 1.0) * 0.7)


# --- animação --------------------------------------------------------------------------------------

func _intro() -> void:
	if _logo == null:
		_play_music(0.0)
		return
	var rays := _rays.material as ShaderMaterial
	if _reduce_motion():
		rays.set_shader_parameter("intensity", 0.4)
		_play_music(0.0)
		return
	# O efeito tem o impacto gravado em 0,76 s, o mesmo instante em que o logo bate (abaixo).
	if _gol:
		_gol.play()
	for b in [_play, _gear_btn, _sound_btn]:
		b.appear = 0.0
	# Abre do escuro com a câmera avançando sobre o estádio.
	_cover.color.a = 1.0
	_zoom = 0.14
	var cam := create_tween().set_parallel()
	cam.tween_property(_cover, "color:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE)
	cam.tween_property(self, "_zoom", 0.0, 1.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# O logo despenca enorme, acelerando, e bate; depois amassa, estica e assenta tremendo.
	_logo.modulate.a = 0.0
	_logo.scale = Vector2(3.4, 3.4)
	_logo.rotation_degrees = -14.0
	_logo.position = _logo_rest + Vector2(0, -90)
	var t := create_tween()
	t.tween_interval(0.5)
	t.tween_property(_logo, "modulate:a", 1.0, 0.1)
	t.parallel().tween_property(_logo, "scale", Vector2(0.9, 0.9), 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_logo, "rotation_degrees", 4.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_logo, "position", _logo_rest, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_impact)
	t.tween_property(_logo, "scale", Vector2(1.16, 0.84), 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_logo, "scale", Vector2(0.93, 1.08), 0.09).set_trans(Tween.TRANS_SINE)
	t.tween_property(_logo, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_logo, "rotation_degrees", 0.0, 0.8).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(func(): _idle = true)

	# Já com o logo no lugar: reflexo nele e os botões saltando um a um.
	var after := 0.5 + 0.26
	_pop(_play, after + 0.35)
	_pop(_gear_btn, after + 0.6)
	_pop(_sound_btn, after + 0.72)
	var fx := create_tween()
	fx.tween_interval(after + 0.3)
	_param(fx, _logo_shine, "progress", -0.2, 1.2, 0.75).set_trans(Tween.TRANS_SINE)
	fx.tween_callback(_play.shine)
	fx.tween_interval(0.6)
	fx.tween_callback(_idle_loops)


## O instante em que o logo bate: tremor, clarão, onda de choque, faíscas, papel picado, um soco
## de zoom na câmera e os raios acendendo forte antes de assentar.
func _impact() -> void:
	_play_music(1.2)
	_shake = 22.0
	_flash.color.a = 0.75
	create_tween().tween_property(_flash, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ring.visible = true
	var ring := _ring.material as ShaderMaterial
	var rt := create_tween()
	_param(rt, ring, "progress", 0.05, 1.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rt.tween_callback(func(): _ring.visible = false)
	_sparks.restart()
	_burst.restart()
	_zoom = -0.035
	create_tween().tween_property(self, "_zoom", 0.0, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var rays := _rays.material as ShaderMaterial
	var ry := create_tween()
	_param(ry, rays, "intensity", 0.0, 1.7, 0.12)
	_param(ry, rays, "intensity", 1.7, 0.55, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Começa o tema; com fade > 0 ele sobe do silêncio por baixo do grito de gol.
func _play_music(fade: float) -> void:
	if _audio == null or _audio.playing:
		return
	_audio.volume_db = MUSIC_DB - 24.0 if fade > 0.0 else MUSIC_DB
	_audio.play()
	if fade > 0.0:
		create_tween().tween_property(_audio, "volume_db", MUSIC_DB, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Botão saltando para dentro: cresce passando do ponto e volta com elástico.
func _pop(b: TitleButton, delay: float) -> void:
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(b, "appear", 1.0, 0.65).from(0.0).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if b == _play:
		t.tween_callback(func(): b.attention = true)


## Repetições depois da entrada: reflexos no logo e no JOGAR, alternados.
func _idle_loops() -> void:
	var t := create_tween().set_loops()
	t.tween_interval(2.6)
	_param(t, _logo_shine, "progress", -0.2, 1.2, 0.8).set_trans(Tween.TRANS_SINE)
	t.tween_interval(1.4)
	t.tween_callback(_play.shine)


# --- entrada ---------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_at = Time.get_ticks_msec() / 1000.0


func _unhandled_input(event: InputEvent) -> void:
	if _settings and _settings.is_panel_open():
		return
	if event.is_action_pressed("ui_accept") or (event is InputEventJoypadButton and event.pressed):
		_start()
		get_viewport().set_input_as_handled()


func _start() -> void:
	if _starting or Time.get_ticks_msec() / 1000.0 < _ready_at:
		return
	_starting = true
	_play.attention = false
	SfxService.play("ui_confirmar")
	if not _reduce_motion():
		# A câmera mergulha no estádio e o logo vem junto enquanto a tela clareia.
		create_tween().tween_property(self, "_zoom", 0.1, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		create_tween().tween_property(_logo_holder, "scale", Vector2(1.06, 1.06), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_shake = 6.0
	var t := create_tween()
	t.tween_interval(0.08)
	t.tween_property(_fade, "color:a", 1.0, 0.35)
	for p in [_audio, _gol]:
		if p and p.playing:
			t.parallel().tween_property(p, "volume_db", -40.0, 0.35)
	t.tween_callback(func(): started.emit())


# --- utilidades ------------------------------------------------------------------------------------

func _manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST):
		push_warning("TitleScreen: %s não existe; rode visuais/abertura/Exportar Abertura.command" % MANIFEST)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


func _load(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


## Anima um parâmetro de shader (tween_method: "shader_parameter/x" só existe para o Tween depois
## que o shader compila, e sem renderizador nunca existe).
static func _param(t: Tween, mat: ShaderMaterial, param: String, from: float, to: float, duration: float) -> MethodTweener:
	return t.tween_method(func(v: float): mat.set_shader_parameter(param, v), from, to, duration)


## Termo traduzido, ou `fallback` se a chave ainda não está na tradução importada.
static func _text(key: String, fallback: String) -> String:
	var t := GameTerms.text(key)
	return fallback if t == key else t


static func _dot_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (size / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


static func _rect_texture(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)
