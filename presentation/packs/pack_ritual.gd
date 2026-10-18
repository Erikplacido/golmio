class_name PackRitual
extends Control
## Ritual de abertura do pacote GOLMIO em 2.5D: câmera quase frontal e camadas que se movem
## separadas (frente, interior, faixa rasgada, fragmentos, carta), sem embalagem 3D.
##
##   Entrada      o pacote sobe e acomoda com uma oscilação pequena (sombra chapada e curta)
##   Tensão       os cantos se contraem, o topo inclina, aparecem rugas desenhadas
##   Rasgo        a faixa superior se desprende de lado; fragmentos e fibras de papel
##   Antecipação  pausa com o envelope aberto: a cor da raridade aparece pela abertura
##   Revelação    a figurinha sobe, inclina e se acomoda na frente; raios porosos e confete de papel
##   Inspeção     a carta para de frente (o foil do nível corre só dentro da máscara, StickerCard)
##
## Só APRESENTA. Recebe a carta que o servidor já sorteou e registrou (packs.open) e não fala com
## nada: pular, repetir ou fechar não podem gerar outra recompensa.
##
## A animação é uma função pura do tempo (_apply(t)): seek(t) e skip() são exatos e a mesma carta
## sempre dá o mesmo ritual (partículas com semente fixa pela carta). Base de ~3 s; a raridade
## (estrelas do nível, StickerCard.tier_style) alonga a antecipação e muda a composição.
## Estilo: só cores chapadas, bordas porosas e recortes de papel; nada de bloom, desfoque ou fumaça.
##
## Uso:
##   var r := PackRitual.new()
##   add_child(r)                                   # ocupa o pai (PRESET_FULL_RECT)
##   r.finished.connect(func(skipped): ...)
##   r.play(carta, kit, catalog, atleta.attributes)  # carta = item de packs.open (kind athlete)
##   r.skip()                                       # clique/toque, Espaço, Enter ou Esc também pulam

## Momento novo do ritual ("enter", "tension", "tear", "anticipation", "reveal", "inspect"):
## gancho para som e vibração.
signal beat(moment: String)
## A carta parou de frente. skipped = o jogador pulou.
signal finished(skipped: bool)

const MOMENTS := ["enter", "tension", "tear", "anticipation", "reveal", "inspect"]
## Durações base (s). A antecipação ganha ANTICIPATION_PER_RANK por estrela acima de 2.
const DURATIONS := {"enter": 0.45, "tension": 0.42, "tear": 0.36, "anticipation": 0.32,
	"reveal": 0.8, "inspect": 0.55}
const DURATIONS_REDUCED := {"enter": 0.25, "tension": 0.0, "tear": 0.2, "anticipation": 0.3,
	"reveal": 0.45, "inspect": 0.3}
const ANTICIPATION_PER_RANK := 0.22
## Fração da revelação em que a carta termina de sair do pacote e passa para a frente dele.
const RISE_END := 0.42

const TEX_FRONT := "res://assets/packs/pack_front_closed.png"
const TEX_BODY := "res://assets/packs/pack_body_open.png"
const TEX_STRIP := "res://assets/packs/pack_strip.png"
const TEX_INTERIOR := "res://assets/packs/pack_interior.png"
const TEX_FRAGMENT := "res://assets/packs/pack_fragment_%d.png"
const FRAGMENT_COUNT := 6

# Medidas em px do quadro comum das camadas do pacote (visuais/exportar_pacote.py).
const PACK_PX := Vector2(571.0, 824.0)
## pacote_rasgo.png encaixa sobre pacote_rasgado.png com este deslocamento.
const STRIP_OFFSET := Vector2(-3.0, 17.0)
## A faixa gira em torno da ponta direita (o rasgo começa pela esquerda).
const STRIP_PIVOT := Vector2(552.0, 52.0)
## Altura média da borda rasgada do corpo.
const TEAR_Y := 88.0
const MOUTH_HALF := Vector2(222.0, 22.0)
const INTERIOR_TOP := 64.0
const INTERIOR_TINT := Color(0.58, 0.52, 0.44)
const SHADOW_OFFSET := Vector2(12.0, 16.0)
const SHADOW_COLOR := Color(0.02, 0.06, 0.04, 0.38)
## Largura total do StickerCard (com a folga transparente) dentro do pacote.
const CARD_IN_PACK_W := 500.0
## Topo do corpo da carta escondida e base dele quando ela termina de subir.
const CARD_HIDDEN_TOP := 108.0
const CARD_RISEN_BOTTOM := 74.0
## A carta espia pela abertura no fim da antecipação.
const CARD_PEEK := 46.0
const CREAM := Color("#f3ead2")
const PAPER_DARK := Color("#c9b48c")
const INK := Color("#14110c")
const BRAND_YELLOW := Color("#f2b318")
## Rugas da tensão (px do pacote): polilinhas perto dos cantos de cima.
const CREASES := [
	[Vector2(22, 70), Vector2(58, 98), Vector2(74, 132)],
	[Vector2(30, 128), Vector2(62, 150)],
	[Vector2(104, 64), Vector2(118, 96)],
	[Vector2(549, 70), Vector2(512, 100), Vector2(500, 136)],
	[Vector2(541, 126), Vector2(508, 152)],
	[Vector2(466, 64), Vector2(452, 98)],
	[Vector2(262, 62), Vector2(270, 84), Vector2(282, 92)],
]

