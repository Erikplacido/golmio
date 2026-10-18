extends Node2D
## Visualizador 2D da partida. Só LÊ o estado do motor (MatchEngine.ctx) e desenha;
## nenhuma regra mora aqui. Velocidades do GDD 3: 1x = 90 min em REAL_SECONDS_AT_1X reais, até 5x.
## Teclas: Espaço pausa | 1 a 5 velocidade | C pula para o próximo lance crítico | R nova partida.
## Toque: barra MatchTouchBar (Settings "touch_controls").
## Responsivo: o campo é escalado para caber na área livre entre o placar e a barra inferior e,
## quando a área é bem mais alta que larga (celular em retrato), gira 90° para ficar maior.

const ORIGIN := Vector2(75.0, 70.0)
## Folga ao redor do gramado (gols, jogadores na linha de fundo).
const PITCH_PAD := 14.0
const HUD_TOP := 62.0
const HUD_MSG_H := 30.0
## Campo pintado do mandante (PitchSkins; arte em visuais/campo/): 4 px por unidade em @4x, com
## sangria de 32 unidades em volta do campo. Sem os arquivos, volta às faixas desenhadas.
const PITCH_TEXTURE_BLEED := 32.0
## Tamanho VISUAL das peças de botão, em unidades do campo. É maior que o raio físico do motor
## (7,2 / 8 / 4,5) para a peça ter leitura; a simulação não muda.
const PIECE_R := 12.0
const GK_PIECE_R := 13.0
const BALL_R := 5.5
const GK_TINT := Color("#f59e0b")
## 1x um pouco mais lento que os 120 s originais, para dar para acompanhar os lances (em ajuste).
const REAL_SECONDS_AT_1X := 150.0
## ¼× e ½× para assistir com calma (90 min em 10 e 5 min reais); 1× = 90 min em 150 s.
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0]
const CRITICAL_EVENTS := ["goal", "save", "foul", "yellow_card", "red_card", "penalty", "offside"]
const DEMO_HINTS := "[Espaço] pausa · [9/0/1-5] velocidade · [S] sandbox status · [C] lance crítico · [P] replay · [V] vinhetas · [T] táticas · [R] nova · [F10] opções"

var engine: MatchEngine
var _quiet := false                # pulando até o lance crítico: só o lance encontrado faz som
var _period_end_at := -10.0        # s; o apito de fim de tempo engole o de saída que vem junto
var _burst_frame := -1             # disputa de pênaltis sai inteira num passo: espaça os sons
var _burst_n := 0
var speed := 1.0
var paused := false
var _acc := 0.0
var _hud: Label
var _hints: Label
var _msg: Label
var _font: Font
var _hud_root: Control
var _touch_bar: MatchTouchBar
var _speed_bar: MatchSpeedBar
## "Finalizar agora" (encerra no placar atual) só existe em build de desenvolvimento.
var _dev_end_now := OS.is_debug_build()
## Coordenadas da partida (ORIGIN + pos) -> tela; e escala uniforme dessa transformação.
var _xf := Transform2D.IDENTITY
var _xf_scale := 1.0
var _pitch_rect := Rect2()
var _hud_k := 1.0
## HUD estreito (celular em retrato): placar com siglas e sem a velocidade (a faixa já mostra).
var _hud_narrow := false
var _pitch_tex: Texture2D
var _pitch_tex_scale := 0
var _pitch_skin := PitchSkins.DEFAULT
## Aviso temporário no rodapé (ex.: vinhetas ligadas/desligadas).
var _flash_text := ""
var _flash_left := 0.0

## Modo Replay
var is_replaying := false
var current_replay: Dictionary = {}
var current_replay_frames: Array = []
var replay_frame_idx: int = 0
var _replay_timer: float = 0.0
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label

## Vinhetas e Cutscenes de Lances
var cutscenes_enabled := true
var _cutscenes: CutsceneOverlay
## Lance que para o jogo: a partida espera a vinheta (STOPPAGE_HOLD s) antes de seguir.
const STOPPAGE_HOLD := 1.5
const GOAL_HOLD := 2.5
## Apresentação dos times e cara ou coroa antes do apito (partida do clube). A partida não anda
## enquanto está aberta; a escolha vai para o MatchSetup e o motor é recriado com ela.
var _intro: MatchIntroOverlay
var _intro_active := false
var _setup: MatchSetup
var _settings: Node

## Partida do clube do jogador (Game.pending_match, preparada no Pré-jogo). Sem ela, a partida de
## demonstração de sempre (Rubro × Anil, R para outra).
var career := false
var _summary: MatchSummaryOverlay
var _halftime_pending := false
var _final_shown := false
## "Ver resultado": simula o resto em fatias por quadro (a tela não trava) até o apito final.
var _fast_forward := false
var _names := {}
const FF_BUDGET_USEC := 12000
const CAREER_ACTIONS := ["pause", "critical", "replay", "cutscenes", "finish"]

## Camada Cinestésica (Game Feel — TASK-05)
var _squash: Dictionary = {}
var _ball_squash := Vector2.ONE
var _ball_squash_angle := 0.0
var _ball_squash_time := 0.0
var _shake_intensity := 0.0
var _shake_offset := Vector2.ZERO
var _net_wave := 0.0
var _net_goal_side := 0
var _last_contact_tick := -100


func _ready() -> void:
	_font = DesignTokens.display_font()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED   # papel de fundo repetido
	_settings = get_node_or_null("/root/Settings")
	speed = float(_pref("match_speed", 1.0))
	cutscenes_enabled = bool(_pref("cutscenes", true))
	_build_hud()
	_summary = MatchSummaryOverlay.new()
	_summary.action_pressed.connect(_on_summary_action)
	add_child(_summary)
	_cutscenes = CutsceneOverlay.new()
	add_child(_cutscenes)
	_cutscenes.reduce_motion = bool(_pref("reduce_motion", false))
	_intro = MatchIntroOverlay.new()
	_intro.finished.connect(_on_intro_finished)
	add_child(_intro)
	if _settings:
		_settings.changed.connect(_on_setting_changed)
	get_viewport().size_changed.connect(_layout_hud)
	_layout_hud()
	new_match()


