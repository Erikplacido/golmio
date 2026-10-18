extends Mechanic
## Mentalidade tática base (GDD 2.3), escala de 7 níveis do mais defensivo ao mais ofensivo:
## Retranca, Defensivo, Cauteloso, Equilibrado, Positivo, Ofensivo, Pressão Total (GameTerms.MENTALITIES).
## Matriz Intransitiva (Pedra-Papel-Tesoura) — TASK-06:
##   - Pressão Alta (High Press) > Posse / Retranca (Compact Possession): asfixia saída de bola.
##   - Contra-Ataque Direto (Direct Counter) > Pressão Alta (High Press): explora linha alta nas costas.
##   - Posse / Retranca (Compact Possession) > Contra-Ataque Direto (Direct Counter): nega espaço nas costas.

const ARCHETYPE_HIGH_PRESS := "high_press"
const ARCHETYPE_DIRECT_COUNTER := "direct_counter"
const ARCHETYPE_COMPACT_POSSESSION := "compact_possession"
const ARCHETYPE_BALANCED := "balanced"


func _init() -> void:
	id = "mentality"
	title = "Mentalidade tática"
	description = "Perfis de comportamento coletivo aplicados sobre MatchTeam.DEFAULT_KNOBS com dinâmica intransitiva."
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
	ctx.bus.on(Hooks.TEAM_KNOBS, _on_knobs, id, -100)
	ctx.bus.on(Hooks.TACKLE_ATTEMPT, _on_tackle, id, 0)
	ctx.bus.on(Hooks.PLAYER_ATTRIBUTES, _on_player_attributes, id, 0)


static func get_archetype(team: MatchTeam, default_mentality: String = "equilibrado") -> String:
	if team == null or team.setup == null:
		return ARCHETYPE_BALANCED
	var m := str(team.setup.tactics.get("mentality", default_mentality))
	match m:
		"pressao_total":
			return ARCHETYPE_HIGH_PRESS
		"ofensivo", "positivo":
			return ARCHETYPE_DIRECT_COUNTER
		"retranca", "defensivo":
			return ARCHETYPE_COMPACT_POSSESSION
		_:
			return ARCHETYPE_BALANCED


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

	var ctx: MatchContext = payload.get("ctx", null)
	if ctx == null:
		return knobs

	var opp := ctx.other(team)
	if opp == null:
		return knobs

	var def_m := str(param("default"))
	var my_arch := get_archetype(team, def_m)
	var opp_arch := get_archetype(opp, def_m)

	# Direct / Counter > High Press
	if my_arch == ARCHETYPE_DIRECT_COUNTER and opp_arch == ARCHETYPE_HIGH_PRESS:
		knobs["pass_risk"] = float(knobs.get("pass_risk", 0.0)) + 0.30
		knobs["shot_range_mult"] = float(knobs.get("shot_range_mult", 1.0)) * 1.15
		knobs["shot_prob_mult"] = float(knobs.get("shot_prob_mult", 1.0)) * 1.15

	# Compact / Possession > Direct / Counter
	elif my_arch == ARCHETYPE_COMPACT_POSSESSION and opp_arch == ARCHETYPE_DIRECT_COUNTER:
		knobs["line_height"] = float(knobs.get("line_height", 0.0)) - 12.0
		knobs["pass_risk"] = float(knobs.get("pass_risk", 0.0)) - 0.20
		knobs["tempo_frames"] = int(knobs.get("tempo_frames", 16)) + 2

	# High Press > Compact / Possession
	elif my_arch == ARCHETYPE_HIGH_PRESS and opp_arch == ARCHETYPE_COMPACT_POSSESSION:
		knobs["press_radius"] = float(knobs.get("press_radius", 180.0)) + 30.0
		knobs["press_count"] = 2

	return knobs


func _on_tackle(data: Dictionary, payload: Dictionary) -> Dictionary:
	var tackler: MatchPlayer = payload.get("tackler", null)
	var holder: MatchPlayer = payload.get("holder", null)
	if tackler == null or holder == null:
		return data

	var my_team: MatchTeam = tackler.team
	var opp_team: MatchTeam = holder.team
	if my_team == null or opp_team == null:
		return data

	var def_m := str(param("default"))
	var my_arch := get_archetype(my_team, def_m)
	var opp_arch := get_archetype(opp_team, def_m)

	# High Press > Compact / Possession: bônus de interceptação/desarme no campo do adversário
	if my_arch == ARCHETYPE_HIGH_PRESS and opp_arch == ARCHETYPE_COMPACT_POSSESSION:
		var in_opp_half := holder.pos.x < Pitch.W * 0.5 if opp_team.dir == 1 else holder.pos.x > Pitch.W * 0.5
		if in_opp_half:
			var cur_chance: float = float(data.get("chance", 0.5))
			data["chance"] = minf(0.95, cur_chance * 1.25)

	return data


func _on_player_attributes(attrs: Dictionary, payload: Dictionary) -> Dictionary:
	var p: MatchPlayer = payload.get("player", null)
	var ctx: MatchContext = payload.get("ctx", null)
	if p == null or p.team == null or ctx == null:
		return attrs

	var my_team: MatchTeam = p.team
	var opp := ctx.other(my_team)
	if opp == null:
		return attrs

	var def_m := str(param("default"))
	var my_arch := get_archetype(my_team, def_m)
	var opp_arch := get_archetype(opp, def_m)

	# Direct / Counter > High Press: atacantes e meias recebem impulso de transição rápida
	if my_arch == ARCHETYPE_DIRECT_COUNTER and opp_arch == ARCHETYPE_HIGH_PRESS:
		if p.role in ["FWD", "MID"]:
			attrs["pace"] = clampf(float(attrs.get("pace", 50.0)) + 6.0, 1.0, 99.0)
			attrs["passing"] = clampf(float(attrs.get("passing", 50.0)) + 5.0, 1.0, 99.0)

	# Compact / Possession > Direct / Counter: defensores firmes na antecipação
	elif my_arch == ARCHETYPE_COMPACT_POSSESSION and opp_arch == ARCHETYPE_DIRECT_COUNTER:
		if p.role in ["DEF", "GK"]:
			attrs["tackling"] = clampf(float(attrs.get("tackling", 50.0)) + 8.0, 1.0, 99.0)
			attrs["physical"] = clampf(float(attrs.get("physical", 50.0)) + 5.0, 1.0, 99.0)

	# High Press > Compact / Possession: pressão agressiva de desarme no ataque
	elif my_arch == ARCHETYPE_HIGH_PRESS and opp_arch == ARCHETYPE_COMPACT_POSSESSION:
		if p.role in ["FWD", "MID"]:
			attrs["tackling"] = clampf(float(attrs.get("tackling", 50.0)) + 6.0, 1.0, 99.0)

	return attrs