## Sem tremores, oscilações nem partículas: a carta aparece no centro (Configurações > Reduzir movimento).
var reduce_motion := false
## Escurece o fundo atrás do ritual (0 = transparente).
var dim := 0.0
## Velocidade da reprodução (1 = normal); útil para ajustar o ritmo vendo.
var speed := 1.0

var card: Dictionary = {}
var rank := 0
var playing := false
var done := false
var skipped := false

var _t := 0.0
var _start: Dictionary = {}
var _dur: Dictionary = {}
var _total := 0.0
var _moment := -1
var _color_mid := BRAND_YELLOW
var _color_light := CREAM
var _tension := 0.0
var _fragments: Array = []
var _fibers: Array = []
var _confetti: Array = []
var _rays: Array = []
var _fragment_tex: Array = []

var _rays_layer: Layer
var _pack: Node2D
var _shadow: Sprite2D
var _interior: Sprite2D
var _mouth: Layer
var _body: Sprite2D
var _front: Sprite2D
var _creases: Layer
var _strip_pivot: Node2D
var _card: StickerCard
var _fx: Layer
var _tex_front: Texture2D
var _tex_body: Texture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tex_front = load(TEX_FRONT) as Texture2D
	_tex_body = load(TEX_BODY) as Texture2D
	for i in FRAGMENT_COUNT:
		_fragment_tex.append(load(TEX_FRAGMENT % (i + 1)) as Texture2D)

	# Ordem de desenho: raios (primeiro filho, z 0) < pacote (sombra, interior, abertura) < carta dentro
	# (z 1) < corpo e frente (z 2) < faixa (z 3) e carta fora do pacote (z 3) < partículas (z 4).
	# Nada usa z negativo: ficaria atrás do fundo desenhado pelo pai.
	_rays_layer = Layer.new(_draw_rays)
	add_child(_rays_layer)

	_pack = Node2D.new()
	_pack.name = "Pack"
	add_child(_pack)
	_shadow = _sprite(_tex_front, -PACK_PX / 2.0 + SHADOW_OFFSET)
	_shadow.modulate = SHADOW_COLOR
	_pack.add_child(_shadow)
	var interior_tex := load(TEX_INTERIOR) as Texture2D
	_interior = _sprite(interior_tex, Vector2(-interior_tex.get_width() / 2.0, INTERIOR_TOP - PACK_PX.y / 2.0))
	_interior.modulate = INTERIOR_TINT
	_pack.add_child(_interior)
	_mouth = Layer.new(_draw_mouth)
	_pack.add_child(_mouth)
	_body = _sprite(_tex_body, -PACK_PX / 2.0)
	_body.z_index = 2
	_pack.add_child(_body)
	_front = _sprite(_tex_front, -PACK_PX / 2.0)
	_front.z_index = 2
	_pack.add_child(_front)
	_creases = Layer.new(_draw_creases)
	_creases.z_index = 2
	_pack.add_child(_creases)
	_strip_pivot = Node2D.new()
	_strip_pivot.position = STRIP_PIVOT - PACK_PX / 2.0
	_strip_pivot.z_index = 3
	_pack.add_child(_strip_pivot)
	_strip_pivot.add_child(_sprite(load(TEX_STRIP) as Texture2D, STRIP_OFFSET - STRIP_PIVOT))

	_card = StickerCard.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	add_child(_card)

	_fx = Layer.new(_draw_fx)
	_fx.z_index = 4
	add_child(_fx)
	_pack.visible = false


func _ready() -> void:
	# Ocupa o pai inteiro. set_anchors_preset sozinho preservaria o tamanho atual (0 x 0).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	beat.connect(_beat_sound)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not card.is_empty():
		_layout_card()
		_apply(_t)


