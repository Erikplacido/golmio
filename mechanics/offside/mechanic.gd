extends Mechanic
## Regra do Impedimento / Offside (GDD 4, Bloco B).
##
## Detecta impedimento no momento do passe (Hooks.PASS_RELEASED).
## Um jogador está em posição de impedimento se, no momento do passe:
## 1. Está na metade do campo adversária ((pos.x - W/2) * team.dir > 0).
## 2. Está à frente da bola ((pos.x - ball.pos.x) * team.dir > 0).
## 3. Está à frente do penúltimo adversário (2ª linha de defesa).
##
## Em caso de impedimento confirmado, o lance é interrompido no tick seguinte
## e reiniciado com tiro livre indireto (freekick) para a equipe defensora.


func _init() -> void:
	id = "offside"
	title = "Regra do Impedimento"
	description = "Detecta impedimento no momento do passe e assinala falta para a defesa (GDD 4, Bloco B)."
	version = 1
	data_version = 1
	layer = "match"
	stage = "experimental"
	enabled_by_default = false
	depends_on = []
	default_params = {
		"freekick_delay": 40,   # ticks de pausa até a cobrança (0.2s cada)
		"margin":         0.0,  # margem de tolerância geométrica (unidades de campo)
	}
	provides_hooks = {
		"offside.detected": "emit {ctx, passer, receiver, line_x} — emitido quando um impedimento é detectado.",
	}


func setup_match(ctx: MatchContext) -> void:
	ctx.bus.on(Hooks.PASS_RELEASED, _on_pass_released, id)
	ctx.bus.on(Hooks.MATCH_TICK, _on_tick, id)
	var state := ctx.state_for(id)
	state["offsides"] = {}          # {team_side: int}
	state["pending_offside"] = null # guarda o impedimento para aplicar no tick seguinte


func _on_pass_released(payload: Dictionary) -> void:
	var ctx: MatchContext = payload.ctx
	var passer: MatchPlayer = payload.passer
	var receiver: MatchPlayer = payload.receiver

	if passer == null or receiver == null:
		return
	if receiver.is_gk() or receiver == passer or receiver.team != passer.team:
		return

	var fwd := float(passer.team.dir)

	# 1. Metade do campo adversária:
	# Não há impedimento no próprio campo de defesa
	var in_attacking_half := (receiver.pos.x - Pitch.W / 2.0) * fwd > 0.0
	if not in_attacking_half:
		return

	# 2. À frente da linha da bola:
	# Passe para trás ou na mesma linha da bola não é impedimento
	var ahead_of_ball := (receiver.pos.x - ctx.ball.pos.x) * fwd > 0.0
	if not ahead_of_ball:
		return

	# 3. Penúltimo adversário (2ª linha de defesa):
	# Coleta profundidade de todos os adversários em campo em direção ao próprio gol
	var def_team: MatchTeam = ctx.other(passer.team)
	var depths: Array[float] = []
	for opp: MatchPlayer in def_team.players:
		depths.append(opp.pos.x * fwd)

	if depths.size() < 2:
		return

	depths.sort()
	depths.reverse() # Ordem decrescente: o maior valor é o jogador mais recuado

	var second_last: float = depths[1]
	var receiver_depth: float = receiver.pos.x * fwd
	var margin: float = float(param("margin"))

	# Se o receptor está além do penúltimo adversário + margem
	var is_offside := receiver_depth > (second_last + margin)
	if not is_offside:
		return

	# Notificação via hook para observadores
	ctx.bus.emit("offside.detected", {
		"ctx": ctx,
		"passer": passer,
		"receiver": receiver,
		"line_x": second_last * fwd,
	})

	# Armazena para interromper no início do tick seguinte
	var state := ctx.state_for(id)
	state["pending_offside"] = {
		"passer": passer,
		"receiver": receiver,
		"pos": passer.pos,
	}


func _on_tick(payload: Dictionary) -> void:
	var ctx: MatchContext = payload.ctx
	var state := ctx.state_for(id)
	var pending = state.get("pending_offside", null)
	if pending == null:
		return

	state["pending_offside"] = null

	var passer: MatchPlayer = pending["passer"]
	var receiver: MatchPlayer = pending["receiver"]
	var foul_pos: Vector2 = pending["pos"]
	var def_team: MatchTeam = ctx.other(passer.team)

	# Atualiza estatísticas da partida
	var offsides: Dictionary = state["offsides"]
	offsides[passer.team.side] = int(offsides.get(passer.team.side, 0)) + 1

	# Registra evento na timeline oficial
	ctx.add_event("offside", receiver, {
		"passer": passer.athlete.id,
		"receiver": receiver.athlete.id,
		"team": passer.team.side,
		"offsides_team": offsides[passer.team.side],
	})

	# Reinício de jogo: falta para o time adversário
	var delay: int = int(param("freekick_delay"))
	ctx.begin_restart("freekick", def_team, foul_pos, delay)
	ctx.ball.vel = Vector2.ZERO
	ctx.message = "Impedimento de %s!" % receiver.display_name()