func _pref(key: String, fallback: Variant) -> Variant:
	return _settings.get_value(key) if _settings else fallback


func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"cutscenes":
			cutscenes_enabled = bool(value)
		"reduce_motion":
			_cutscenes.reduce_motion = bool(value)
		"touch_controls", "key_hints", "ui_scale", "aspect":
			_layout_hud.call_deferred()


func _exit_tree() -> void:
	SfxService.stop_ambient(0.6)
	if engine:
		engine.dispose()
		engine = null


func new_match(rng_seed: int = -1) -> void:
	var game := get_node_or_null("/root/Game")
	career = game != null and game.has_pending_match() and not bool(game.pending_match.get("reported", false))
	var setup: MatchSetup
	if career:
		setup = game.pending_match.setup
	else:
		if rng_seed < 0:
			rng_seed = randi()  # a UI pode sortear a semente; o motor em si é determinístico
		var minutes := float(App.ruleset.core_param("match_minutes"))
		setup = DemoData.match_setup(rng_seed, minutes)
	_names.clear()
	for ts: TeamSetup in [setup.home, setup.away]:
		for a: Athlete in ts.lineup + ts.bench:
			_names[a.id] = a.name
	_halftime_pending = false
	_final_shown = false
	_fast_forward = false
	if _summary:
		_summary.close()
	_setup = setup
	_create_engine(setup)
	SfxService.ambient("torcida_ambiente", -4.0)
	_intro_active = career and _intro != null
	if not _intro_active:
		SfxService.play("apito_inicio", 0.0, 0.4)
	var skin := PitchSkins.for_team(engine.ctx.home)
	if skin != _pitch_skin or _pitch_tex == null:
		_pitch_skin = skin
		_pitch_tex = null
		_pitch_tex_scale = 0
		_layout_hud.call_deferred()
	_acc = 0.0
	paused = false
	_stop_replay()
	_touch_bar.set_actions(CAREER_ACTIONS if career else MatchTouchBar.DEMO_ACTIONS)
	if _hints:
		_hints.text = tr("PARTIDA_DICAS_CARREIRA") if career else DEMO_HINTS
		if _dev_end_now:
			_hints.text += "   " + tr("PARTIDA_DICA_ENCERRAR")
	_layout_hud.call_deferred()
	if _intro_active:
		_start_intro.call_deferred()
	elif career and bool(game.pending_match.get("debut", false)):
		_debut_tips.call_deferred()


func _create_engine(setup: MatchSetup) -> void:
	if engine:
		engine.dispose()
	engine = MatchEngine.create(setup, App.registry)
	engine.ctx.bus.on(Hooks.MATCH_EVENT, _on_match_event, "match_view_cutscenes")


func _start_intro() -> void:
	_intro.reduce_motion = bool(_pref("reduce_motion", false))
	_intro.pitch_rotated = not is_zero_approx(_xf.get_rotation())
	_intro.start(_setup.home, _setup.away)


## Sorteio feito: a partida nasce com quem dá a saída e o lado de cada time.
func _on_intro_finished(kickoff_side: String, home_dir: int) -> void:
	_setup.kickoff_side = kickoff_side
	_setup.home_dir = home_dir
	_create_engine(_setup)
	_acc = 0.0
	_intro_active = false
	SfxService.play("apito_inicio", 0.0, 0.1)
	var game := get_node_or_null("/root/Game")
	if career and game and bool(game.pending_match.get("debut", false)):
		_debut_tips.call_deferred()


## A partida espera enquanto a vinheta de um lance que parou o jogo está na tela.
func _holding() -> bool:
	return _intro_active or (_cutscenes != null and _cutscenes.is_active)


func _process(delta: float) -> void:
	if _fast_forward and engine and not engine.is_finished():
		var t0 := Time.get_ticks_usec()
		_quiet = true
		while not engine.is_finished() and Time.get_ticks_usec() - t0 < FF_BUDGET_USEC:
			engine.step()
		_quiet = false
		_flash(tr("PARTIDA_CALCULANDO") % roundi(100.0 * engine.ctx.tick / maxf(engine.total_regular_ticks(), 1.0)), 0.5)
	elif is_replaying:
		_process_replay(delta)
	elif engine and not paused and not engine.is_finished() and not _halftime_pending and not _holding():
		var ticks_per_sec := engine.total_regular_ticks() / REAL_SECONDS_AT_1X
		_acc += delta * ticks_per_sec * speed
		var budget := 2000
		while _acc >= 1.0 and budget > 0 and not engine.is_finished() and not _halftime_pending and not _holding():
			engine.step()
			_acc -= 1.0
			budget -= 1
	if career and engine:
		if engine.is_finished() and not _final_shown:
			_show_final()
		elif _halftime_pending and not _summary.is_open():
			if _cutscenes:
				_cutscenes.dismiss()
			_summary.open(engine.ctx, false, _names)

	_update_game_feel(delta)
	_update_hud()
	queue_redraw()


func _update_game_feel(delta: float) -> void:
	# 1. Screen Shake decrescente (150ms)
	if _shake_intensity > 0.0:
		_shake_intensity = maxf(0.0, _shake_intensity - delta * 30.0)
		_shake_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_intensity
	else:
		_shake_offset = Vector2.ZERO

	# 2. Deformação de rede (onda amortecida)
	if _net_wave > 0.0:
		_net_wave = maxf(0.0, _net_wave - delta * 2.5)

	# 3. Squash de jogadores
	if not _squash.is_empty():
		var expired: Array = []
		for pid in _squash:
			var sq: Dictionary = _squash[pid]
			sq["time_left"] = float(sq.get("time_left", 0.0)) - delta
			if float(sq["time_left"]) <= 0.0:
				expired.append(pid)
			else:
				var t_prog: float = 1.0 - (float(sq["time_left"]) / float(sq.get("duration", 0.1)))
				var curve := sin(t_prog * PI) * float(sq.get("intensity", 0.2))
				sq["current_scale"] = Vector2(1.0 + curve * 0.9, 1.0 - curve * 0.7)
		for pid in expired:
			_squash.erase(pid)

	# 4. Squash da bola
	if _ball_squash_time > 0.0:
		_ball_squash_time -= delta
		var b_factor := sin(clampf(1.0 - _ball_squash_time / 0.1, 0.0, 1.0) * PI) * 0.25
		_ball_squash = Vector2(1.0 + b_factor, 1.0 - b_factor * 0.8)
	else:
		_ball_squash = Vector2.ONE