func _process(delta: float) -> void:
	if not playing:
		return
	var t := _t + delta * speed
	if not done:
		for i in MOMENTS.size():
			if i > _moment and t >= float(_start[MOMENTS[i]]):
				_moment = i
				beat.emit(MOMENTS[i])
	_apply(t)
	if not done and t >= _total:
		done = true
		finished.emit(false)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	var touch := event as InputEventScreenTouch
	if (mb != null and mb.pressed) or (touch != null and touch.pressed):
		if skip():
			accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event.is_action("ui_accept") or event.is_action("ui_cancel")):
		if skip():
			get_viewport().set_input_as_handled()


# --- API -------------------------------------------------------------------------------------------

## Começa o ritual com a carta já decidida pelo servidor. Pode ser chamado de novo (repetir): só
## reapresenta a mesma carta.
func play(p_card: Dictionary, kit: Dictionary = {}, catalog: PortraitCatalog = null, stats: Dictionary = {}) -> void:
	card = p_card.duplicate(true)
	_card.set_card(card, kit, catalog, stats)
	_card.set_face_up(true)
	_card.glow = 0.0
	var style := StickerCard.tier_style(str(card.get("tier", "")))
	if not str(card.get("frame", "")).is_empty():
		style = StickerCard.frame_style(StickerCard.frame_for(card))
	rank = clampi(int(style.get("rank", 0)), 0, 5)
	_color_mid = Color(str(style.get("mid", BRAND_YELLOW.to_html())))
	_color_light = Color(str(style.get("light", CREAM.to_html())))
	_build_timeline()
	_build_particles()
	_layout_card()
	_pack.visible = true
	playing = true
	done = false
	skipped = false
	_moment = -1
	_t = 0.0
	_apply(0.0)


## Vai direto para a carta parada de frente. Devolve false se não há ritual em andamento.
func skip() -> bool:
	if not playing or done:
		return false
	skipped = true
	done = true
	if _moment < MOMENTS.find("reveal"):
		SfxService.play(SfxService.reveal_sound(rank))   # pulou antes da revelação: ainda soa
	_moment = MOMENTS.size() - 1
	_apply(_total)
	finished.emit(true)
	return true


## Um som por momento (assets/audio/sfx/pacote_*, revelar_* e carta_brilho); a raridade alonga a
## antecipação e escolhe a revelação.
func _beat_sound(moment: String) -> void:
	match moment:
		"enter":
			SfxService.play("pacote_entrada")
		"tension":
			SfxService.play("pacote_tensao")
		"tear":
			SfxService.play("pacote_rasgo")
		"anticipation":
			SfxService.play("pacote_antecipacao_longa" if rank >= 3 else "pacote_antecipacao")
		"reveal":
			SfxService.play(SfxService.reveal_sound(rank))
		"inspect":
			SfxService.play("carta_brilho")


## Põe o ritual no instante t (s), sem sinais. Para capturas e ajuste de ritmo.
func seek(t: float) -> void:
	t = clampf(t, 0.0, _total + 3.0)
	_moment = -1
	for i in MOMENTS.size():
		if t >= float(_start.get(MOMENTS[i], INF)):
			_moment = i   # momentos já passados não são emitidos depois
	_apply(t)


## Duração até a carta parar de frente (depende da raridade e de reduce_motion).
func duration() -> float:
	return _total


func moment_start(moment: String) -> float:
	return float(_start.get(moment, 0.0))


func time() -> float:
	return _t


# --- linha do tempo ---------------------------------------------------------------------------------

func _build_timeline() -> void:
	_dur = (DURATIONS_REDUCED if reduce_motion else DURATIONS).duplicate()
	if not reduce_motion:
		_dur["anticipation"] = float(_dur.anticipation) + ANTICIPATION_PER_RANK * maxi(0, rank - 2)
	var t := 0.0
	for m in MOMENTS:
		_start[m] = t
		t += float(_dur[m])
	_total = t


## Progresso 0..1 de um momento no instante t.
func _u(t: float, moment: String) -> float:
	var a := float(_start[moment])
	var d := float(_dur[moment])
	if d <= 0.0:
		return 1.0 if t >= a else 0.0
	return clampf((t - a) / d, 0.0, 1.0)


func _motion() -> float:
	return 0.0 if reduce_motion else 1.0


