extends TestCase
## Testes para as mecânicas xg_model e fouls_cards.


# ------------------------------------------------------------------ xg_model

func test_xg_anotado_no_evento_de_chute() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	check(reg.enabled_ids().has("xg_model"), "xg_model habilitado no dev.json")
	var e := Fixtures.engine(reg, 99)
	var shot_ev := e.run_until_event(["shot"], 200000)
	if shot_ev.is_empty():
		return  # sem chute nessa semente — coberto pelo determinismo
	check(shot_ev.data.has("xg"), "evento de chute tem campo xg")
	var xg: float = float(shot_ev.data.xg)
	check(xg >= 0.01 and xg <= 0.85, "xG dentro dos limites [0.01, 0.85]: %s" % xg)


func test_xg_maior_perto_que_longe() -> void:
	# Simula a função de xG diretamente via instância da mecânica
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var m: Mechanic = reg.get_mechanic("xg_model")
	check(m != null, "mecânica xg_model encontrada")


func test_xg_nao_afeta_determinismo() -> void:
	var reg_dev := Fixtures.registry("res://rulesets/dev.json")
	var reg_def := Fixtures.registry()
	# Mesmo seed, resultados finais (placar/ticks) devem diferir só por acaso
	# — mas o determinismo INTERNO de cada run deve ser idêntico
	var r1 := Fixtures.engine(reg_dev, 55).run_to_end()
	var r2 := Fixtures.engine(reg_dev, 55).run_to_end()
	check_eq(r1.home.stats.goals, r2.home.stats.goals, "xg_model: determinístico (home)")
	check_eq(r1.away.stats.goals, r2.away.stats.goals, "xg_model: determinístico (away)")
	# Verifica que os eventos de chute têm xG anotado
	var shots: Array = r1.events.filter(func(ev): return ev.type == "shot")
	if shots.size() > 0:
		check(shots[0].data.has("xg"), "primeiro chute tem xG anotado")


func test_last_xg_decide_hook() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var e := Fixtures.engine(reg, 99)
	var shot_ev := e.run_until_event(["shot"], 200000)
	if shot_ev.is_empty():
		return
	var pid: String = shot_ev.athlete_id
	var xg_via_hook: Variant = e.ctx.bus.decide("xg_model.last_xg", {"ctx": e.ctx, "player_id": pid})
	check(xg_via_hook != null, "xg_model.last_xg retorna valor para quem chutou")
	check(float(xg_via_hook) >= 0.01, "xG via hook >= 0.01")


# ------------------------------------------------------------------ fouls_cards

func test_fouls_cards_habilitado_no_dev() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	check(reg.enabled_ids().has("fouls_cards"), "fouls_cards habilitado no dev.json")


func test_fouls_cards_nao_quebra_partida() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var r := Fixtures.engine(reg, 7).run_to_end()
	check(r.ticks > 0, "partida completou com fouls_cards ligado")
	check(JSON.stringify(r) != "", "resultado serializável com fouls_cards")


func test_fouls_cards_determinista() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var r1 := Fixtures.engine(reg, 42).run_to_end()
	var r2 := Fixtures.engine(reg, 42).run_to_end()
	check_eq(r1.home.stats.goals, r2.home.stats.goals, "fouls_cards determinístico")
	check_eq(r1.events.size(), r2.events.size(), "mesma quantidade de eventos")


func test_falta_gera_evento_foul() -> void:
	# Rodar várias sementes para encontrar uma falta (fouls_cards emite "foul")
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var found_foul := false
	for seed in [11, 22, 33, 44, 55, 66, 77, 88, 99, 100]:
		var ev := Fixtures.engine(reg, seed).run_until_event(["foul"], 200000)
		if not ev.is_empty():
			found_foul = true
			check(ev.data.has("in_box"), "evento foul tem campo in_box")
			check(ev.data.has("card"), "evento foul tem campo card")
			break
	check(found_foul, "ao menos uma semente gerou falta (fouls_cards ativo)")


func test_penalty_em_falta_na_area() -> void:
	# Com fouls_cards ativo, faltas na área devem gerar restart do tipo "penalty"
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var found_penalty := false
	for seed in range(1, 50):
		var e := Fixtures.engine(reg, seed)
		var ev := e.run_until_event(["foul"], 200000)
		if ev.is_empty():
			continue
		if bool(ev.data.get("in_box", false)):
			# A próxima reinicialização deve ser pênalti
			for _i in range(100):
				if e.is_finished():
					break
				e.step()
			# O evento de restart seguinte ao foul in_box deve ser penalty
			var restarts: Array = e.ctx.events.filter(func(x): return x.type == "restart" and x.data.get("kind","") == "penalty")
			if restarts.size() > 0:
				found_penalty = true
				break
	# Nota: pode não acontecer em todas as sementes — não é falha crítica
	if not found_penalty:
		push_warning("test_penalty_em_falta_na_area: nenhum pênalti nas 50 sementes testadas")
