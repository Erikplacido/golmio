extends Mechanic
## Faltas e Cartões (GDD 4, 8.3).
## Intercepta TACKLE_ATTEMPT (pipe) e decide se o lance vira uma falta.
## Se sim: marca `handled=true`, inicia bola parada (freekick ou pênalti) e registra cartão.
## Acúmulo de cartões por partida: 2 amarelos = vermelho automático.
## Oferece `fouls_cards.foul_chance` (pipe float) para crowd_pressure ampliar depois.


func _init() -> void:
	id = "fouls_cards"
	title = "Faltas e Cartões"
	description = "Adiciona faltas ao tackle e emite cartões (GDD 4, 8.3). Falta na área → pênalti."
	version = 1
	data_version = 1
	layer = "match"
	stage = "experimental"
	enabled_by_default = false
	depends_on = ["set_pieces"]   # reinícios (freekick, penalty) precisam da infra de bola parada
	default_params = {
		# Probabilidade base de a falta acontecer (0..1), modulada por atributos
		"foul_base_chance":       0.10,    # 10% dos tackles normais viram falta
		"foul_physical_weight":   0.40,    # quanto a diferença de physical influencia
		"foul_tackle_reduction":  0.35,    # quanto um tackle alto reduz a falta
		# Cartões
		"yellow_chance":          0.28,    # chance de cartão amarelo na falta
		"red_direct_chance":      0.04,    # chance de vermelho direto (falta brutal)
		# Bola parada
		"freekick_delay":         45,      # ticks até a cobrança (0.2s cada)
		"penalty_delay":          60,
	}
	provides_hooks = {
		"fouls_cards.foul_chance": "pipe float chance_base ; payload {ctx, tackler, holder} — multiplique para aumentar a chance de falta (ex.: crowd_pressure).",
		"fouls_cards.foul_committed": "emit {ctx, fouler, victim, in_box, card} — falta confirmada. card: '' | 'yellow' | 'red'.",
	}


func setup_match(ctx: MatchContext) -> void:
	ctx.bus.on(Hooks.TACKLE_ATTEMPT, _on_tackle, id)
	# Estado por partida: cartões amarelos acumulados {athlete_id: int}
	ctx.state_for(id)["yellows"] = {}
	ctx.state_for(id)["reds"]    = {}
	ctx.state_for(id)["fouls"]   = {}   # {team_side: int}