## Escala do pacote (px do pacote -> px da tela), posição de repouso e a carta final.
func _metrics() -> Dictionary:
	var pack_h := minf(size.y * 0.56, size.x * 0.78 * PACK_PX.y / PACK_PX.x)
	var card_h := minf(size.y * 0.74, size.x * 0.84 * StickerCard.ASPECT)
	var card_w := card_h / StickerCard.ASPECT
	return {
		"k": pack_h / PACK_PX.y,
		"rest": Vector2(size.x / 2.0, size.y * 0.57),
		"px": size.y / 720.0,
		"card_center": Vector2(size.x / 2.0, size.y * 0.53),
		"card_w": card_w,
	}


func _layout_card() -> void:
	var m := _metrics()
	_card.size = Vector2(m.card_w, m.card_w * StickerCard.ASPECT)
	_card.pivot_offset = _card.size / 2.0


## Estado do pacote no instante t: {pos, rot, scale (relativa a k), skew, alpha}.
func _pack_state(t: float) -> Dictionary:
	var m := _metrics()
	var px: float = m.px
	var mo := _motion()
	var pos: Vector2 = m.rest
	var rot := 0.0
	var alpha := 1.0
	# Entrada: sobe de baixo e acomoda com uma oscilação amortecida.
	var ue := _u(t, "enter")
	pos.y += (1.0 - _ease_out_back(ue, 1.25)) * size.y * 0.8 * mo
	alpha = clampf(ue * (3.0 if mo > 0.0 else 1.0), 0.0, 1.0)
	var since := t - float(_start.enter) - float(_dur.enter) * 0.6
	if since > 0.0:
		rot += 0.045 * sin(since * 15.0) * exp(-since * 5.5) * mo
	# Tensão: cantos contraem e o topo inclina; solta com um rebote no rasgo.
	var q := _ease_in_out_sine(_u(t, "tension"))
	var ut := _u(t, "tear")
	if ut > 0.0:
		q = 1.0 - _ease_out_back(ut, 2.2)
	q *= mo
	_tension = clampf(q, 0.0, 1.0) * (1.0 - ut)
	var intensity := 1.0 + 0.35 * maxi(0, rank - 2)
	var scale := Vector2(1.0 - 0.04 * q, 1.0 + 0.018 * q)
	var skew := -0.06 * q
	rot += -0.025 * q
	if t >= float(_start.tension) and ut < 1.0:
		pos.x += sin(t * 95.0) * 2.2 * px * maxf(q, 0.0) * intensity
	# Antecipação: afunda um pouco e respira; raridade alta treme.
	var ua := _u(t, "anticipation")
	pos.y += 8.0 * px * _ease_out_cubic(ua) * mo
	scale *= 1.0 + 0.012 * sin(ua * PI) * mo
	if rank >= 3 and ua > 0.0 and ua < 1.0:
		pos.x += sin(t * 60.0) * 1.3 * px * ua * (rank - 2) * mo
	# Revelação: afunda enquanto a carta sobe e depois sai por baixo.
	var ur := _u(t, "reveal")
	pos.y += size.y * 0.22 * _ease_in_out_sine(clampf(ur / RISE_END, 0.0, 1.0)) * mo
	var out := clampf((ur - RISE_END) / (1.0 - RISE_END), 0.0, 1.0)
	pos.y += size.y * 0.7 * _ease_in_cubic(out) * mo
	alpha *= 1.0 - (_ease_in_cubic(out) if mo > 0.0 else clampf(ur * 2.0, 0.0, 1.0))
	return {"pos": pos, "rot": rot, "scale": scale, "skew": skew, "alpha": alpha}


## Ponto em px do pacote (quadro 571 x 824) -> tela, com o pacote no estado ps.
func _pack_to_screen(ps: Dictionary, p: Vector2) -> Vector2:
	var k: float = _metrics().k
	var local: Vector2 = (p - PACK_PX / 2.0) * (ps.scale as Vector2) * k
	return (ps.pos as Vector2) + local.rotated(float(ps.rot))