func _trigger_haptic(duration_ms: int) -> void:
	if DisplayServer.is_headless():
		return
	var haptics_enabled: bool = bool(_pref("vibration", true))
	if haptics_enabled and Input.has_method("vibrate_handheld"):
		Input.vibrate_handheld(duration_ms)


func _trigger_player_squash(player_id: String, angle: float, intensity: float = 0.22, duration: float = 0.1) -> void:
	_squash[player_id] = {
		"angle": angle,
		"intensity": intensity,
		"duration": duration,
		"time_left": duration,
		"current_scale": Vector2.ONE
	}


func _trigger_ball_squash(angle: float, duration: float = 0.1) -> void:
	_ball_squash_angle = angle
	_ball_squash_time = duration


func _trigger_game_feel_impact(type: String, data: Dictionary) -> void:
	match type:
		"shot":
			_trigger_haptic(35)
			if engine and engine.ctx:
				var b := engine.ctx.ball
				var angle := b.vel.angle() if b.vel.length_squared() > 0.01 else 0.0
				_trigger_ball_squash(angle)
				if b.last_kicker:
					_trigger_player_squash(b.last_kicker.id, angle, 0.22)
		"goal":
			_trigger_haptic(70)
			_shake_intensity = 6.0
			_net_wave = 1.0
			if engine and engine.ctx:
				_net_goal_side = -1 if engine.ctx.ball.pos.x < Pitch.W / 2.0 else 1
		"save":
			_trigger_haptic(35)
			_shake_intensity = 3.5
			if engine and engine.ctx:
				_trigger_ball_squash(engine.ctx.ball.vel.angle())
		"block":
			_trigger_haptic(35)
			_shake_intensity = 3.0
			if engine and engine.ctx:
				_trigger_ball_squash(engine.ctx.ball.vel.angle())
		"woodwork":
			_trigger_haptic(70)
			_shake_intensity = 5.5
		"pass":
			_trigger_haptic(15)



func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	if _intro_active:
		return
	if is_replaying:
		if event.keycode in [KEY_SPACE, KEY_C, KEY_P]:
			_stop_replay()
			return
	# Esc fica com o Router (voltar), que pergunta a handle_back() antes de sair.
	if _summary and _summary.is_open():
		return

	match event.keycode:
		KEY_SPACE: _do_action("pause")
		KEY_9: _set_speed(0.25)
		KEY_0: _set_speed(0.5)
		KEY_1: _set_speed(1)
		KEY_2: _set_speed(2)
		KEY_3: _set_speed(3)
		KEY_4: _set_speed(4)
		KEY_5: _set_speed(5)
		KEY_E: _do_action("end_now")
		KEY_C: _do_action("critical")
		KEY_P: _do_action("replay")
		KEY_T: _do_action("tactics")
		KEY_V: _do_action("cutscenes")
		KEY_S: _do_action("sandbox")
		KEY_R: _do_action("new")
		KEY_F: _do_action("finish")


## Comandos comuns a teclado e barra de toque.
func _do_action(id: String) -> void:
	if _intro_active:
		return
	# Na partida do clube não se troca de partida nem de tática no meio (o resultado é um só).
	if career and id in ["tactics", "sandbox", "new"]:
		return
	if not career and id == "finish":
		return
	if id == "end_now" and not _dev_end_now:
		return
	match id:
		"pause":
			if is_replaying:
				_stop_replay()
			else:
				paused = not paused
		"speed":
			_set_speed(SPEEDS[(SPEEDS.find(speed) + 1) % SPEEDS.size()])
		"end_now":
			_end_now()
		"critical":
			if is_replaying:
				_stop_replay()
			_critical_skip()
		"replay":
			if is_replaying:
				_stop_replay()
			else:
				_play_last_replay()
		"tactics":
			var router := get_node_or_null("/root/Router")
			if router:
				router.go("lineup")
			else:
				get_tree().change_scene_to_file("res://presentation/tactics/tactics_view.tscn")
		"finish":
			_start_fast_forward()
		"cutscenes":
			cutscenes_enabled = not cutscenes_enabled
			if _settings:
				_settings.set_value("cutscenes", cutscenes_enabled)
			_flash("Vinhetas de lances: %s" % ("ligadas" if cutscenes_enabled else "desligadas"))
		"sandbox":
			get_tree().change_scene_to_file("res://presentation/match_view/match_sandbox_view.tscn")
		"new":
			new_match()


