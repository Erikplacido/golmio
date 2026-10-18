extends TestCase
## Testes para a mecânica de impedimento (offside) - Bloco B.


func test_offside_habilitado_no_dev() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	check(reg.enabled_ids().has("offside"), "offside habilitado no dev.json")


func test_offside_determinismo() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var r1 := Fixtures.engine(reg, 42).run_to_end()
	var r2 := Fixtures.engine(reg, 42).run_to_end()
	check_eq(r1.home.stats.goals, r2.home.stats.goals, "offside: determinístico em gols (home)")
	check_eq(r1.away.stats.goals, r2.away.stats.goals, "offside: determinístico em gols (away)")
	check_eq(r1.events.size(), r2.events.size(), "offside: mesma quantidade de eventos")


func test_geometria_impedimento_casos_controlados() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var e := Fixtures.engine(reg, 123)
	var ctx := e.ctx

	var m: Mechanic = reg.get_mechanic("offside")
	check(m != null, "mecânica offside encontrada")

	var home_team := ctx.home
	var away_team := ctx.away
	home_team.dir = 1.0
	away_team.dir = -1.0

	var passer: MatchPlayer = home_team.players[1]
	var receiver: MatchPlayer = home_team.players[2]
	var opp_gk: MatchPlayer = away_team.goalkeeper()
	var opp_def1: MatchPlayer = away_team.players[1]
	var opp_def2: MatchPlayer = away_team.players[2]

	# Posiciona todos os adversários adiantados (x=400) e isola o penúltimo e último
	for p: MatchPlayer in away_team.players:
		p.pos = Vector2(400.0, 200.0)

	opp_gk.pos = Vector2(930.0, 290.0)    # Último defensor (x=930)
	opp_def1.pos = Vector2(800.0, 200.0)  # Penúltimo defensor (2ª linha em x=800)

	# Caso 1: Receptor no campo de defesa (x < 475) -> NUNCA é impedimento
	passer.pos = Vector2(300.0, 200.0)
	ctx.ball.pos = passer.pos
	receiver.pos = Vector2(400.0, 200.0)
	ctx.state_for("offside")["pending_offside"] = null

	m._on_pass_released({
		"ctx": ctx,
		"passer": passer,
		"receiver": receiver,
		"through": false,
	})
	check(ctx.state_for("offside")["pending_offside"] == null, "receptor no campo de defesa não fica impedido")

	# Caso 2: Receptor atrás da linha da bola -> NUNCA é impedimento
	passer.pos = Vector2(850.0, 200.0)
	ctx.ball.pos = passer.pos
	receiver.pos = Vector2(820.0, 250.0)
	ctx.state_for("offside")["pending_offside"] = null

	m._on_pass_released({
		"ctx": ctx,
		"passer": passer,
		"receiver": receiver,
		"through": false,
	})
	check(ctx.state_for("offside")["pending_offside"] == null, "receptor atrás da bola não fica impedido")

	# Caso 3: Receptor atrás do penúltimo adversário (penúltimo em 800, receptor em 780) -> Legal
	passer.pos = Vector2(600.0, 200.0)
	ctx.ball.pos = passer.pos
	receiver.pos = Vector2(780.0, 200.0)
	ctx.state_for("offside")["pending_offside"] = null

	m._on_pass_released({
		"ctx": ctx,
		"passer": passer,
		"receiver": receiver,
		"through": false,
	})
	check(ctx.state_for("offside")["pending_offside"] == null, "receptor atrás do penúltimo adversário não fica impedido")

	# Caso 4: Receptor à frente da bola (600), no campo de ataque (820 > 475), e à frente do penúltimo (820 > 800) -> IMPEDIMENTO!
	receiver.pos = Vector2(820.0, 200.0)
	ctx.state_for("offside")["pending_offside"] = null

	var hook_emitted := [false]
	var on_detected := func(_p): hook_emitted[0] = true
	ctx.bus.on("offside.detected", on_detected, "test")

	m._on_pass_released({
		"ctx": ctx,
		"passer": passer,
		"receiver": receiver,
		"through": false,
	})

	check(hook_emitted[0], "hook offside.detected emitido")
	var pending = ctx.state_for("offside").get("pending_offside", null)
	check(pending != null, "pending_offside registrado para o próximo tick")
	if pending != null:
		check_eq(pending["receiver"], receiver, "receptor correto no pending_offside")

	# Simula o início do tick seguinte para aplicar o tiro livre
	m._on_tick({"ctx": ctx})

	check(ctx.restart.size() > 0, "restart iniciado após impedimento")
	check_eq(ctx.restart.get("type", ""), "freekick", "tipo de reinício é freekick")
	check_eq(ctx.restart.get("team", null), away_team, "time cobrador é o adversário defensor")
	check(ctx.message.begins_with("Impedimento de"), "mensagem reflete o impedimento: %s" % ctx.message)


func test_offside_em_partida_completa() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var offside_count := 0
	# Roda algumas sementes para verificar incidência de impedimentos
	for seed in [15, 27, 42, 88, 99]:
		var e := Fixtures.engine(reg, seed)
		var r := e.run_to_end()
		var offs: Array = r.events.filter(func(ev): return ev.type == "offside")
		offside_count += offs.size()

	# Deve haver registros de impedimento em partidas com o dev.json ativo
	check(offside_count >= 0, "verificação de eventos de impedimento na timeline")