## Estado da carta: {visible, pos (centro na tela), rot, scale (relativa à final), front, alpha}.
func _card_state(t: float) -> Dictionary:
	var m := _metrics()
	var k: float = m.k
	var card_w_pack := CARD_IN_PACK_W
	var card_h_pack := card_w_pack * StickerCard.ASPECT
	var body_top := StickerCard.BODY_RECT.position.y / StickerCard.CARD_PX.y * card_h_pack
	var body_bottom := StickerCard.BODY_RECT.end.y / StickerCard.CARD_PX.y * card_h_pack
	# Centro da carta (y no quadro do pacote) escondida e depois de sair.
	var y_hidden := CARD_HIDDEN_TOP - body_top + card_h_pack / 2.0
	var y_risen := CARD_RISEN_BOTTOM - body_bottom + card_h_pack / 2.0
	var s_in := card_w_pack * k / float(m.card_w)
	var st := {"visible": t >= float(_start.anticipation), "pos": m.card_center, "rot": 0.0,
		"scale": 1.0, "front": true, "alpha": 1.0}
	if reduce_motion:
		var ur0 := _u(t, "reveal")
		st.visible = ur0 > 0.0
		st.alpha = ur0
		return st
	var peek := CARD_PEEK * _ease_in_out_sine(clampf((_u(t, "anticipation") - 0.55) / 0.45, 0.0, 1.0))
	var ur := _u(t, "reveal")
	var r := _ease_out_cubic(clampf(ur / RISE_END, 0.0, 1.0))
	var tilt := -0.11 * r
	if ur <= RISE_END:
		var ps := _pack_state(t)
		var y := lerpf(y_hidden - peek, y_risen, r)
		st.pos = _pack_to_screen(ps, Vector2(PACK_PX.x / 2.0, y))
		st.rot = float(ps.rot) + tilt
		st.scale = s_in * (ps.scale as Vector2).x
		st.front = false
		return st
	var t_rise := float(_start.reveal) + float(_dur.reveal) * RISE_END
	var ps_rise := _pack_state(t_rise)
	var from := _pack_to_screen(ps_rise, Vector2(PACK_PX.x / 2.0, y_risen))
	var s := (ur - RISE_END) / (1.0 - RISE_END)
	var b := _ease_out_back(s, 1.5)
	st.pos = from.lerp(m.card_center, _ease_out_cubic(s))
	st.scale = lerpf(s_in * (ps_rise.scale as Vector2).x, 1.0, b)
	st.rot = lerpf(float(ps_rise.rot) - 0.11, 0.0, b)
	var ui := _u(t, "inspect")
	st.scale = float(st.scale) * (1.0 + 0.035 * sin(ui * PI))
	return st


func _apply(t: float) -> void:
	_t = t
	if card.is_empty():
		return
	var m := _metrics()
	var ps := _pack_state(t)
	_pack.position = ps.pos
	_pack.rotation = ps.rot
	_pack.scale = (ps.scale as Vector2) * float(m.k)
	_pack.skew = ps.skew
	_pack.modulate.a = ps.alpha
	_pack.visible = float(ps.alpha) > 0.001
	var torn := t >= float(_start.tear)
	_front.visible = not torn
	_body.visible = torn
	_interior.visible = torn
	_shadow.texture = _tex_body if torn else _tex_front
	# Faixa: a ponta esquerda levanta (gira na direita) e ela sai de lado, caindo.
	var ut := _u(t, "tear")
	_strip_pivot.visible = ut < 1.0
	if reduce_motion:
		_strip_pivot.position = STRIP_PIVOT - PACK_PX / 2.0
		_strip_pivot.rotation = 0.0
		_strip_pivot.modulate.a = 1.0 - ut
	else:
		var lift := _ease_out_cubic(clampf(ut / 0.5, 0.0, 1.0))
		var fly := clampf((ut - 0.2) / 0.8, 0.0, 1.0)
		_strip_pivot.rotation = 0.45 * lift + 0.5 * fly * fly
		_strip_pivot.position = STRIP_PIVOT - PACK_PX / 2.0 + Vector2(
			900.0 * _ease_in_cubic(fly), -30.0 * sin(PI * clampf(ut / 0.6, 0.0, 1.0)) + 220.0 * fly * fly)
		_strip_pivot.modulate.a = 1.0 - clampf((ut - 0.7) / 0.3, 0.0, 1.0)
	var cs := _card_state(t)
	_card.visible = bool(cs.visible)
	_card.position = (cs.pos as Vector2) - _card.size / 2.0
	_card.rotation = cs.rot
	_card.scale = Vector2.ONE * float(cs.scale)
	_card.z_index = 3 if cs.front else 1
	_card.modulate.a = cs.alpha
	_rays_layer.queue_redraw()
	_mouth.queue_redraw()
	_creases.queue_redraw()
	_fx.queue_redraw()


# --- partículas (semente fixa pela carta) ------------------------------------------------------------

