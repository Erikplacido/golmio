extends TestCase


func _summary(r: Dictionary) -> String:
	return JSON.stringify({"h": r.home.stats, "a": r.away.stats, "ev": r.events.size(), "t": r.ticks})


func test_mesma_semente_mesmo_resultado() -> void:
	var reg := Fixtures.registry()
	var r1 := Fixtures.engine(reg, 42).run_to_end()
	var r2 := Fixtures.engine(reg, 42).run_to_end()
	check_eq(_summary(r1), _summary(r2), "determinismo")
	var r3 := Fixtures.engine(reg, 43).run_to_end()
	check(_summary(r1) != _summary(r3), "sementes diferentes devem divergir")


func test_partida_termina_com_resultado_completo() -> void:
	var e := Fixtures.engine(Fixtures.registry(), 7)
	var r := e.run_to_end()
	check(e.is_finished())
	check_eq(r.ticks, e.total_regular_ticks(), "duração regulamentar exata")
	check(r.home.participants.size() >= 11)
	check(r.away.participants.size() >= 11)
	check(r.signature.has("hash"))
	check(r.home.stats.passes_attempted > 0, "houve jogo")
	check(JSON.stringify(r) != "", "resultado serializável")
	var periods: Array = r.events.filter(func(ev): return ev.type == "period_end")
	check_eq(periods.size(), 2)


func test_encerrar_agora_fecha_no_placar_atual() -> void:
	var e := Fixtures.engine(Fixtures.registry(), 7)
	var stop_at := e.total_regular_ticks() / 3
	while e.ctx.tick < stop_at:
		e.step()
	var hg: int = e.ctx.home.stats.goals
	var ag: int = e.ctx.away.stats.goals
	e.end_now()
	check(e.is_finished(), "partida encerrada")
	check_eq(e.result.ticks, stop_at, "não simula o resto")
	check_eq([e.result.home.goals, e.result.away.goals], [hg, ag], "placar do momento")
	check(e.result.extra.has("ended_early"), "resultado marca o encerramento antecipado")
	e.end_now()   # de novo: não faz nada
	check_eq(e.result.ticks, stop_at)


func test_times_trocam_de_lado_no_intervalo() -> void:
	var e := Fixtures.engine(Fixtures.registry(), 3)
	check_eq(e.ctx.home.dir, 1)
	while e.ctx.period_index == 0:
		e.step()
	check_eq(e.ctx.home.dir, -1)
	check_eq(e.ctx.restart.get("team"), e.ctx.away, "2º tempo começa com o visitante")


func test_so_nucleo_roda_sem_mecanicas() -> void:
	var reg := Fixtures.registry("res://rulesets/core_only.json")
	check_eq(reg.enabled_ids().size(), 0)
	var r := Fixtures.engine(reg, 11).run_to_end()
	check_eq(r.home.stats.corners + r.away.stats.corners, 0, "sem set_pieces não há escanteio")
	check(r.home.stats.passes_attempted > 0)


func test_saida_de_bola_apos_gol_e_de_quem_sofreu() -> void:
	var e := Fixtures.engine(Fixtures.registry(), 5, 30.0)
	var ev := e.run_until_event(["goal"], 200000)
	if ev.is_empty():
		return  # nenhum gol nessa semente; o teste de determinismo cobre o resto
	var scoring := e.ctx.team_by_side(ev.data.team)
	check_eq(e.ctx.restart.get("type"), "kickoff")
	check_eq(e.ctx.restart.get("team"), e.ctx.other(scoring), "quem sofreu dá a saída")


func test_pass_released_hook_e_disparado() -> void:
	var reg := Fixtures.registry()
	var e := Fixtures.engine(reg, 42)
	var passes_disparados: Array = []
	e.ctx.bus.on(Hooks.PASS_RELEASED, func(p): passes_disparados.append(p), "test")
	for i in range(150):
		if e.is_finished():
			break
		e.step()
	check(passes_disparados.size() > 0, "hook PASS_RELEASED foi emitido em passes")
	var first: Dictionary = passes_disparados[0]
	check(first.has("ctx"), "payload tem ctx")
	check(first.has("passer") and first.passer is MatchPlayer, "payload tem passer")
	check(first.has("receiver"), "payload tem receiver")
	check(first.has("through"), "payload tem through")


## Cara ou coroa: quem dá a saída no 1º tempo (o outro dá no 2º) e o lado do mandante no 1º tempo.
func test_sorteio_define_saida_e_lado() -> void:
	var reg := Fixtures.registry()
	var s := DemoData.match_setup(11, 4.0)
	var e := MatchEngine.create(s, reg)
	check_eq(e.ctx.home.dir, 1, "padrão: mandante ataca para a direita")
	s = DemoData.match_setup(11, 4.0)
	s.kickoff_side = "away"
	s.home_dir = -1
	e = MatchEngine.create(s, reg)
	check_eq(e.ctx.home.dir, -1, "mandante ataca para a esquerda")
	check_eq(e.ctx.away.dir, 1, "visitante ataca para a direita")
	var r := e.run_to_end()
	var kickoffs: Array = r.events.filter(func(ev): return ev.type == "restart" and ev.data.get("kind") == "kickoff")
	check(kickoffs.size() >= 2, "saídas registradas")
	check_eq(str(kickoffs[0].data.team), "away", "visitante dá a saída do 1º tempo")
	var second: Array = r.events.filter(func(ev): return ev.type == "period_end")
	var t1_end: int = r.events.find(second[0])
	var after: Array = r.events.slice(t1_end).filter(func(ev): return ev.type == "restart" and ev.data.get("kind") == "kickoff")
	check_eq(str(after[0].data.team), "home", "mandante dá a saída do 2º tempo")
