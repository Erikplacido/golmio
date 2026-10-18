extends Mechanic
## Sistema de Replays e Câmera de Lances Críticos (GDD seção 4).
## Mantém buffer circular contínuo de 300–500 frames com posições da bola e dos 22 atletas.
## Captura automaticamente:
##   - Gols (construção da jogada até a rede)
##   - Defesas Milagrosas (chutes com xG elevado ou defesas difíceis)
##   - Faltas Graves e Pênaltis (cartões e lances capitais)
## Oferece hooks para visualizadores (match_view) e emite notificação quando um replay está pronto.

const HOOK_LAST_REPLAY := "replays.last_replay"
const HOOK_GET_REPLAYS := "replays.get_replays"
const HOOK_REPLAY_READY := "replays.replay_ready"


func _init() -> void:
	id = "replays"
	title = "Sistema de Replays"
	description = "Buffer circular de lances críticos e replay em câmera lenta de gols, defesas e faltas (GDD 4)."
	version = 1
	data_version = 1
	layer = "presentation"
	stage = "experimental"
	depends_on = []
	conflicts_with = []
	enabled_by_default = false
	default_params = {
		"buffer_capacity": 450,       # Capacidade do buffer circular de frames
		"clip_frames": 180,           # Janela gravada no replay (~3.6 a 5 segundos de jogo)
		"xg_miracle_threshold": 0.30, # xG mínimo em finalizações salvas para qualificar defesa milagrosa
	}
	provides_hooks = {
		HOOK_LAST_REPLAY: "decide {ctx} -> Dictionary (último clipe de replay gravado ou null)",
		HOOK_GET_REPLAYS: "decide {ctx} -> Array (todos os clipes de replay da partida)",
		HOOK_REPLAY_READY: "emit {ctx, replay: Dictionary} — novo clipe gravado pronto para reprodução",
	}


func setup_match(ctx: MatchContext) -> void:
	ctx.bus.on(Hooks.MATCH_TICK, _on_tick, id)
	ctx.bus.on(Hooks.MATCH_EVENT, _on_event, id)
	ctx.bus.on(HOOK_LAST_REPLAY, _on_last_replay, id)
	ctx.bus.on(HOOK_GET_REPLAYS, _on_get_replays, id)

	var state := ctx.state_for(id)
	state["buffer"] = []
	state["buffer_index"] = 0
	state["replays"] = []
	state["last_replay"] = null


func _on_tick(payload: Dictionary) -> void:
	var ctx: MatchContext = payload.ctx
	var state := ctx.state_for(id)
	var cap: int = int(param("buffer_capacity", 450))
	var buf: Array = state["buffer"]

	var frame := {
		"tick": ctx.tick,
		"ball_pos": ctx.ball.pos,
		"ball_vel": ctx.ball.vel,
		"home_score": ctx.home.stats.goals,
		"away_score": ctx.away.stats.goals,
		"home_players": [],
		"away_players": [],
	}

	for p in ctx.home.players:
		frame.home_players.append({
			"id": p.athlete.id,
			"pos": p.pos,
			"number": p.shirt,
		})
	for p in ctx.away.players:
		frame.away_players.append({
			"id": p.athlete.id,
			"pos": p.pos,
			"number": p.shirt,
		})

	if buf.size() < cap:
		buf.append(frame)
	else:
		var idx: int = int(state.get("buffer_index", 0))
		buf[idx] = frame
		state["buffer_index"] = (idx + 1) % cap


func _on_event(payload: Dictionary) -> void:
	var ev: Dictionary = payload.event
	var type: String = str(ev.get("type", ""))
	var ctx: MatchContext = payload.ctx
	var state := ctx.state_for(id)

	var is_critical := false
	var category := ""
	var title := ""

	match type:
		"goal":
			is_critical = true
			category = "goal"
			var scorer := ctx.find_player(str(ev.get("athlete_id", "")))
			var name := scorer.display_name() if scorer else "Gol"
			title = "GOL! %s" % name

		"save":
			var xg: float = float(ev.get("data", {}).get("xg", 0.0))
			var miracle_limit: float = float(param("xg_miracle_threshold", 0.30))
			if xg >= miracle_limit or ev.get("data", {}).get("miracle", false):
				is_critical = true
				category = "miracle_save"
				title = "DEFESA ESPETACULAR! (xG %.2f)" % xg
			else:
				is_critical = true
				category = "save"
				title = "DEFESA DO GOLEIRO!"

		"foul":
			is_critical = true
			category = "foul"
			var card: String = str(ev.get("card", ""))
			if card == "red":
				title = "CARTÃO VERMELHO! EXPULSÃO!"
			elif card == "yellow":
				title = "FALTA GRAVE · CARTÃO AMARELO"
			elif bool(ev.get("in_box", false)):
				title = "PÊNALTI MARCADO!"
			else:
				title = "FALTA PERIGOSA"

		"penalty":
			is_critical = true
			category = "penalty"
			title = "COBRANÇA DE PÊNALTI!"

	if not is_critical:
		return

	var clip_len: int = int(param("clip_frames", 180))
	var frames := _extract_recent_frames(state["buffer"], int(state.get("buffer_index", 0)), clip_len)
	if frames.is_empty():
		return

	var replay := {
		"id": "replay_%d" % ctx.tick,
		"tick": ctx.tick,
		"type": type,
		"category": category,
		"title": title,
		"description": ctx.message,
		"frames": frames,
		"event": ev.duplicate(true),
	}

	state["last_replay"] = replay
	state["replays"].append(replay)
	ctx.bus.emit(HOOK_REPLAY_READY, {"ctx": ctx, "replay": replay})


func _on_last_replay(payload: Dictionary) -> Variant:
	var ctx: MatchContext = payload.ctx
	return ctx.state_for(id).get("last_replay")


func _on_get_replays(payload: Dictionary) -> Variant:
	var ctx: MatchContext = payload.ctx
	return ctx.state_for(id).get("replays", []).duplicate(true)


static func _extract_recent_frames(buf: Array, buf_idx: int, count: int) -> Array:
	var total := buf.size()
	if total == 0:
		return []
	var take := mini(total, count)
	var out: Array = []

	if total < count:
		for i in range(total):
			out.append(buf[i])
	else:
		for i in range(take):
			var slot := (buf_idx - take + i + total) % total
			out.append(buf[slot])
	return out