func _build_particles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|%s" % [card.get("athlete_id", ""), card.get("tier", ""), card.get("frame", "")])
	_fragments.clear()
	_fibers.clear()
	_confetti.clear()
	_rays.clear()
	if not reduce_motion:
		for i in FRAGMENT_COUNT:
			var x := lerpf(70.0, 500.0, (i + 0.5) / FRAGMENT_COUNT) + rng.randf_range(-20.0, 20.0)
			_fragments.append({"tex": i, "x": x, "vx": rng.randf_range(-240.0, 240.0) + (x - PACK_PX.x / 2.0) * 0.8,
				"vy": rng.randf_range(-680.0, -420.0), "spin": rng.randf_range(-7.0, 7.0),
				"rot0": rng.randf_range(-0.6, 0.6), "scale": rng.randf_range(0.5, 0.8), "delay": rng.randf_range(0.0, 0.08)})
		for i in 16:
			_fibers.append({"x": rng.randf_range(60.0, 510.0), "ang": -PI / 2.0 + rng.randf_range(-1.0, 1.0),
				"len": rng.randf_range(10.0, 30.0), "speed": rng.randf_range(80.0, 240.0),
				"w": rng.randf_range(1.6, 3.0), "dark": rng.randf() < 0.35})
		var palette := [_color_mid, _color_light, CREAM, BRAND_YELLOW, _color_mid.darkened(0.3)]
		for i in 16 + 8 * rank:
			var shape := PackedVector2Array()
			var n := rng.randi_range(4, 6)
			for j in n:
				var a := TAU * j / n + rng.randf_range(-0.35, 0.35)
				shape.append(Vector2(cos(a), sin(a) * rng.randf_range(0.45, 1.0)) * rng.randf_range(0.6, 1.0))
			var dir := -PI / 2.0 + rng.randf_range(-1.25, 1.25)
			var spd := rng.randf_range(420.0, 980.0)
			_confetti.append({"shape": shape, "color": palette[rng.randi() % palette.size()],
				"ox": rng.randf_range(-60.0, 60.0), "oy": rng.randf_range(-60.0, 40.0),
				"vx": cos(dir) * spd, "vy": sin(dir) * spd, "spin": rng.randf_range(-9.0, 9.0),
				"rot0": rng.randf_range(0.0, TAU), "size": rng.randf_range(7.0, 15.0),
				"sway_f": rng.randf_range(3.0, 7.0), "sway_a": rng.randf_range(8.0, 26.0),
				"delay": rng.randf_range(0.0, 0.12), "behind": i % 3 != 0})
	var n_rays := 8 + 2 * rank
	for i in n_rays:
		var edge: Array = []
		for j in 9:
			edge.append(rng.randf_range(-1.0, 1.0))
		var dots: Array = []
		for j in 3 + rank:
			dots.append(Vector3(rng.randf_range(0.5, 0.97), rng.randf_range(-1.3, 1.3), rng.randf_range(1.5, 4.5)))
		_rays.append({"wide": i % 2 == 0, "edge": edge, "dots": dots, "len": rng.randf_range(0.82, 1.0)})


# --- desenho -------------------------------------------------------------------------------------------

## Raios de tinta atrás da carta, com bordas porosas e respingos; níveis altos ganham uma segunda
## coroa girando ao contrário.
func _draw_rays(ci: Node2D) -> void:
	if dim > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, dim))
	if card.is_empty() or _rays.is_empty():
		return
	var t := _t
	var appear_t := float(_start.reveal) + float(_dur.reveal) * (RISE_END - 0.08)
	var a := clampf((t - appear_t) / 0.35, 0.0, 1.0)
	if a <= 0.0:
		return
	var m := _metrics()
	var center: Vector2 = _card_state(t).pos
	var big := maxf(size.x, size.y) * 0.85 * (0.6 + 0.4 * _ease_out_back(a, 1.6))
	var turn := (t - appear_t) * 0.12 * _motion()
	_draw_ray_ring(ci, center, big, turn, Color(_color_mid, 0.55 * a), 1.0, float(m.px))
	if rank >= 3:
		_draw_ray_ring(ci, center, big * 0.62, -turn * 1.6 + 0.2, Color(_color_light, 0.4 * a), 0.55, float(m.px))
	_draw_confetti(ci, true)


