extends Mechanic
## Mentalidade tática base (GDD 2.3), escala de 7 níveis do mais defensivo ao mais ofensivo:
## Retranca, Defensivo, Cauteloso, Equilibrado, Positivo, Ofensivo, Pressão Total (GameTerms.MENTALITIES).
## Lê team.setup.tactics["mentality"] e ajusta os knobs do time. Novos perfis = só dados no ruleset.
## Os níveis intermediários interpolam os vizinhos: cada passo muda pouco, para o controle ser fino.


func _init() -> void:
	id = "mentality"
	title = "Mentalidade tática"
	description = "Perfis de comportamento coletivo aplicados sobre MatchTeam.DEFAULT_KNOBS."
	version = 3
	layer = "match"
	enabled_by_default = true
	default_params = {
		"default": "equilibrado",
		"profiles": {
			"retranca": {"line_height": -45.0, "press_radius": 120.0, "shot_range_mult": 0.9,
				"shot_prob_mult": 0.85, "pass_risk": -0.3, "tempo_frames": 20},
			"defensivo": {"line_height": -30.0, "press_radius": 140.0, "shot_range_mult": 0.93,
				"shot_prob_mult": 0.9, "pass_risk": -0.2, "tempo_frames": 19},
			"cauteloso": {"line_height": -15.0, "press_radius": 160.0, "shot_range_mult": 0.97,
				"shot_prob_mult": 0.95, "pass_risk": -0.1, "tempo_frames": 18},
			"equilibrado": {},
			"positivo": {"line_height": 15.0, "press_radius": 185.0, "shot_range_mult": 1.05,
				"shot_prob_mult": 1.07, "pass_risk": 0.15, "tempo_frames": 14},
			"ofensivo": {"line_height": 30.0, "press_radius": 190.0, "shot_range_mult": 1.1,
				"shot_prob_mult": 1.15, "pass_risk": 0.3, "tempo_frames": 12},
			"pressao_total": {"line_height": 45.0, "press_radius": 260.0, "press_count": 2,
				"shot_prob_mult": 1.05, "pass_risk": 0.2, "tempo_frames": 12},
		},
	}


func setup_match(ctx: MatchContext) -> void:
	# Prioridade baixa: define a base; outras mecânicas (ex.: crise da torcida) ajustam depois.
	ctx.bus.on(Hooks.TEAM_KNOBS, _on_knobs, id, -100)


func _on_knobs(knobs: Dictionary, payload: Dictionary) -> Dictionary:
	var team: MatchTeam = payload.team
	var chosen := str(team.setup.tactics.get("mentality", param("default")))
	var profiles: Dictionary = param("profiles")
	if not profiles.has(chosen):
		push_warning("Mentalidade desconhecida '%s' em %s; usando padrão." % [chosen, team.name])
		chosen = str(param("default"))
	var profile: Dictionary = profiles.get(chosen, {})
	for k in profile:
		knobs[k] = profile[k]
	return knobs