func _on_match_event(payload: Dictionary) -> void:
	var ev: Dictionary = payload.get("event", {})
	if not _quiet:
		_event_sound(ev)
		_trigger_game_feel_impact(str(ev.get("type", "")), ev.get("data", {}))
	if career and not _fast_forward and str(ev.get("type", "")) == "period_end" \
			and str(ev.get("data", {}).get("period", "")) == "1T":
		_halftime_pending = true
	if _fast_forward or not cutscenes_enabled or _cutscenes == null:
		return
	var type: String = ev.get("type", "")
	var data: Dictionary = ev.get("data", {})
	var msg: String = engine.ctx.message if engine and engine.ctx else ""

	var len_factor: float = _settings.settings.cutscene_length_factor() if _settings else 1.0
	_cutscenes.duration_scale = len_factor

	match type:
		"goal":
			_cutscenes.play_event("goal", "G O O O L ! ! !", msg, GOAL_HOLD)
		"save":
			_cutscenes.play_event("save", "DEFESA ESPETACULAR!", msg, STOPPAGE_HOLD)
		"foul":
			var card: String = str(data.get("card", ""))
			if card == "red":
				_cutscenes.play_event("foul_red", "CARTÃO VERMELHO! EXPULSÃO!", msg, STOPPAGE_HOLD)
			elif card == "yellow":
				_cutscenes.play_event("foul_yellow", "FALTA GRAVE · CARTÃO AMARELO", msg, STOPPAGE_HOLD)
			elif bool(data.get("in_box", false)):
				_cutscenes.play_event("penalty", "PÊNALTI MARCADO!", msg, STOPPAGE_HOLD)
			else:
				_cutscenes.play_event("foul_simple", "FALTA MARCADA", msg, STOPPAGE_HOLD)
		"offside":
			_cutscenes.play_event("offside", "IMPEDIMENTO!", msg, STOPPAGE_HOLD)
		"substitution":
			_cutscenes.play_event("substitution", "SUBSTITUIÇÃO DE JOGADOR", msg, STOPPAGE_HOLD)
		"period_end":
			_cutscenes.play_event("period_end", "FIM DE TEMPO", msg, STOPPAGE_HOLD)
		"restart":
			var kind: String = str(data.get("kind", ""))
			match kind:
				"throw_in":
					_cutscenes.play_event("throw_in", "ARREMESSO LATERAL", msg, STOPPAGE_HOLD)
				"corner":
					_cutscenes.play_event("corner", "COBRANÇA DE ESCANTEIO", msg, STOPPAGE_HOLD)
				"goal_kick":
					_cutscenes.play_event("goal_kick", "TIRO DE META", msg, STOPPAGE_HOLD)
				"penalty":
					_cutscenes.play_event("penalty_kick", "COBRANÇA DE PÊNALTI", msg, STOPPAGE_HOLD)


## Efeito sonoro de cada lance (assets/audio/sfx/, compostos em tools/strudel/efeitos.strudel.js).
func _event_sound(ev: Dictionary) -> void:
	var data: Dictionary = ev.get("data", {})
	var now := Time.get_ticks_msec() / 1000.0
	match str(ev.get("type", "")):
		"goal":
			SfxService.play("gol")
		"save":
			SfxService.play("defesa")
		"shot":
			SfxService.play("chute" if bool(data.get("on_target", false)) else "chute_fora")
		"block":
			SfxService.play("bloqueio")
		"foul":
			var card := str(data.get("card", ""))
			if card == "red":
				SfxService.play("cartao_vermelho")
			elif card == "yellow":
				SfxService.play("cartao_amarelo")
			elif bool(data.get("in_box", false)):
				SfxService.play("penalti")
			else:
				SfxService.play("apito_falta")
		"offside":
			SfxService.play("impedimento")
		"substitution":
			SfxService.play("substituicao")
		"extra_time":
			SfxService.play("prorrogacao")
		"period_end":
			_period_end_at = now
			_period_whistle.call_deferred()
		"penalty_kick":
			var frame := Engine.get_process_frames()
			if frame != _burst_frame:
				_burst_frame = frame
				_burst_n = 0
			SfxService.play("penalti_gol" if bool(data.get("scored", false)) else "penalti_perdido", 0.0, 1.8 * _burst_n)
			_burst_n += 1
		"restart":
			match str(data.get("kind", "")):
				"kickoff":
					if now - _period_end_at > 1.5:
						SfxService.play("apito_inicio")
				"corner":
					SfxService.play("escanteio")


## Depois do passo do motor já se sabe se o tempo que acabou foi o último.
func _period_whistle() -> void:
	if engine and engine.is_finished():
		SfxService.play("apito_final")
		SfxService.stop_ambient(5.0)
	else:
		SfxService.play("apito_intervalo")


func _critical_skip() -> void:
	if engine == null or engine.is_finished():
		return
	_quiet = true
	var ev := engine.run_until_event(CRITICAL_EVENTS)
	_quiet = false
	if not ev.is_empty():
		_event_sound(ev)
	if not ev.is_empty() and bool(_pref("auto_replay", true)):
		# Dispara replay do lance que acabou de ser encontrado
		_play_last_replay()


func _play_last_replay() -> void:
	if engine == null:
		return
	var last_rep: Variant = App.registry.bus.decide("replays.last_replay", {"ctx": engine.ctx})
	if last_rep is Dictionary and not (last_rep as Dictionary).is_empty():
		_start_replay(last_rep)


func _start_replay(replay_dict: Dictionary) -> void:
	var frames: Array = replay_dict.get("frames", [])
	if frames.is_empty():
		return
	current_replay = replay_dict
	current_replay_frames = frames
	replay_frame_idx = 0
	_replay_timer = 0.0
	is_replaying = true
	_banner_title.text = "● REPLAY · %s" % str(replay_dict.get("title", "LANCE CRÍTICO"))
	_banner_sub.text = str(replay_dict.get("description", ""))
	_banner.visible = true


func _stop_replay() -> void:
	is_replaying = false
	current_replay = {}
	current_replay_frames.clear()
	replay_frame_idx = 0
	_replay_timer = 0.0
	if _banner:
		_banner.visible = false


func _process_replay(delta: float) -> void:
	if current_replay_frames.is_empty():
		_stop_replay()
		return

	# Câmera lenta dramática no terço final do replay (momento do impacto)
	var total := current_replay_frames.size()
	var is_climax := replay_frame_idx > int(total * 0.75) and not bool(_pref("reduce_motion", false))
	var frame_dur := 0.045 if is_climax else 0.022 # ~22 fps acelerando para slow-motion 45ms

	_replay_timer += delta
	while _replay_timer >= frame_dur and is_replaying:
		_replay_timer -= frame_dur
		replay_frame_idx += 1
		if replay_frame_idx >= total:
			_stop_replay()
			break


