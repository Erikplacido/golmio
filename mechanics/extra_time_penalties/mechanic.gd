extends Mechanic
## Prorrogação e disputa de pênaltis em mata-mata (GDD 3).
## Chute: Finalização + energia restante do batedor x Reflexo + Posicionamento + Elasticidade do goleiro.
## Ordem dos batedores: team.setup.tactics["penalty_order"] (ids), completada pelos melhores finalizadores.


func _init() -> void:
	id = "extra_time_penalties"
	title = "Prorrogação e pênaltis"
	description = "Empate em mata-mata: 2 x 15 min e, persistindo, disputa de pênaltis."
	version = 1
	layer = "match"
	enabled_by_default = true
	default_params = {
		"extra_period_minutes": 15.0,   # 0 = vai direto aos pênaltis
		"kicks": 5,
		"base_conversion": 0.76,
		"skill_weight": 0.5,
		"min_conversion": 0.35,
		"max_conversion": 0.95,
	}
	provides_hooks = {
		"extra_time_penalties.kick_chance": "pipe float chance de gol da cobrança ; payload {ctx, shooter, keeper}. Ex.: pressão da torcida (GDD 8.3).",
	}


func setup_match(ctx: MatchContext) -> void:
	ctx.bus.on(Hooks.MATCH_END_DECISION, _on_end_decision, id)


func _on_end_decision(payload: Dictionary) -> Variant:
	var ctx: MatchContext = payload.ctx
	if not ctx.setup.knockout or ctx.home.stats.goals != ctx.away.stats.goals:
		return null
	var st := ctx.state_for(id)
	var minutes := float(param("extra_period_minutes"))
	if not st.get("extra_time_played", false) and minutes > 0.0:
		st["extra_time_played"] = true
		ctx.add_event("extra_time", null, {})
		var secs := minutes * 60.0 * ctx.setup.match_minutes / 90.0  # escala junto com partidas encurtadas
		return [{"id": "P1", "seconds": secs}, {"id": "P2", "seconds": secs}]
	_shootout(ctx)
	return null


func _shootout(ctx: MatchContext) -> void:
	var rng := ctx.rng_for(id)
	var order := {"home": _kickers(ctx.home), "away": _kickers(ctx.away)}
	var score := {"home": 0, "away": 0}
	var taken := {"home": 0, "away": 0}
	var kicks: Array = []
	var n := int(param("kicks"))
	var round_i := 0
	while round_i < 100:
		for side in ["home", "away"]:
			var team := ctx.team_by_side(side)
			var shooter: MatchPlayer = order[side][taken[side] % order[side].size()]
			var keeper := ctx.other(team).goalkeeper()
			var scored := rng.chance(_kick_chance(ctx, shooter, keeper))
			taken[side] += 1
			if scored:
				score[side] += 1
			kicks.append({"team": side, "athlete_id": shooter.athlete.id, "scored": scored})
			ctx.add_event("penalty_kick", shooter, {"scored": scored})
			if round_i < n and _decided(score, taken, n):
				_store(ctx, score, kicks)
				return
		round_i += 1
		if round_i >= n and score.home != score.away:
			_store(ctx, score, kicks)
			return


func _decided(score: Dictionary, taken: Dictionary, n: int) -> bool:
	var left_home := n - int(taken.home)
	var left_away := n - int(taken.away)
	return score.home + left_home < score.away or score.away + left_away < score.home


func _store(ctx: MatchContext, score: Dictionary, kicks: Array) -> void:
	var winner := "home" if score.home > score.away else "away"
	ctx.result_extra["shootout"] = {"home": score.home, "away": score.away, "kicks": kicks}
	ctx.result_extra["winner"] = winner
	ctx.message = "%s vence nos pênaltis (%d x %d)!" % [ctx.team_by_side(winner).name, score.home, score.away]


func _kick_chance(ctx: MatchContext, shooter: MatchPlayer, keeper: MatchPlayer) -> float:
	var shot_skill := shooter.athlete.attr("finishing") * (0.75 + 0.25 * ctx.player_condition(shooter))
	var keep_skill := 50.0
	if keeper:
		keep_skill = (keeper.athlete.attr("reflexes") + keeper.athlete.attr("positioning") + keeper.athlete.attr("elasticity")) / 3.0
	var p := float(param("base_conversion")) + (shot_skill - keep_skill) / 100.0 * float(param("skill_weight"))
	p = float(ctx.bus.pipe("extra_time_penalties.kick_chance", p, {"ctx": ctx, "shooter": shooter, "keeper": keeper}))
	return clampf(p, float(param("min_conversion")), float(param("max_conversion")))


func _kickers(team: MatchTeam) -> Array:
	var out: Array = []
	for aid in team.setup.tactics.get("penalty_order", []):
		for p: MatchPlayer in team.players:
			if p.athlete.id == aid and not out.has(p):
				out.append(p)
	var rest: Array = team.players.filter(func(p): return not out.has(p) and not p.is_gk())
	rest.sort_custom(func(x, y): return x.athlete.attr("finishing") > y.athlete.attr("finishing") \
		or (x.athlete.attr("finishing") == y.athlete.attr("finishing") and x.athlete.id < y.athlete.id))
	out.append_array(rest)
	var gk := team.goalkeeper()
	if gk:
		out.append(gk)
	return out