func _on_tackle(val: Dictionary, payload: Dictionary) -> Dictionary:
	# Já tratado por outra mecânica
	if val.get("handled", false):
		return val

	var ctx: MatchContext    = payload.ctx
	var tackler: MatchPlayer = payload.tackler
	var holder: MatchPlayer  = payload.holder

	# Jogador expulso não pode fazer falta (já deveria ter saído, mas garantimos)
	var state := ctx.state_for(id)
	if state["reds"].get(tackler.athlete.id, false):
		return val

	# --- Calcular chance de falta ---
	var base: float = float(param("foul_base_chance"))

	# Diferença de atributo físico (holder mais forte → mais difícil derrubar sem falta)
	var phys_diff := (holder.a("physical") - tackler.a("physical")) / 100.0
	var tackle_skill := tackler.a("tackling") / 100.0

	var chance: float = base
	chance += base * float(param("foul_physical_weight")) * phys_diff
	chance -= base * float(param("foul_tackle_reduction")) * tackle_skill
	chance = maxf(0.0, chance)

	# Hook para crowd_pressure ampliar a chance
	chance = float(ctx.bus.pipe("fouls_cards.foul_chance", chance, {"ctx": ctx, "tackler": tackler, "holder": holder}))

	var rng := ctx.rng_for(id)
	if not rng.chance(chance):
		return val   # não foi falta — leave normal tackle logic

	# --- É UMA FALTA ---
	val["handled"] = true

	# Registrar estatística
	var fouls: Dictionary = state["fouls"]
	fouls[tackler.team.side] = int(fouls.get(tackler.team.side, 0)) + 1

	# Posição da falta
	var foul_pos: Vector2 = holder.pos
	var in_box: bool = _is_in_penalty_box(foul_pos, tackler.team)

	# --- Decidir cartão ---
	var card := ""
	var yellows: Dictionary = state["yellows"]
	var reds: Dictionary    = state["reds"]

	if rng.chance(float(param("red_direct_chance"))):
		card = "red"
		reds[tackler.athlete.id] = true
	elif rng.chance(float(param("yellow_chance"))):
		card = "yellow"
		var ycount := int(yellows.get(tackler.athlete.id, 0)) + 1
		yellows[tackler.athlete.id] = ycount
		if ycount >= 2:
			card = "red"   # 2 amarelos = vermelho automático
			reds[tackler.athlete.id] = true

	# --- Emitir evento ---
	ctx.add_event("foul", tackler, {
		"victim": holder.athlete.id,
		"in_box": in_box,
		"card": card,
		"fouls_team": fouls.get(tackler.team.side, 1),
	})

	# --- Aplicar cartão na mensagem ---
	var card_msg := ""
	match card:
		"yellow": card_msg = " Cartão amarelo para %s!" % tackler.display_name()
		"red":    card_msg = " CARTÃO VERMELHO para %s!" % tackler.display_name()

	# Emitir hook de falta confirmada para outras mecânicas ouvirem
	ctx.bus.emit("fouls_cards.foul_committed", {
		"ctx": ctx, "fouler": tackler, "victim": holder, "in_box": in_box, "card": card
	})

	# --- Bola parada ---
	if in_box:
		var pen_spot := _penalty_spot(tackler.team)
		ctx.begin_restart("penalty", holder.team, pen_spot, int(param("penalty_delay")))
		ctx.message = "PÊNALTI para %s!%s" % [holder.team.name, card_msg]
	else:
		ctx.begin_restart("freekick", holder.team, foul_pos, int(param("freekick_delay")))
		ctx.message = "Falta de %s sobre %s.%s" % [tackler.display_name(), holder.display_name(), card_msg]

	return val


## Verifica se o ponto está dentro da área do time que fez a falta.
## O "time que fez a falta" é o tackler, então verificamos a área do goleiro adversário.
func _is_in_penalty_box(p: Vector2, fouling_team: MatchTeam) -> bool:
	# A área que importa é a do próprio goleiro do fouling_team (donde defender o pênalti)
	# fouling_team.own_goal_x() dá a linha de fundo deste time
	var goal_x := fouling_team.own_goal_x()
	var box_y_top    := (Pitch.H - Pitch.PENALTY_BOX_H) / 2.0
	var box_y_bottom := (Pitch.H + Pitch.PENALTY_BOX_H) / 2.0
	var in_y := p.y >= box_y_top and p.y <= box_y_bottom

	# Profundidade da área a partir da linha de fundo
	var box_depth := Pitch.PENALTY_BOX_W
	var in_x: bool
	if goal_x <= Pitch.W / 2.0:
		# Gol à esquerda (dir=1): área vai de 0 até box_depth
		in_x = p.x >= goal_x and p.x <= goal_x + box_depth
	else:
		# Gol à direita (dir=-1): área vai de W-box_depth até W
		in_x = p.x >= goal_x - box_depth and p.x <= goal_x

	return in_x and in_y


## Ponto de pênalti do goleiro adversário ao fouling_team.
func _penalty_spot(fouling_team: MatchTeam) -> Vector2:
	var goal_x := fouling_team.own_goal_x()
	var spot_offset := Pitch.PENALTY_SPOT_X
	if goal_x <= Pitch.W / 2.0:
		return Vector2(goal_x + spot_offset, Pitch.H / 2.0)
	else:
		return Vector2(goal_x - spot_offset, Pitch.H / 2.0)