# ------------------------------------------------------------------ partida do clube (carreira)
## "Ver resultado": o resto da partida é simulado sem vinhetas nem sons, em fatias por quadro.
## Velocidade escolhida (botões, teclas 1-5): vale já e fica lembrada nas opções.
func _set_speed(value: float) -> void:
	if not SPEEDS.has(value):
		return
	speed = value
	if _speed_bar:
		_speed_bar.set_speed(value)
	if _settings and not is_equal_approx(float(_pref("match_speed", 1.0)), value):
		_settings.set_value("match_speed", value)


## Desenvolvimento: encerra a partida no ato, no placar atual, sem simular o resto. Na partida do
## clube vai direto ao Resultado (registra como qualquer partida, com extra.ended_early).
func _end_now() -> void:
	if engine == null or engine.is_finished():
		return
	if is_replaying:
		_stop_replay()
	if _cutscenes:
		_cutscenes.dismiss()
	_summary.close()
	_fast_forward = false
	_halftime_pending = false
	paused = false
	engine.end_now()
	_period_whistle()
	_flash(tr("PARTIDA_ENCERRADA"), 2.0)
	if career:
		_final_shown = true
		_go_result()


func _start_fast_forward() -> void:
	if engine == null or engine.is_finished():
		return
	if is_replaying:
		_stop_replay()
	_halftime_pending = false
	_summary.close()
	if _cutscenes:
		_cutscenes.dismiss()
	_fast_forward = true
	paused = false


func _show_final() -> void:
	_final_shown = true
	_fast_forward = false
	_halftime_pending = false
	if _cutscenes:
		_cutscenes.dismiss()
	_summary.open(engine.ctx, true, _names)


func _on_summary_action() -> void:
	if engine and engine.is_finished():
		_go_result()
		return
	_halftime_pending = false
	_summary.close()
	paused = false


## Registra a partida (uma vez) e abre o Resultado.
func _go_result() -> void:
	var game := get_node_or_null("/root/Game")
	if game:
		game.finish_match(engine.result)
	var router := get_node_or_null("/root/Router")
	if router:
		router.go("result")


## Voltar (Esc, botão do Android) durante a partida: o Router pergunta aqui antes de sair.
## true = tratado aqui (replay fecha; partida do clube pede confirmação).
func handle_back() -> bool:
	if is_replaying:
		_stop_replay()
		return true
	if not career:
		return false
	if _summary.is_open() or _fast_forward:
		return true
	var router := get_node_or_null("/root/Router")
	if router == null:
		return false
	var was_paused := paused
	paused = true
	var official: bool = engine.ctx.setup.kind == "official"
	var actions: Array = [
		{"label": tr("PARTIDA_CONTINUAR_ASSISTINDO"), "kind": "secondary", "cancel": true,
			"callback": func() -> void: paused = was_paused},
		{"label": tr("PARTIDA_VER_RESULTADO"), "kind": "primary", "callback": _start_fast_forward},
	]
	if not official:
		actions.append({"label": tr("PARTIDA_ABANDONAR"), "kind": "destructive", "callback": func() -> void:
			var game := get_node_or_null("/root/Game")
			if game:
				game.discard_pending_match()
			router.go("home")})
	router.overlays.modal(tr("PARTIDA_SAIR_TITULO"),
		tr("PARTIDA_SAIR_OFICIAL") if official else tr("PARTIDA_SAIR_AMISTOSO"), actions)
	return true


## Estreia (O04): duas dicas, velocidade e próximo lance, com a partida parada até o fim delas.
func _debut_tips() -> void:
	var router := get_node_or_null("/root/Router")
	if router == null:
		return
	paused = true
	var speed_target: Control = _speed_bar.speed_button(speed) if _speed_bar.visible else _hints
	var skip_target: Control = _touch_bar.button("critical") if _touch_bar.visible else _hints
	router.overlays.coach([
		{"target": speed_target, "title": tr("ESTREIA_DICA_VEL_TITULO"), "text": tr("ESTREIA_DICA_VEL_TEXTO")},
		{"target": skip_target, "title": tr("ESTREIA_DICA_LANCE_TITULO"), "text": tr("ESTREIA_DICA_LANCE_TEXTO")},
	], func(_skipped: bool) -> void: paused = false)


# ------------------------------------------------------------------ HUD
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# Tudo do HUD vive em `_hud_root`, ampliado por Settings.readability_scale() em telas que
	# encolhem o layout (celular); dentro dele as medidas são lógicas e ancoradas às bordas.
	_hud_root = Control.new()
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud_root)

	_hud = Label.new()
	_hud.position = Vector2(16, 10)
	_hud.add_theme_font_size_override("font_size", UiKit.FONT_H2)
	_hud.add_theme_font_override("font", DesignTokens.display_font())
	_hud.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	_hud.clip_text = true
	_hud.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hud_root.add_child(_hud)

	_hints = Label.new()
	_hints.position = Vector2(16, 36)
	_hints.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	_hints.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
	_hints.text = DEMO_HINTS
	_hints.clip_text = true
	_hints.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hud_root.add_child(_hints)

	_msg = Label.new()
	_msg.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
	_msg.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	_msg.clip_text = true
	_msg.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hud_root.add_child(_msg)

	_touch_bar = MatchTouchBar.new()
	_touch_bar.action.connect(_do_action)
	_hud_root.add_child(_touch_bar)

	_speed_bar = MatchSpeedBar.new(SPEEDS, _dev_end_now)
	_speed_bar.speed_picked.connect(_set_speed)
	_speed_bar.end_now_pressed.connect(func() -> void: _do_action("end_now"))
	_hud_root.add_child(_speed_bar)
	_speed_bar.set_speed(speed)

	# Banner de Replay
	_banner = PanelContainer.new()
	_banner.custom_minimum_size = Vector2(0, 50)
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(0.08, 0.1, 0.16, 0.92)
	b_style.border_color = Color("#ff4757")
	b_style.border_width_left = 3
	b_style.border_width_top = 1
	b_style.border_width_right = 1
	b_style.border_width_bottom = 3
	b_style.corner_radius_top_left = 8
	b_style.corner_radius_top_right = 8
	b_style.corner_radius_bottom_left = 8
	b_style.corner_radius_bottom_right = 8
	b_style.content_margin_left = 14
	b_style.content_margin_right = 14
	b_style.content_margin_top = 6
	b_style.content_margin_bottom = 6
	_banner.add_theme_stylebox_override("panel", b_style)
	_banner.visible = false
	_hud_root.add_child(_banner)

	var b_vbox := VBoxContainer.new()
	_banner.add_child(b_vbox)

	_banner_title = Label.new()
	_banner_title.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	_banner_title.add_theme_font_override("font", DesignTokens.display_font())
	_banner_title.add_theme_color_override("font_color", Color("#ff4757"))
	_banner_title.clip_text = true
	b_vbox.add_child(_banner_title)

	_banner_sub = Label.new()
	_banner_sub.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	_banner_sub.add_theme_color_override("font_color", Color("#cbd5e1"))
	_banner_sub.clip_text = true
	b_vbox.add_child(_banner_sub)


