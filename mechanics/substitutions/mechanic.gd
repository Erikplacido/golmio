extends Mechanic
## Substituições automáticas condicionais (GDD 2.3). Regras em team.setup.tactics["auto_subs"]:
##   {"when": "condition_below", "value": 0.3}                             -> troca quem estiver abaixo de 30%
##   {"when": "losing_at", "minute": 60, "out": "<athlete_id>", "in": "<athlete_id>"}
## Lê a condição via ctx.player_condition() — funciona com ou sem a mecânica de estamina
## (sem ela, a condição é sempre 1.0 e a regra de cansaço simplesmente nunca dispara).
## As trocas acontecem quando a bola para (evento "restart"); se o jogo ficar muito tempo
## sem bola parada (ex.: ruleset sem set_pieces), trocam mesmo com a bola rolando.


func _init() -> void:
	id = "substitutions"
	title = "Substituições automáticas"
	description = "Executa as trocas programadas pelo técnico nas bolas paradas."
	version = 1
	layer = "match"
	enabled_by_default = true
	default_params = {
		"max_subs": 5,
		"max_wait_minutes": 3.0,   # sem bola parada por este tempo: troca com a bola rolando
	}


func setup_match(ctx: MatchContext) -> void:
	ctx.bus.on(Hooks.MATCH_EVENT, _on_event, id)
	ctx.bus.on(Hooks.MATCH_PERIODIC, _on_periodic, id)


func _on_event(payload: Dictionary) -> void:
	if payload.event.type == "restart":
		var ctx: MatchContext = payload.ctx
		ctx.state_for(id)["last_dead_ball"] = ctx.minute()
		_apply_rules(ctx)


func _on_periodic(payload: Dictionary) -> void:
	var ctx: MatchContext = payload.ctx
	var last := float(ctx.state_for(id).get("last_dead_ball", 0.0))
	if ctx.minute() - last >= float(param("max_wait_minutes")):
		_apply_rules(ctx)


func _apply_rules(ctx: MatchContext) -> void:
	for team: MatchTeam in ctx.teams():
		var rules: Array = team.setup.tactics.get("auto_subs", [])
		var fired: Dictionary = team.ext_for(id)
		for i in rules.size():
			if team.subs_used >= int(param("max_subs")) or team.bench.is_empty():
				break
			var rule: Dictionary = rules[i]
			match str(rule.get("when", "")):
				"condition_below":
					_sub_tired(ctx, team, float(rule.get("value", 0.3)))
				"losing_at":
					if fired.has(i):
						continue
					if ctx.minute() >= float(rule.get("minute", 60)) and team.stats.goals < ctx.other(team).stats.goals:
						fired[i] = true
						var out_p := ctx.find_player(str(rule.get("out", "")))
						var in_a := _bench_by_id(team, str(rule.get("in", "")))
						if out_p != null and out_p.team == team and in_a != null:
							ctx.substitute(team, out_p, in_a)


func _sub_tired(ctx: MatchContext, team: MatchTeam, threshold: float) -> void:
	for p: MatchPlayer in team.players.duplicate():
		if team.subs_used >= int(param("max_subs")):
			return
		if ctx.player_condition(p) >= threshold:
			continue
		var repl := _best_replacement(team, p)
		if repl != null:
			ctx.substitute(team, p, repl)


func _best_replacement(team: MatchTeam, out_p: MatchPlayer) -> Athlete:
	var fallback: Athlete = null
	for ath: Athlete in team.bench:
		if out_p.is_gk() != ath.is_goalkeeper():
			continue
		if ath.position == out_p.role:
			return ath
		if fallback == null:
			fallback = ath
	return fallback


func _bench_by_id(team: MatchTeam, athlete_id: String) -> Athlete:
	for ath: Athlete in team.bench:
		if ath.id == athlete_id:
			return ath
	return null
