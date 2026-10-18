class_name MatchIntroOverlay
extends CanvasLayer
## Antes do apito: apresentação dos dois times, cara ou coroa, a moeda do juiz girando no ar e caindo
## no gramado, e a escolha de bola ou campo. Quem ganha escolhe; quem perde fica com o que sobrou
## (bola -> o outro escolhe o lado; campo -> o outro dá a saída). O jogador é sempre o mandante.
## Termina com `finished(kickoff_side, home_dir)`, que vai para o MatchSetup antes de a partida começar.

signal finished(kickoff_side: String, home_dir: int)

const PRESENT_SECONDS := 3.0
const COIN_SECONDS := 1.8
const VERDICT_SECONDS := 1.6
const COIN_SIZE := 96.0

## Preferência de acessibilidade: sem giro nem quique (a moeda já aparece no chão).
var reduce_motion := false
## O campo está desenhado em pé (celular em retrato): as setas de lado giram junto.
var pitch_rotated := false

var _home: TeamSetup
var _away: TeamSetup
var _home_ovr := 0
var _away_ovr := 0
var _rng := RandomNumberGenerator.new()
var _root: Control
var _box: VBoxContainer
var _coin: TossCoin
var _stage := ""
var _tween: Tween


func _ready() -> void:
	layer = 16
	# CanvasLayer fica fora da moldura de leitura: amplia por conta própria (como MatchSummaryOverlay),
	# senão no celular em retrato tudo aparece no tamanho de 1100 px lógicos encolhidos.
	_root = Control.new()
	_root.theme = DesignTokens.base_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_tap)
	add_child(_root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.04, 0.08, 0.82)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_box = UiKit.vbox(DesignTokens.SPACING_LG)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.custom_minimum_size.x = 300
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_box)
	visible = false
	_layout()


func _process(_delta: float) -> void:
	if visible and (not is_equal_approx(_root.scale.x, _scale()) or not _root.size.is_equal_approx(_logical())):
		_layout()


func _scale() -> float:
	var s := get_node_or_null("/root/Settings")
	return s.readability_scale() if s else 1.0


func _logical() -> Vector2:
	return get_viewport().get_visible_rect().size / _scale()


func _layout() -> void:
	var k := _scale()
	_root.scale = Vector2(k, k)
	_root.size = _logical()


func start(home: TeamSetup, away: TeamSetup) -> void:
	_home = home
	_away = away
	_home_ovr = GameStore.strength(home.lineup).ovr
	_away_ovr = GameStore.strength(away.lineup).ovr
	_rng.randomize()
	visible = true
	_present()


func is_open() -> bool:
	return visible