## Reposiciona o HUD e recalcula onde o campo cabe. Chamado no início e a cada mudança de tamanho.
func _layout_hud() -> void:
	if _hud_root == null:
		return
	var vp := get_viewport_rect().size
	var safe: Vector4 = _settings.safe_margins() if _settings else Vector4.ZERO
	_hud_k = _settings.readability_scale() if _settings else 1.0
	var k := _hud_k
	# Área do HUD em unidades lógicas dele (vp / k), já sem as margens seguras.
	var w := (vp.x - safe.x - safe.z) / k
	var h := (vp.y - safe.y - safe.w) / k
	_hud_root.position = Vector2(safe.x, safe.y)
	_hud_root.scale = Vector2(k, k)
	_hud_root.size = Vector2(w, h)

	var show_bar: bool = _settings.touch_controls_visible() if _settings else false
	var show_hints: bool = _settings.key_hints_visible() if _settings else true
	_touch_bar.visible = show_bar
	_hints.visible = show_hints
	var bar_h := 0.0
	if show_bar:
		_touch_bar.set_width(w)
		bar_h = _touch_bar.bar_height()
		_touch_bar.position = Vector2(0, h - bar_h)
		_touch_bar.size = Vector2(w, bar_h)
	# Faixa de velocidade logo acima da barra de toque (ou no rodapé, sem ela).
	var speed_h := _speed_bar.bar_height()
	_speed_bar.set_width(w)
	_speed_bar.position = Vector2(0, h - bar_h - speed_h)
	_speed_bar.size = Vector2(w, speed_h)
	bar_h += speed_h
	# Com a barra visível ela já tem o botão de opções: o flutuante sai e não cobre o placar.
	if show_bar and not is_in_group("settings_button_host"):
		add_to_group("settings_button_host")
	elif not show_bar and is_in_group("settings_button_host"):
		remove_from_group("settings_button_host")

	var right_room := 16.0 if show_bar else 72.0   # espaço do botão flutuante de opções
	_hud_narrow = w < MatchSpeedBar.NARROW
	_hud.size = Vector2(maxf(w - 16.0 - right_room, 0.0), 0)
	_hints.size = Vector2(maxf(w - 16.0 - right_room, 0.0), 18)
	_msg.position = Vector2(16, h - bar_h - HUD_MSG_H)
	_msg.size = Vector2(maxf(w - 32.0, 0.0), 24)
	var banner_w := minf(500.0, w - 32.0)
	_banner.custom_minimum_size.x = banner_w
	_banner.size = Vector2(banner_w, 50)
	_banner.position = Vector2((w - banner_w) / 2.0, HUD_TOP + 4.0)

	var top := (HUD_TOP if show_hints else HUD_TOP - 18.0) * k + safe.y
	var bottom := (bar_h + HUD_MSG_H + 6.0) * k + safe.w
	_fit_pitch(Rect2(safe.x + 8.0, top, vp.x - safe.x - safe.z - 16.0, vp.y - top - bottom))
	queue_redraw()


## Calcula `_xf` para o gramado (com gols e folga) caber em `area`, girando 90° se ganhar >15%.
func _fit_pitch(area: Rect2) -> void:
	var pad_x := Pitch.GOAL_DEPTH + PITCH_PAD
	var pad_y := PITCH_PAD
	if _has_pitch_texture():
		pad_x = maxf(pad_x, PITCH_TEXTURE_BLEED)
		pad_y = maxf(pad_y, PITCH_TEXTURE_BLEED)
	var world := Vector2(Pitch.W + 2.0 * pad_x, Pitch.H + 2.0 * pad_y)
	area.size = area.size.max(Vector2(40, 40))
	var s_land := minf(area.size.x / world.x, area.size.y / world.y)
	var s_port := minf(area.size.x / world.y, area.size.y / world.x)
	var rotate := s_port > s_land * 1.15
	_xf_scale = s_port if rotate else s_land
	var center := area.get_center()
	_xf = Transform2D(PI / 2.0 if rotate else 0.0, Vector2(_xf_scale, _xf_scale), 0.0, center) \
		* Transform2D(0.0, -(ORIGIN + Pitch.center()))
	var half := (Vector2(world.y, world.x) if rotate else world) * _xf_scale / 2.0
	_pitch_rect = Rect2(center - half, half * 2.0)
	_pick_pitch_texture(world.x * _xf_scale)


func _has_pitch_texture() -> bool:
	return PitchSkins.is_valid(_pitch_skin)


## @2x até ~2000 px reais de largura do campo; @4x só em telas grandes (4K, ultrawide), que
## aguentam os ~40 MB de memória de vídeo da versão cheia.
func _pick_pitch_texture(world_w_logical: float) -> void:
	if not _has_pitch_texture():
		return
	var px := world_w_logical * get_viewport().get_final_transform().get_scale().x
	var want := 4 if px > 2100.0 and ResourceLoader.exists(PitchSkins.texture_path(_pitch_skin, 4)) else 2
	if want != _pitch_tex_scale:
		_pitch_tex = load(PitchSkins.texture_path(_pitch_skin, want))
		_pitch_tex_scale = want