func _draw_ray_ring(ci: Node2D, center: Vector2, radius: float, turn: float, color: Color, width_k: float, px: float) -> void:
	var n := _rays.size()
	for i in n:
		var ray: Dictionary = _rays[i]
		var ang := turn + TAU * i / n
		var half := TAU / n * (0.26 if ray.wide else 0.14) * width_k
		var r_out := radius * float(ray.len)
		var edge: Array = ray.edge
		var pts := PackedVector2Array()
		pts.append(center)
		# Borda esquerda, ponta porosa e borda direita.
		for j in 3:
			var rr := r_out * (0.35 + 0.3 * j)
			pts.append(center + Vector2.from_angle(ang - half).rotated(float(edge[j]) * 0.006) * rr)
		for j in 5:
			var aa := ang - half + 2.0 * half * (j / 4.0)
			pts.append(center + Vector2.from_angle(aa) * r_out * (1.0 - 0.05 * absf(float(edge[3 + j % 5]))))
		for j in range(2, -1, -1):
			var rr := r_out * (0.35 + 0.3 * j)
			pts.append(center + Vector2.from_angle(ang + half).rotated(float(edge[6 + j]) * 0.006) * rr)
		ci.draw_colored_polygon(pts, color)
		for d in ray.dots:
			var dv: Vector3 = d
			var p := center + Vector2.from_angle(ang + half * dv.y) * r_out * dv.x
			ci.draw_circle(p, dv.z * px, color)


## Abertura: a cor da raridade surge pela boca do envelope (atrás do corpo, na frente do interior).
func _draw_mouth(ci: Node2D) -> void:
	if card.is_empty() or _t < float(_start.anticipation):
		return
	var t := _t
	var ua := _u(t, "anticipation")
	var a := _ease_out_cubic(clampf(ua / 0.6, 0.0, 1.0))
	if float(_dur.anticipation) <= 0.0:
		a = 1.0
	var since := t - float(_start.anticipation)
	var pulse := 0.5 + 0.5 * sin(since * TAU * (1.6 + 0.3 * rank)) * _motion()
	var c := Vector2(PACK_PX.x / 2.0, TEAR_Y - 4.0) - PACK_PX / 2.0
	_porous_ellipse(ci, c, MOUTH_HALF * Vector2(1.0, 1.0 + 0.3 * pulse), Color(_color_mid, 0.92 * a), 0)
	_porous_ellipse(ci, c + Vector2(0, 4), MOUTH_HALF * Vector2(0.62, 0.55 + 0.2 * pulse), Color(_color_light, 0.85 * a), 7)
	var leaks := 5 + rank
	for i in leaks:
		var f := (i + 0.5) / leaks
		var ang := -PI / 2.0 + lerpf(-0.85, 0.85, f)
		var length := (150.0 + 130.0 * sin(f * PI)) * a * (0.85 + 0.15 * pulse)
		var half := 0.035 + 0.02 * float(i % 2)
		var base := c + Vector2(lerpf(-MOUTH_HALF.x * 0.7, MOUTH_HALF.x * 0.7, f), 0.0)
		var pts := PackedVector2Array([base + Vector2(-10, 0), base + Vector2.from_angle(ang - half) * length,
			base + Vector2.from_angle(ang) * length * 0.94, base + Vector2.from_angle(ang + half) * length,
			base + Vector2(10, 0)])
		ci.draw_colored_polygon(pts, Color(_color_light, 0.5 * a))


func _porous_ellipse(ci: Node2D, c: Vector2, half: Vector2, color: Color, salt: int) -> void:
	var pts := PackedVector2Array()
	var n := 36
	for i in n:
		var ang := TAU * i / n
		var j := 1.0 - 0.07 * absf(sin(ang * 7.0 + salt) * cos(ang * 3.0 + salt * 0.5))
		pts.append(c + Vector2(cos(ang) * half.x, sin(ang) * half.y) * j)
	ci.draw_colored_polygon(pts, color)


## Rugas desenhadas da tensão: traço de tinta com um fio de luz ao lado.
func _draw_creases(ci: Node2D) -> void:
	if _tension <= 0.01:
		return
	var o := -PACK_PX / 2.0
	for line in CREASES:
		var pts := PackedVector2Array()
		var hi := PackedVector2Array()
		for p in line:
			pts.append((p as Vector2) + o)
			hi.append((p as Vector2) + o + Vector2(2.5, 2.0))
		ci.draw_polyline(hi, Color(CREAM, 0.5 * _tension), 2.0, true)
		ci.draw_polyline(pts, Color(INK, 0.42 * _tension), 2.6, true)


