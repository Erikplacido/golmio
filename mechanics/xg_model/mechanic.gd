extends Mechanic
## Modelo de Gols Esperados — xG (GDD seção 4).
## Calcula a probabilidade de gol de cada chute com base em distância, ângulo e atributos
## do chutador e do goleiro. Anota `data.xg` no evento de chute.
## Oferece `xg_model.last_xg` via decide (para replays e estatísticas).
## Todos os cálculos usam DMath (determinístico, sem pow() da libm).


func _init() -> void:
	id = "xg_model"
	title = "Modelo xG (Gols Esperados)"
	description = "Anota a probabilidade de gol em cada chute. Usado por replays e estatísticas (GDD 4)."
	version = 1
	data_version = 1
	layer = "match"
	stage = "experimental"
	enabled_by_default = false
	default_params = {
		# Distâncias de referência do campo (coordenadas do motor, em unidades Pitch)
		"dist_close":        100.0,   # abaixo → chute próximo (xG alto)
		"dist_far":          250.0,   # acima → chute de longe (xG baixo)
		"xg_close_base":     0.38,    # xG base para chutes próximos sem atributos
		"xg_far_base":       0.05,    # xG base para chutes de longe
		# Pesos de atributos (0..1 — contribuição no cálculo final)
		"finishing_weight":  0.35,    # quanto finishing do chutador melhora o xG
		"angle_weight":      0.30,    # quanto o ângulo reduz o xG (perpendicular=1.0)
		"keeper_weight":     0.25,    # quanto os atributos do goleiro reduzem o xG
		# Clamping do xG final
		"xg_min":            0.01,
		"xg_max":            0.85,
	}
	provides_hooks = {
		"xg_model.last_xg": "decide {ctx, player_id} -> float xG do último chute desse atleta (null se não chutou).",
	}


func setup_match(ctx: MatchContext) -> void:
	ctx.bus.on(Hooks.MATCH_EVENT, _on_event, id)
	ctx.bus.on("xg_model.last_xg", _on_last_xg, id)
	ctx.state_for(id)["last_by_player"] = {}  # athlete_id -> xG do último chute


func _on_event(payload: Dictionary) -> void:
	var ev: Dictionary = payload.event
	if ev.type != "shot":
		return
	var ctx: MatchContext = payload.ctx
	var state := ctx.state_for(id)

	# --- Pegar os jogadores envolvidos ---
	var shooter: MatchPlayer = ctx.find_player(ev.athlete_id)
	if shooter == null:
		return
	var keeper: MatchPlayer = ctx.other(shooter.team).goalkeeper()

	# --- Geometria ---
	# Distância da bola até o gol adversário no momento do chute
	var goal_center := Vector2(shooter.team.opp_goal_x(), Pitch.H / 2.0)
	var dist: float = float(ev.data.get("distance", DMath.dist(shooter.pos, goal_center)))

	# Cosseno do ângulo de visão do gol (1.0 = chute frontal, 0.0 = pela linha de fundo)
	var dx := absf(goal_center.x - shooter.pos.x)
	var cos_angle: float = dx / maxf(dist, 1.0)

	# --- Atributos ---
	var fin: float = shooter.a("finishing") / 100.0
	var keeper_qual: float = 0.0
	if keeper != null:
		keeper_qual = (keeper.a("positioning") * 0.5 + keeper.a("reflexes") * 0.5) / 100.0

	# --- Interpolação de distância (0=perto, 1=longe) ---
	var dist_close: float = float(param("dist_close"))
	var dist_far:   float = float(param("dist_far"))
	var dist_t: float = clampf((dist - dist_close) / maxf(dist_far - dist_close, 1.0), 0.0, 1.0)

	var xg_close: float = float(param("xg_close_base"))
	var xg_far:   float = float(param("xg_far_base"))
	var xg_base: float  = DMath.lerp(xg_close, xg_far, dist_t)

	# --- Contribuição dos fatores ---
	var fw := float(param("finishing_weight"))
	var aw := float(param("angle_weight"))
	var kw := float(param("keeper_weight"))

	var xg: float = xg_base
	xg += xg_base * fw * (fin - 0.5) * 2.0          # finishing acima/abaixo de 50 melhora/piora
	xg -= xg * aw * (1.0 - cos_angle)                # ângulo ruim reduz proporcionalmente
	xg -= xg * kw * keeper_qual                       # goleiro de qualidade reduz

	xg = clampf(xg, float(param("xg_min")), float(param("xg_max")))

	# --- Anotar no evento e salvar no estado da partida ---
	ev.data["xg"] = DMath.round_to(xg, 0.001)
	state["last_by_player"][ev.athlete_id] = xg


func _on_last_xg(payload: Dictionary) -> Variant:
	# decide: retorna o xG do último chute do atleta solicitado, ou null
	var ctx: MatchContext = payload.ctx
	var pid: String = str(payload.get("player_id", ""))
	var state := ctx.state_for(id)
	var by_player: Dictionary = state.get("last_by_player", {})
	if by_player.has(pid):
		return by_player[pid]
	return null