static func _team_tag(t: MatchTeam) -> String:
	return t.setup.short_name if t.setup and t.setup.short_name != "" else t.name


func _flash(text: String, seconds: float = 2.0) -> void:
	_flash_text = text
	_flash_left = seconds


func _update_hud() -> void:
	if engine == null:
		return
	_flash_left -= get_process_delta_time()
	var c := engine.ctx
	var secs := int(c.clock_seconds())
	var status := "FIM" if c.finished else c.period_id()
	if is_replaying:
		status = "● REPLAY"
	elif paused:
		status += " (pausado)"
	if _hud_narrow:
		_hud.text = "%s %d x %d %s   %02d:%02d %s" % [_team_tag(c.home), c.home.stats.goals,
			c.away.stats.goals, _team_tag(c.away), secs / 60, secs % 60, status]
	else:
		_hud.text = "%s  %d x %d  %s     %02d:%02d  %s     %dx" % [
			c.home.name, c.home.stats.goals, c.away.stats.goals, c.away.name, secs / 60, secs % 60, status, speed]
	var extra := ""
	if c.result_extra.has("shootout"):
		var so: Dictionary = c.result_extra.shootout
		extra = "   Pênaltis: %d x %d" % [so.home, so.away]
	_msg.text = _flash_text if _flash_left > 0.0 else c.message + extra
	if _touch_bar.visible:
		_touch_bar.update_state(paused, speed, cutscenes_enabled, is_replaying)
	_speed_bar.set_end_enabled(not c.finished)


# ------------------------------------------------------------------ desenho
# O gramado é desenhado sob `_xf` (pode estar girado); jogadores e bola são desenhados em
# coordenadas de tela (`_to_screen`) para os números ficarem sempre de pé.
func _draw() -> void:
	var paper := UiFrames.piece("ui_papel")
	if paper:
		draw_texture_rect(paper, Rect2(Vector2.ZERO, get_viewport_rect().size), true)
	else:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), DesignTokens.COLOR_BG_APP)
	draw_set_transform_matrix(_xf.translated(_shake_offset))
	_draw_pitch()
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if engine == null:
		return

	if is_replaying and not current_replay_frames.is_empty():
		_draw_replay_frame()
	else:
		var c := engine.ctx
		for p: MatchPlayer in c.all_players:
			_draw_player(p, c.ball.holder == p)
		_draw_ball(c.ball)


func _to_screen(pos: Vector2) -> Vector2:
	return _xf * (ORIGIN + pos)


func _draw_replay_frame() -> void:
	var idx := clampi(replay_frame_idx, 0, current_replay_frames.size() - 1)
	var f: Dictionary = current_replay_frames[idx]
	var home := engine.ctx.home
	var away := engine.ctx.away

	# Jogadores mandantes
	for p_info in f.get("home_players", []):
		var pos: Vector2 = p_info.get("pos", Vector2.ZERO)
		var num: int = int(p_info.get("number", 0))
		_draw_piece(_to_screen(pos), home, num, num == 1)

	# Jogadores visitantes
	for p_info in f.get("away_players", []):
		var pos: Vector2 = p_info.get("pos", Vector2.ZERO)
		var num: int = int(p_info.get("number", 0))
		_draw_piece(_to_screen(pos), away, num, num == 1)

	# Bola
	var ball_pos: Vector2 = f.get("ball_pos", Vector2.ZERO)
	var at := _to_screen(ball_pos)
	var br := BALL_R * _xf_scale
	draw_circle(at + Vector2(2, 2.5) * _xf_scale, br, Color(0, 0, 0, 0.4))
	draw_circle(at, br, Color.WHITE)
	draw_arc(at, br, 0, TAU, 16, Color("#ff4757"), 1.4 * _xf_scale)

	# Barra de progresso do replay (sempre horizontal, logo abaixo do campo)
	var bar_y := _pitch_rect.end.y + 4.0
	draw_rect(Rect2(_pitch_rect.position.x, bar_y, _pitch_rect.size.x, 3.0), Color(0.2, 0.2, 0.3, 0.5))
	var progress := float(idx + 1) / float(current_replay_frames.size())
	draw_rect(Rect2(_pitch_rect.position.x, bar_y, _pitch_rect.size.x * progress, 3.0), Color("#ff4757"))


## Peça de futebol de botão: sombra na mesa, textura do estilo do time tingida com a cor dele
## (goleiro em laranja) e o número por cima, branco com contorno para ler em qualquer cor.
func _draw_piece(at: Vector2, team: MatchTeam, num: int, is_gk: bool) -> void:
	var k := _xf_scale
	var r := (GK_PIECE_R if is_gk else PIECE_R) * k
	var tint := GK_TINT if is_gk else team.color
	draw_circle(at + Vector2(1.5, 3.0) * k, r * 1.02, Color(0, 0, 0, 0.35))
	if not ButtonPieces.draw(self, ButtonPieces.style_for(team), at, r, tint):
		draw_circle(at, r, tint)
		draw_arc(at, r, 0, TAU, 24, Color.BLACK if is_gk else Color.WHITE, 1.6 * k)
	if team.side == "away" and bool(_pref("team_markers", false)):
		# Acessibilidade: anel externo extra identifica o visitante sem depender da cor.
		draw_arc(at, r + 2.2 * k, 0, TAU, 32, Color(0.05, 0.07, 0.12), 1.4 * k)
		draw_arc(at, r + 3.6 * k, 0, TAU, 32, Color.WHITE, 1.4 * k)
	var txt := str(num)
	var size := maxi(int(round(r * 0.95)), 8)
	var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := at + Vector2(-w / 2.0, size * 0.36)
	draw_string_outline(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(int(size * 0.28), 2), Color(0, 0, 0, 0.85))
	draw_string(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)


