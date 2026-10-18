class_name SfxService
extends Node
## Autoload "Sfx": toca os efeitos sonoros de assets/audio/sfx/ (compostos em Strudel, fontes em
## tools/strudel/efeitos.strudel.js) no barramento "SFX", que o painel de áudio já controla.
##
## Telas chamam `SfxService.play("gol")`: se o autoload não existe (testes, ferramentas) nada
## acontece. Também dá um clique a todo botão (BaseButton) que entra na árvore; um botão escolhe
## outro som com `set_meta(SfxService.META, "ui_confirmar")` ou fica mudo com `""`.
##
## Só apresentação: nada aqui entra na simulação.

const DIR := "res://assets/audio/sfx/"
const BUS := "SFX"
const META := &"sfx"
const CLICK := "ui_clique"
const VOICES := 8
const REPEAT_GAP := 0.06           # s; o mesmo som não se empilha dentro desse intervalo

var _streams := {}                 # nome -> AudioStream (ou null se não existe)
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _last_played := {}             # nome -> instante (s)
var _ambient: AudioStreamPlayer
var _ambient_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_voices.append(p)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = BUS
	add_child(_ambient)
	get_tree().node_added.connect(_on_node_added)


## Toca um efeito pelo nome (arquivo assets/audio/sfx/<nome>.ogg). delay em segundos.
static func play(sound: String, volume_db: float = 0.0, delay: float = 0.0) -> void:
	var s := _instance()
	if s:
		s._play(sound, volume_db, delay)


## Liga um som em loop por baixo de tudo (ex.: "torcida_ambiente"), subindo em fade segundos.
static func ambient(sound: String, volume_db: float = 0.0, fade: float = 1.5) -> void:
	var s := _instance()
	if s:
		s._start_ambient(sound, volume_db, fade)


static func stop_ambient(fade: float = 1.0) -> void:
	var s := _instance()
	if s:
		s._stop_ambient(fade)


## Som da revelação de uma figurinha pelas estrelas do nível (StickerCard.tier_style().rank).
static func reveal_sound(rank: int) -> String:
	if rank >= 5:
		return "revelar_lendario"
	if rank == 4:
		return "revelar_epico"
	if rank == 3:
		return "revelar_raro"
	return "revelar_comum"


static func _instance() -> SfxService:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Sfx") as SfxService if tree else null


func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := DIR + sound + ".ogg"
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
		if _streams[sound] == null:
			push_warning("Sfx: %s não existe" % path)
	return _streams[sound]


func _play(sound: String, volume_db: float, delay: float) -> void:
	if delay > 0.0:
		get_tree().create_timer(delay, true, false, true).timeout.connect(_play.bind(sound, volume_db, 0.0))
		return
	var stream := _stream(sound)
	if stream == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sound, -1.0)) < REPEAT_GAP:
		return
	_last_played[sound] = now
	# Pega uma voz livre; se todas tocam, rouba a mais antiga.
	var voice: AudioStreamPlayer = null
	for i in VOICES:
		var p := _voices[(_next_voice + i) % VOICES]
		if not p.playing:
			voice = p
			break
	if voice == null:
		voice = _voices[_next_voice]
	_next_voice = (_voices.find(voice) + 1) % VOICES
	voice.stream = stream
	voice.volume_db = volume_db
	voice.play()


func _start_ambient(sound: String, volume_db: float, fade: float) -> void:
	var stream := _stream(sound)
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	if _ambient_tween:
		_ambient_tween.kill()
	if _ambient.stream != stream or not _ambient.playing:
		_ambient.stream = stream
		_ambient.volume_db = volume_db - 30.0 if fade > 0.0 else volume_db
		_ambient.play()
	_ambient_tween = create_tween()
	_ambient_tween.tween_property(_ambient, "volume_db", volume_db, maxf(fade, 0.01))


func _stop_ambient(fade: float) -> void:
	if not _ambient.playing:
		return
	if _ambient_tween:
		_ambient_tween.kill()
	_ambient_tween = create_tween()
	_ambient_tween.tween_property(_ambient, "volume_db", _ambient.volume_db - 30.0, maxf(fade, 0.01))
	_ambient_tween.tween_callback(_ambient.stop)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		# Um botão movido de lugar (layout responsivo) volta a entrar na árvore: conecta uma vez só.
		var cb := _on_button_pressed.bind(node)
		if not (node as BaseButton).pressed.is_connected(cb):
			(node as BaseButton).pressed.connect(cb)


func _on_button_pressed(button: BaseButton) -> void:
	var sound := str(button.get_meta(META, CLICK))
	if sound != "":
		_play(sound, 0.0, 0.0)