# ------------------------------------------------------------------ 1. apresentação
func _present() -> void:
	_stage = "present"
	_clear()
	_box.add_child(_heading(tr("SORTEIO_APRESENTACAO")))
	var row := UiKit.hbox(DesignTokens.SPACING_LG)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_team_block(_home, _home_ovr))
	var vs := UiKit.title(tr("SORTEIO_VS"), UiKit.FONT_DISPLAY)
	vs.add_theme_color_override("font_color", UiKit.YELLOW)
	row.add_child(vs)
	row.add_child(_team_block(_away, _away_ovr))
	_box.add_child(row)
	var hint := UiKit.label(tr("SORTEIO_TOQUE"), UiKit.FONT_BODY, Color(1, 1, 1, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(hint)
	if not reduce_motion:
		row.modulate.a = 0.0
		_tw().tween_property(row, "modulate:a", 1.0, 0.4)
	get_tree().create_timer(PRESENT_SECONDS, false).timeout.connect(func() -> void:
		if _stage == "present":
			_ask_call())


func _team_block(t: TeamSetup, ovr: int) -> Control:
	var v := UiKit.vbox(DesignTokens.SPACING_SM)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size.x = 130
	var crest_box := CenterContainer.new()
	crest_box.add_child(ClubCrest.for_colors(t.color, _secondary(t.color), t.short_name, 104))
	v.add_child(crest_box)
	var n := UiKit.title(t.name, UiKit.FONT_H2)
	n.add_theme_color_override("font_color", Color.WHITE)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size.x = 130
	v.add_child(n)
	var badge_box := CenterContainer.new()
	badge_box.add_child(UiKit.ovr_badge(ovr, 52))
	v.add_child(badge_box)
	return v


static func _secondary(c: Color) -> Color:
	return Color.WHITE if c.get_luminance() < 0.6 else UiKit.INK


func _on_tap(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if tap and _stage == "present":
		_ask_call()


# ------------------------------------------------------------------ 2. cara ou coroa
func _ask_call() -> void:
	_stage = "call"
	_clear()
	_box.add_child(_heading(tr("SORTEIO_ESCOLHA")))
	var row := UiKit.hbox(DesignTokens.SPACING_LG)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_coin_choice(true))
	row.add_child(_coin_choice(false))
	_box.add_child(row)


func _coin_choice(heads: bool) -> Control:
	var b := Button.new()
	b.name = "Heads" if heads else "Tails"
	b.custom_minimum_size = Vector2(120, 132)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UiKit.style_button(b, "secondary")
	var v := UiKit.vbox(DesignTokens.SPACING_XS)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin_box := CenterContainer.new()
	coin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := TossCoin.new(64)
	face.heads = heads
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_box.add_child(face)
	v.add_child(coin_box)
	var l := UiKit.label(tr("SORTEIO_CARA") if heads else tr("SORTEIO_COROA"), UiKit.FONT_H2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	b.add_child(v)
	b.pressed.connect(func() -> void: _toss(heads))
	return b


# ------------------------------------------------------------------ 3. a moeda
func _toss(called_heads: bool) -> void:
	if _stage != "call":
		return
	_stage = "toss"
	_clear()
	var result_heads := fair_flip()
	var user_won := result_heads == called_heads
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(240, 260)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(stage)
	var grass := ColorRect.new()
	grass.color = Color("#2f7d3b")
	grass.size = Vector2(240, 44)
	grass.position = Vector2(0, 216)
	stage.add_child(grass)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.7)
	line.size = Vector2(240, 3)
	line.position = Vector2(0, 228)
	stage.add_child(line)
	_coin = TossCoin.new(COIN_SIZE)
	_coin.heads = result_heads
	var ground := Vector2(120 - COIN_SIZE / 2.0, 216 - COIN_SIZE * 0.72)
	_coin.position = ground
	stage.add_child(_coin)
	SfxService.play("apito_inicio", -8.0, 0.0)
	if reduce_motion:
		_coin.spin = 1.0
		_verdict(user_won, result_heads)
		return
	# Sobe girando, cai no gramado e quica uma vez; o giro termina na face sorteada.
	var top := ground - Vector2(0, 170)
	var turns := 6.0
	var tw := _tw()
	tw.set_parallel(true)
	tw.tween_property(_coin, "position", top, COIN_SECONDS * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_coin, "position", ground, COIN_SECONDS * 0.4).set_delay(COIN_SECONDS * 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_coin, "position", ground - Vector2(0, 18), 0.08).set_delay(COIN_SECONDS * 0.85)
	tw.tween_property(_coin, "position", ground, 0.08).set_delay(COIN_SECONDS * 0.85 + 0.08)
	tw.tween_method(func(t: float) -> void: _coin.spin = t, -turns, 1.0, COIN_SECONDS * 0.85) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func() -> void: _verdict(user_won, result_heads))


## Cara (true) ou coroa (false), 50% cada, com entropia do sistema operacional: não depende do
## relógio (como `randomize()`), então partidas seguidas não repetem a mesma face por coincidência.
static func fair_flip() -> bool:
	return Crypto.new().generate_random_bytes(1)[0] & 1 == 0


func _verdict(user_won: bool, _result_heads: bool) -> void:
	_stage = "verdict"
	var msg := tr("SORTEIO_GANHOU") if user_won else tr("SORTEIO_PERDEU") % _away.name
	var h := _heading(msg)
	_box.add_child(h)
	_box.move_child(h, 0)
	get_tree().create_timer(0.9 if user_won else 0.6, false).timeout.connect(func() -> void:
		if user_won:
			_ask_ball_or_field()
		else:
			_opponent_choice())


# ------------------------------------------------------------------ 4. bola ou campo
func _ask_ball_or_field() -> void:
	_stage = "choice"
	_clear()
	_box.add_child(_heading(tr("SORTEIO_GANHOU")))
	var row := UiKit.hbox(DesignTokens.SPACING_MD)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var ball := UiKit.button(tr("SORTEIO_BOLA"), "primary", "jogar", 64)
	ball.text = tr("SORTEIO_BOLA")   # escolha que decide a partida: o texto fica
	ball.name = "Ball"
	ball.tooltip_text = tr("SORTEIO_BOLA_DICA")
	ball.custom_minimum_size.x = 150
	ball.add_theme_font_size_override("font_size", UiKit.FONT_H2)
	# Bola: o adversário escolhe o lado.
	ball.pressed.connect(func() -> void: _finish("home", -1 if _rng.randi() % 2 == 0 else 1))
	row.add_child(ball)
	var field := UiKit.button(tr("SORTEIO_CAMPO"), "secondary", "estadio", 64)
	field.text = tr("SORTEIO_CAMPO")
	field.name = "Field"
	field.tooltip_text = tr("SORTEIO_CAMPO_DICA")
	field.custom_minimum_size.x = 150
	field.add_theme_font_size_override("font_size", UiKit.FONT_H2)
	field.pressed.connect(func() -> void: _ask_side("away"))
	row.add_child(field)
	_box.add_child(row)


## O jogador escolhe para onde ataca no 1º tempo; `kickoff_side` já está decidido.
func _ask_side(kickoff_side: String) -> void:
	_stage = "side"
	_clear()
	_box.add_child(_heading(tr("SORTEIO_LADO")))
	var row := UiKit.hbox(DesignTokens.SPACING_LG)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for dir in [-1, 1]:
		var b := Button.new()
		b.name = "Side%d" % dir
		b.custom_minimum_size = Vector2(120, 120)
		b.tooltip_text = tr("SORTEIO_ESQUERDA") if dir < 0 else tr("SORTEIO_DIREITA")
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		UiKit.style_button(b, "secondary")
		var arrow := SideArrow.new()
		arrow.dir = dir
		arrow.rotated = pitch_rotated
		arrow.color = _home.color
		arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
		arrow.offset_left = 14
		arrow.offset_top = 14
		arrow.offset_right = -14
		arrow.offset_bottom = -14
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(arrow)
		b.pressed.connect(func() -> void: _finish(kickoff_side, dir))
		row.add_child(b)
	_box.add_child(row)


## O adversário ganhou: escolhe ao acaso; se ficar com a bola, o jogador escolhe o lado.
func _opponent_choice() -> void:
	_stage = "opponent"
	_clear()
	var takes_ball := _rng.randi() % 2 == 0
	_box.add_child(_heading(tr("SORTEIO_PERDEU") % _away.name))
	var l := UiKit.label((tr("SORTEIO_ADV_BOLA") if takes_ball else tr("SORTEIO_ADV_CAMPO")) % _away.name,
		UiKit.FONT_H2, Color.WHITE, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(l)
	get_tree().create_timer(VERDICT_SECONDS, false).timeout.connect(func() -> void:
		if takes_ball:
			_ask_side("away")
		else:
			_finish("home", -1 if _rng.randi() % 2 == 0 else 1))


func _finish(kickoff_side: String, home_dir: int) -> void:
	if _stage == "done":
		return
	_stage = "done"
	visible = false
	_clear()
	finished.emit(kickoff_side, home_dir)


# ------------------------------------------------------------------ apoio
func _heading(text: String) -> Label:
	var l := UiKit.title(text, UiKit.FONT_TITLE)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	return l


func _clear() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	ScreenBase.clear(_box)


func _tw() -> Tween:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	return _tween


## Moeda desenhada por código no traço do jogo (contorno de tinta, cor chapada). `spin` em voltas:
## a largura segue |cos| e a face visível troca a cada meia volta; termina (spin inteiro) na face
## sorteada. Cara: mostarda com estrela. Coroa: azul-petróleo com coroa.
class TossCoin extends Control:
	var heads := true
	var spin := 1.0:
		set(v):
			spin = v
			queue_redraw()

	func _init(p_size: float = 96.0) -> void:
		custom_minimum_size = Vector2(p_size, p_size)
		size = custom_minimum_size

	func _draw() -> void:
		var c := cos(spin * TAU)
		var showing_heads := heads if c >= 0.0 else not heads
		var r := size.x / 2.0
		var w := maxf(absf(c), 0.06)
		draw_set_transform(Vector2(r, r), 0.0, Vector2(w, 1.0))
		var fill := UiKit.YELLOW if showing_heads else Color("#005d89")
		draw_circle(Vector2.ZERO, r, Color("#151515"))
		draw_circle(Vector2.ZERO, r * 0.9, fill)
		draw_arc(Vector2.ZERO, r * 0.74, 0.0, TAU, 40, Color(0, 0, 0, 0.35), 2.0)
		var ink := Color("#151515") if showing_heads else Color("#fcf6e6")
		if showing_heads:
			draw_colored_polygon(_star(r * 0.5), ink)
		else:
			draw_colored_polygon(_crown(r * 0.5), ink)
		draw_set_transform(Vector2.ZERO)

	static func _star(s: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI / 2.0 + i * PI / 5.0
			pts.append(Vector2(cos(a), sin(a)) * (s if i % 2 == 0 else s * 0.45))
		return pts

	static func _crown(s: float) -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(-s, s * 0.55), Vector2(-s, -s * 0.45), Vector2(-s * 0.5, s * 0.05), Vector2(0, -s * 0.7),
			Vector2(s * 0.5, s * 0.05), Vector2(s, -s * 0.45), Vector2(s, s * 0.55)])


## Mini-campo com a seta do lado para onde o time ataca (gira com o campo no celular em pé).
class SideArrow extends Control:
	var dir := 1
	var rotated := false
	var color := Color.WHITE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("#2f7d3b"))
		draw_rect(r, Color(1, 1, 1, 0.8), false, 2.0)
		var c := size / 2.0
		var along := Vector2(0, dir) if rotated else Vector2(dir, 0)
		var across := Vector2(along.y, along.x)
		if rotated:
			draw_line(Vector2(0, c.y), Vector2(size.x, c.y), Color(1, 1, 1, 0.8), 2.0)
		else:
			draw_line(Vector2(c.x, 0), Vector2(c.x, size.y), Color(1, 1, 1, 0.8), 2.0)
		var len := (size.y if rotated else size.x) * 0.36
		var tip := c + along * len
		var tail := c - along * len
		var col := color if color.get_luminance() > 0.2 else Color.WHITE
		draw_line(tail, tip - along * 10, Color("#151515"), 10.0)
		draw_line(tail, tip - along * 10, col, 6.0)
		draw_colored_polygon(PackedVector2Array([tip, tip - along * 18 + across * 12, tip - along * 18 - across * 12]), col)
		draw_polyline(PackedVector2Array([tip, tip - along * 18 + across * 12, tip - along * 18 - across * 12, tip]),
			Color("#151515"), 2.0)