func _draw_pitch() -> void:
	if _pitch_tex:
		var bleed := Vector2(PITCH_TEXTURE_BLEED, PITCH_TEXTURE_BLEED)
		draw_texture_rect(_pitch_tex, Rect2(ORIGIN - bleed, Vector2(Pitch.W, Pitch.H) + bleed * 2.0), false)
		if PitchSkins.has_lines(_pitch_skin):
			_draw_goals(2.0)
			return
	else:
		_draw_stripes()
	_draw_lines()


func _draw_stripes() -> void:
	var stripes := 14
	var sw := Pitch.W / stripes
	for i in stripes:
		draw_rect(Rect2(ORIGIN + Vector2(i * sw, 0), Vector2(sw, Pitch.H)), Color("#116832") if i % 2 == 0 else Color("#0d5c2b"))


func _draw_lines() -> void:
	var white := Color.WHITE
	var lw := 2.0
	draw_rect(Rect2(ORIGIN, Vector2(Pitch.W, Pitch.H)), white, false, lw)
	var c := ORIGIN + Pitch.center()
	draw_line(ORIGIN + Vector2(Pitch.W / 2, 0), ORIGIN + Vector2(Pitch.W / 2, Pitch.H), white, lw)
	draw_arc(c, Pitch.CENTER_CIRCLE_R, 0, TAU, 64, white, lw)
	draw_circle(c, 3.5, white)
	var pb_y := (Pitch.H - Pitch.PENALTY_BOX_H) / 2
	var ga_y := (Pitch.H - Pitch.GOAL_AREA_H) / 2
	draw_rect(Rect2(ORIGIN + Vector2(0, pb_y), Vector2(Pitch.PENALTY_BOX_W, Pitch.PENALTY_BOX_H)), white, false, lw)
	draw_rect(Rect2(ORIGIN + Vector2(Pitch.W - Pitch.PENALTY_BOX_W, pb_y), Vector2(Pitch.PENALTY_BOX_W, Pitch.PENALTY_BOX_H)), white, false, lw)
	draw_rect(Rect2(ORIGIN + Vector2(0, ga_y), Vector2(Pitch.GOAL_AREA_W, Pitch.GOAL_AREA_H)), white, false, lw)
	draw_rect(Rect2(ORIGIN + Vector2(Pitch.W - Pitch.GOAL_AREA_W, ga_y), Vector2(Pitch.GOAL_AREA_W, Pitch.GOAL_AREA_H)), white, false, lw)
	for sx in [Pitch.PENALTY_SPOT_X, Pitch.W - Pitch.PENALTY_SPOT_X]:
		draw_circle(ORIGIN + Vector2(sx, Pitch.H / 2), 3.0, white)
	draw_arc(ORIGIN + Vector2(Pitch.PENALTY_SPOT_X, Pitch.H / 2), 60, -0.65, 0.65, 24, white, lw)
	draw_arc(ORIGIN + Vector2(Pitch.W - Pitch.PENALTY_SPOT_X, Pitch.H / 2), 60, PI - 0.65, PI + 0.65, 24, white, lw)
	_draw_goals(lw)


func _draw_goals(lw: float) -> void:
	var gt := Pitch.goal_top()
	var net_lines := 5
	for gx in [-Pitch.GOAL_DEPTH, Pitch.W]:
		var is_left := gx < 0
		var r := Rect2(ORIGIN + Vector2(gx, gt), Vector2(Pitch.GOAL_DEPTH, Pitch.GOAL_H))
		draw_rect(r, Color(1, 1, 1, 0.15))

		# Malha e deformação elástica da rede no gol
		var deform := 0.0
		if _net_wave > 0.0 and ((is_left and _net_goal_side == -1) or (not is_left and _net_goal_side == 1)):
			deform = sin(_net_wave * PI * 3.0) * _net_wave * 5.0 * (-1.0 if is_left else 1.0)

		var net_col := Color(1, 1, 1, 0.3)
		for i in range(1, net_lines):
			var frac := float(i) / float(net_lines)
			var y_line := gt + Pitch.GOAL_H * frac
			var x_start := ORIGIN.x + (gx if is_left else Pitch.W)
			var x_end := ORIGIN.x + (0.0 if is_left else (Pitch.W + Pitch.GOAL_DEPTH))
			draw_line(Vector2(x_start + deform * (1.0 - frac), ORIGIN.y + y_line), Vector2(x_end, ORIGIN.y + y_line), net_col, 1.0)

		draw_rect(r, Color.WHITE, false, lw)


func _draw_player(p: MatchPlayer, has_ball: bool) -> void:
	var at := _to_screen(p.pos)
	var r := (GK_PIECE_R if p.is_gk() else PIECE_R) * _xf_scale
	if has_ball:
		draw_circle(at, r + 4.5 * _xf_scale, Color(0.98, 0.75, 0.14, 0.35))
		draw_arc(at, r + 4.5 * _xf_scale, 0, TAU, 32, Color("#fbbf24"), 2.2 * _xf_scale)

	if _squash.has(p.id):
		var sq: Dictionary = _squash[p.id]
		var angle: float = float(sq.get("angle", 0.0))
		var scale: Vector2 = sq.get("current_scale", Vector2.ONE)
		draw_set_transform(at, angle, scale)
		_draw_piece(Vector2.ZERO, p.team, p.shirt, p.is_gk())
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		_draw_piece(at, p.team, p.shirt, p.is_gk())


func _draw_ball(b: MatchBall) -> void:
	var at := _to_screen(b.pos)
	var r := BALL_R * _xf_scale
	draw_circle(at + Vector2(2, 2.5) * _xf_scale, r, Color(0, 0, 0, 0.35))
	if _ball_squash != Vector2.ONE:
		draw_set_transform(at, _ball_squash_angle, _ball_squash)
		draw_circle(Vector2.ZERO, r, Color.WHITE)
		draw_arc(Vector2.ZERO, r, 0, TAU, 16, Color("#0f172a"), 1.2 * _xf_scale)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(at, r, Color.WHITE)
		draw_arc(at, r, 0, TAU, 16, Color("#0f172a"), 1.2 * _xf_scale)
