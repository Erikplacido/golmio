extends Mechanic
## Estamina (GDD 5.1): energia cai ao longo da partida conforme o atributo Estamina;
## atributos físicos e técnicos decaem com o cansaço. Energia fica em player.ext["stamina"].


func _init() -> void:
	id = "stamina"
	title = "Estamina e cansaço"
	description = "Energia 0..1 por atleta em campo; reduz atributos efetivos e alimenta PLAYER_CONDITION."
	version = 1
	layer = "match"
	enabled_by_default = true
	default_params = {
		"drain_per_minute": 0.0072,     # dreno base (estamina 50 termina os 90' com ~55%)
		"stamina_protection": 0.6,      # quanto a Estamina 99 reduz o dreno
		"keeper_drain_mult": 0.4,
		"movement_weight": 0.8,         # dreno extra de quem corre mais
		"halftime_recovery": 0.12,      # recuperação entre períodos
		"attr_floor": 0.7,              # com energia 0, atributos caem para 70%
		"affected": ["pace", "physical", "passing", "finishing", "tackling", "positioning", "reflexes", "elasticity"],
	}
	provides_hooks = {
		"stamina.recovery": "pipe float recuperação entre períodos ; payload {ctx, team}. Ex.: vaias da torcida anulam (GDD 8.3).",
	}


func setup_match(ctx: MatchContext) -> void:
	ctx.bus.on(Hooks.MATCH_PERIODIC, _on_periodic, id)
	ctx.bus.on(Hooks.PERIOD_END, _on_period_end, id)
	ctx.bus.on(Hooks.PLAYER_ATTRIBUTES, _on_attributes, id)
	ctx.bus.on(Hooks.PLAYER_CONDITION, _on_condition, id)


func energy(p: MatchPlayer) -> float:
	return float(p.ext.get(id, 1.0))


func _on_periodic(payload: Dictionary) -> void:
	var ctx: MatchContext = payload.ctx
	var dt_min := float(payload.dt) / 60.0
	var base := float(param("drain_per_minute"))
	var prot := float(param("stamina_protection"))
	var mw := float(param("movement_weight"))
	for p: MatchPlayer in ctx.all_players:
		var st := p.athlete.attr("stamina") / 99.0
		var effort := 1.0 - mw * 0.5 + mw * clampf(DMath.length(p.vel) / maxf(p.max_speed, 0.1), 0.0, 1.0)
		var drain := base * (1.0 - prot * st) * effort * dt_min
		if p.is_gk():
			drain *= float(param("keeper_drain_mult"))
		p.ext[id] = maxf(0.0, energy(p) - drain)


func _on_period_end(payload: Dictionary) -> void:
	var ctx: MatchContext = payload.ctx
	for t: MatchTeam in ctx.teams():
		var rec := float(ctx.bus.pipe("stamina.recovery", float(param("halftime_recovery")), {"ctx": ctx, "team": t}))
		for p: MatchPlayer in t.players:
			p.ext[id] = minf(1.0, energy(p) + rec)


func _on_attributes(attrs: Dictionary, payload: Dictionary) -> Dictionary:
	var p: MatchPlayer = payload.player
	var factor := DMath.lerp(float(param("attr_floor")), 1.0, energy(p))
	for k in param("affected"):
		if attrs.has(k):
			attrs[k] = float(attrs[k]) * factor
	return attrs


func _on_condition(value: float, payload: Dictionary) -> float:
	return minf(value, energy(payload.player))
