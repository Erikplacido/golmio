extends TestCase
## GameStore (autoload Game): leitura do mundo, escalação -> TeamSetup, pareamento por força,
## partida preparada e registrada uma vez só, oficial diário, histórico e etapas da estreia.
## Tudo num backend em memória (MemoryBackend): nada toca no save do jogador.

const SHORT_MINUTES := 6.0


func _store(ruleset: String = "res://rulesets/dev.json") -> GameStore:
	var backend := MemoryBackend.new()
	var reg := Fixtures.registry(ruleset)
	var world := World.new()
	world.date = "2026-10-10"
	var res := OnboardingService.create_club(world, {"name": "Vila Nova FC", "sigla": "VIL"}, reg, backend)
	check(bool(res.get("ok", false)), "clube criado")
	var g := GameStore.new()
	g.bind(backend, reg)
	g.reload()
	return g


func _play(g: GameStore, kind: String, opponent: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var prep := g.prepare_match(kind, opponent, opts)
	check(bool(prep.get("ok", false)), "partida preparada: %s" % str(prep.get("errors", [])))
	if not bool(prep.get("ok", false)):
		return {}
	var setup: MatchSetup = prep.setup
	setup.match_minutes = SHORT_MINUTES
	var engine := MatchEngine.create(setup, g.registry)
	var result := engine.run_to_end()
	engine.dispose()
	return g.finish_match(result)


func _done(g: GameStore) -> void:
	g.registry.dispose()
	g.free()


func test_le_o_clube_e_monta_o_time() -> void:
	var g := _store()
	check(g.has_club(), "tem clube")
	check_eq(g.squad().size(), 11, "11 atletas")
	var ts := g.team_setup()
	check_eq(ts.lineup.size(), 11, "11 titulares no TeamSetup")
	check_eq(ts.slots.size(), 11, "formação com 11 vagas")
	check_eq(ts.shirt_of(ts.lineup[0], 0), 1, "goleiro com a camisa 1")
	check(g.lineup_problems().is_empty(), "escalação inicial válida: %s" % str(g.lineup_problems()))
	var s := GameStore.strength(g.starters())
	check(int(s.ovr) > 0 and int(s.def) > 0 and int(s.mid) > 0 and int(s.fwd) > 0, "força por setor")
	_done(g)


func test_tatica_vira_chaves_das_mecanicas() -> void:
	var t := GameStore._match_tactics({"mentality": "ofensivo", "penalty_taker_id": "a9", "captain_id": "a2",
		"freekick_taker_id": "a9", "sub_rule_stamina": 35})
	check_eq(t.mentality, "ofensivo", "mentalidade")
	check_eq(t.penalty_order, ["a9", "a2"], "cobradores sem repetir")
	check_eq(t.auto_subs.size(), 1, "regra de cansaço")
	check_near(float(t.auto_subs[0].value), 0.35, 0.0001, "35% -> 0.35")
	check(GameStore._match_tactics({"sub_rule_stamina": 0}).auto_subs.is_empty(), "0 = desligada")


func test_adversarios_pareados_pela_forca() -> void:
	var g := _store()
	var mine := g.team_ovr()
	var opps := g.friendly_opponents()
	check_eq(opps.size(), GameStore.FRIENDLY_OFFERS.size(), "um adversário por oferta")
	for o in opps:
		check(o.snapshot is Dictionary and not o.key.is_empty(), "snapshot e chave")
		check_eq(g.opponent(o.key).id, o.id, "acha pela chave")
	var deltas: Array = opps.map(func(o): return int(o.strength.ovr) - mine)
	check(deltas.any(func(d): return absi(d) <= 2), "um parelho (deltas %s)" % str(deltas))
	check(deltas.any(func(d): return d <= -3), "um mais fraco (deltas %s)" % str(deltas))
	check(absi(int(g.official_opponent().strength.ovr) - mine) <= 2, "oficial pareado pela força")
	_done(g)


func test_amistoso_registra_uma_vez_e_nao_envelhece() -> void:
	var g := _store()
	var a: Athlete = g.squad()[0]
	var age_before := g.age(a)
	var rep := _play(g, GameStore.KIND_FRIENDLY, g.friendly_opponents()[0])
	check_eq(str(rep.kind), "friendly", "tipo no relatório")
	check_eq(int(rep.career.days_gained), 0, "amistoso não dá dia de carreira")
	check_near(g.age(a), age_before, 0.0001, "idade igual")
	var backend: MemoryBackend = g.backend
	check_eq(backend.results.size(), 1, "resultado enviado ao backend")
	var again := g.finish_match(rep.result)
	check_eq(backend.results.size(), 1, "registrar de novo não duplica")
	check_eq(again, rep, "devolve o mesmo relatório")
	var hist := g.recent_results()
	check_eq(hist.size(), 1, "histórico com 1 partida")
	check_eq(int(hist[0].goals_for), int(rep.result.home.goals), "placar do ponto de vista do clube")
	check(not backend.saved.is_empty(), "mundo gravado")
	_done(g)


func test_oficial_conta_dia_e_trava_ate_amanha() -> void:
	var g := _store()
	var st := g.official_status()
	check(bool(st.enabled) and bool(st.available), "oficial disponível")
	check(int(st.next_in) > 0 and int(st.next_in) <= GameStore.SECONDS_PER_DAY, "contagem até a virada do dia")
	var rep := _play(g, GameStore.KIND_OFFICIAL, g.official_opponent())
	var participants: Array = rep.result.home.participants
	check_eq(int(rep.career.days_gained), participants.size(), "1 dia por atleta que entrou em campo")
	st = g.official_status()
	check(not bool(st.available), "oficial de hoje já jogado")
	check(not st.today_result.is_empty(), "resultado de hoje no status")
	var blocked := g.prepare_match(GameStore.KIND_OFFICIAL, g.official_opponent())
	check(not bool(blocked.ok), "segundo oficial no mesmo dia é recusado")
	(g.backend as MemoryBackend).advance_days(1)
	check(bool(g.official_status().available), "amanhã libera")
	_done(g)


func test_oficial_sem_a_mecanica() -> void:
	var g := _store("res://rulesets/default.json")
	check(not bool(g.official_status().enabled), "default: sem oficial diário")
	var res := g.prepare_match(GameStore.KIND_OFFICIAL, g.official_opponent())
	check(not bool(res.ok), "oficial recusado sem a mecânica")
	check_eq(g.squad().size(), 11, "fallback do onboarding cria os 11 atletas")
	_done(g)


func test_escalacao_invalida_bloqueia() -> void:
	var g := _store()
	var t := g.tactics()
	var starters: Array = t.starting_11
	starters[3] = ""
	t.starting_11 = starters
	g.save_tactics(t)
	check(not g.lineup_problems().is_empty(), "vaga vazia aparece como problema")
	var res := g.prepare_match(GameStore.KIND_FRIENDLY, g.friendly_opponents()[0])
	check(not bool(res.ok), "partida recusada")
	check(not g.has_pending_match(), "nada pendente")
	_done(g)


func test_estreia_avanca_so_para_frente() -> void:
	var g := _store()
	check_eq(g.onboarding_stage(), GameStore.STAGE_DONE, "save sem a chave conta como concluído")
	g.start_onboarding()
	check_eq(g.onboarding_stage(), GameStore.STAGE_STARTER, "começa no pacote inicial")
	g.advance_onboarding(GameStore.STAGE_DEBUT)
	g.advance_onboarding(GameStore.STAGE_FIRST_LINEUP)
	check_eq(g.onboarding_stage(), GameStore.STAGE_DEBUT, "não volta etapa")
	_play(g, GameStore.KIND_FRIENDLY, g.friendly_opponents()[0], {"debut": true})
	check_eq(g.onboarding_stage(), GameStore.STAGE_TOUR, "depois da estreia vem o tour")
	g.reload()
	check_eq(g.onboarding_stage(), GameStore.STAGE_TOUR, "etapa salva no mundo")
	_done(g)


func test_resumo_vitoria_empate_derrota() -> void:
	var base := {"kind": "friendly", "date": "2026-10-10", "winner": "home",
		"home": {"club_id": "eu", "name": "Eu", "goals": 2}, "away": {"club_id": "ele", "name": "Ele", "goals": 1}}
	check_eq(GameStore.summarize(base, "eu").outcome, "win", "vitória em casa")
	check_eq(GameStore.summarize(base, "ele").outcome, "loss", "derrota fora")
	var tie := base.duplicate(true)
	tie.winner = ""
	tie.away.goals = 2
	check_eq(GameStore.summarize(tie, "eu").outcome, "draw", "empate")
	var pens := tie.duplicate(true)
	pens.winner = "away"
	pens["extra"] = {"shootout": {"home": 3, "away": 4}}
	var s := GameStore.summarize(pens, "eu")
	check_eq(s.outcome, "loss", "pênaltis decidem")
	check_eq(s.shootout, [3, 4], "placar dos pênaltis do ponto de vista do clube")


func test_fases_da_carreira() -> void:
	var g := _store()
	check_eq(g.career_phase(17.0), "promessa", "17")
	check_eq(g.career_phase(29.0), "auge", "29")
	check_eq(g.career_phase(36.0), "veterano", "36")
	check_eq(g.career_phase(40.0), "declinio", "40")
	var c := g.career(g.squad()[0])
	check_eq(int(c.days_per_year), 25, "25 dias por ano")
	check(bool(c.aging), "career_aging ligada")
	_done(g)


## Elenco de emergência (gerador desligado, regras de produção) não tem rosto no DNA: a carta e a
## miniatura usam um rosto de vitrine fixo pelo id, para nenhuma tela mostrar carta vazia.
func test_atleta_sem_rosto_ganha_rosto_de_vitrine_fixo() -> void:
	var a := Athlete.new()
	a.id = "ath_init_meu_clube_6"
	a.name = "Volante"
	a.position = "MID"
	var face: Dictionary = GameStore.card_for(a)["face"]
	check(not face.is_empty(), "carta de atleta sem rosto ganha rosto")
	check(GameStore.face_for(a) == face, "o mesmo atleta sempre tem o mesmo rosto")
	check(not a.dna.has("face"), "o rosto de vitrine não é gravado no DNA")
	var b := Athlete.new()
	b.id = "ath_init_meu_clube_7"
	b.position = "MID"
	check(GameStore.face_for(b) != face, "atletas diferentes têm rostos diferentes")