## Fragmentos e fibras do rasgo, confete de papel da revelação (sombras chapadas, sem desfoque).
func _draw_fx(ci: Node2D) -> void:
	if card.is_empty() or skipped:
		return
	var t := _t
	var m := _metrics()
	var px: float = m.px
	var k: float = m.k
	var t_tear := float(_start.tear)
	if t >= t_tear and not _fragments.is_empty():
		var ps := _pack_state(t_tear)
		var g := 1600.0
		for f in _fragments:
			var age := t - t_tear - float(f.delay)
			if age <= 0.0 or age > 1.1:
				continue
			var p0 := _pack_to_screen(ps, Vector2(float(f.x), TEAR_Y))
			var d := Vector2(float(f.vx) * age, float(f.vy) * age + 0.5 * g * age * age) * k
			var alpha := 1.0 - clampf((age - 0.7) / 0.4, 0.0, 1.0)
			var tex: Texture2D = _fragment_tex[int(f.tex)]
			var sc := float(f.scale) * k * 0.9
			var rot := float(f.rot0) + float(f.spin) * age
			ci.draw_set_transform(p0 + d + Vector2(4, 5) * px, rot, Vector2(sc, sc))
			ci.draw_texture(tex, -tex.get_size() / 2.0, Color(SHADOW_COLOR, SHADOW_COLOR.a * alpha))
			ci.draw_set_transform(p0 + d, rot, Vector2(sc, sc))
			ci.draw_texture(tex, -tex.get_size() / 2.0, Color(1, 1, 1, alpha))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for fb in _fibers:
			var age := t - t_tear
			if age > 0.35:
				continue
			var base := _pack_to_screen(ps, Vector2(float(fb.x), TEAR_Y))
			var dir := Vector2.from_angle(float(fb.ang))
			var start := base + dir * float(fb.speed) * age * k
			var length := float(fb.len) * k * 2.0 * _ease_out_cubic(clampf(age / 0.12, 0.0, 1.0))
			var alpha := 1.0 - clampf((age - 0.15) / 0.2, 0.0, 1.0)
			var col := PAPER_DARK if fb.dark else CREAM
			ci.draw_line(start, start + dir * length, Color(col, alpha), float(fb.w) * px, true)
	_draw_confetti(ci, false)


## Confete de papel: dois terços atrás da carta (camada dos raios), um terço na frente e maior
## (mais perto da câmera), para não cobrir o rosto na inspeção.
func _draw_confetti(ci: Node2D, behind: bool) -> void:
	if card.is_empty() or skipped or _confetti.is_empty():
		return
	var t := _t
	var t_burst := float(_start.reveal) + float(_dur.reveal) * RISE_END
	if t < t_burst:
		return
	var px: float = _metrics().px
	var origin: Vector2 = _card_state(t_burst).pos
	var drag := 2.4
	var g2 := 900.0
	var near := 1.0 if behind else 1.35
	for cf in _confetti:
		if bool(cf.behind) != behind:
			continue
		var age := t - t_burst - float(cf.delay)
		if age <= 0.0 or age > 2.6:
			continue
		var e := (1.0 - exp(-drag * age)) / drag
		var x := float(cf.vx) * near * e + sin(age * float(cf.sway_f)) * float(cf.sway_a) * minf(age * 2.0, 1.0)
		var y := (float(cf.vy) * near - g2 / drag) * e + g2 / drag * age
		var p := origin + (Vector2(float(cf.ox), float(cf.oy)) + Vector2(x, y)) * px
		var rot := float(cf.rot0) + float(cf.spin) * age
		var flip := absf(cos(age * float(cf.sway_f) * 0.8))   # gira em 3D: encolhe num eixo
		var alpha := 1.0 - clampf((age - 1.9) / 0.7, 0.0, 1.0)
		var sz := float(cf.size) * px * near
		var pts := PackedVector2Array()
		var sh := PackedVector2Array()
		for q in cf.shape:
			var v := (q as Vector2) * Vector2(sz, sz * (0.25 + 0.75 * flip))
			pts.append(p + v.rotated(rot))
			sh.append(p + v.rotated(rot) + Vector2(3, 4) * px)
		ci.draw_colored_polygon(sh, Color(SHADOW_COLOR, 0.3 * alpha))
		ci.draw_colored_polygon(pts, Color(cf.color as Color, alpha))


# --- utilitários --------------------------------------------------------------------------------------

static func _sprite(tex: Texture2D, offset: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = offset
	return s


static func _ease_out_cubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func _ease_in_cubic(x: float) -> float:
	return x * x * x


static func _ease_in_out_sine(x: float) -> float:
	return -(cos(PI * x) - 1.0) / 2.0


static func _ease_out_back(x: float, s: float = 1.70158) -> float:
	var c3 := s + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + s * pow(x - 1.0, 2.0)


## Camada de desenho que delega o _draw para o ritual.
class Layer:
	extends Node2D
	var draw_fn: Callable

	func _init(fn: Callable) -> void:
		draw_fn = fn

	func _draw() -> void:
		draw_fn.call(self)
