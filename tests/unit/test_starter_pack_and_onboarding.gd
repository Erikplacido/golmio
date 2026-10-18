extends TestCase
## Testes para pacote starter (11 atletas garantidos) e OnboardingService.


## Mundo em memória: o teste não pode tocar no save do jogador (user://save/world.json).
class MemBackend extends LocalBackend:
	var saved: Dictionary = {}

	func load_world() -> Dictionary:
		return saved

	func save_world(data: Dictionary) -> bool:
		saved = data.duplicate(true)
		return true


func test_starter_pack_existe_e_gera_11_posicoes() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	check(reg.enabled_ids().has("packs"), "packs habilitado")
	check(reg.enabled_ids().has("athlete_generator"), "athlete_generator habilitado")

	var world := World.new()
	world.date = "2026-09-28"
	var club := Club.new()
	club.id = "meu_clube"
	world.add_club(club)

	# Testar abertura atômica do pacote starter
	var res: Variant = reg.bus.decide("packs.grant_starter", {
		"world": world,
		"club": club,
		"seed": 424242,
	})
	check(res is Dictionary, "packs.grant_starter respondeu")
	check(bool(res.get("ok", false)), "starter pack aberto com sucesso")

	var athletes: Array = res.get("athletes", [])
	check_eq(athletes.size(), 11, "starter pack concede exatamente 11 atletas")
	check_eq(club.athlete_ids.size(), 11, "clube recebeu os 11 atletas no elenco")

	# Contar posições
	var gks := 0
	var defs := 0
	var mids := 0
	var fwds := 0
	for a in athletes:
		match a.position:
			"GK": gks += 1
			"DEF": defs += 1
			"MID": mids += 1
			"FWD": fwds += 1

	check_eq(gks, 1, "exatamente 1 GK garantido")
	check_eq(defs, 4, "exatamente 4 DEF garantidos")
	check_eq(mids, 3, "exatamente 3 MID garantidos")
	check_eq(fwds, 3, "exatamente 3 FWD garantidos")


func test_onboarding_service_criacao_completa() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var world := World.new()
	world.date = "2026-09-28"
	var backend := MemBackend.new()   # LocalBackend gravaria por cima do save real em user://

	var club_data := {
		"name": "Esporte Clube Estrela",
		"sigla": "ECE",
		"club_identity": {
			"kit": {
				"colors": ["#16a34a", "#ffffff", "#000000"],
				"pattern": "listras_verticais",
			}
		}
	}

	var res := OnboardingService.create_club(world, club_data, reg, backend)
	check(bool(res.get("ok", false)), "OnboardingService criou o clube com sucesso")

	var club: Club = res.get("club")
	check(club != null, "clube retornado")
	check_eq(club.name, "Esporte Clube Estrela", "nome do clube salvo")
	check_eq(club.short_name, "ECE", "sigla do clube salva")
	check_eq(club.athlete_ids.size(), 11, "11 atletas no elenco do clube")

	var athletes: Array = res.get("athletes", [])
	check_eq(athletes.size(), 11, "11 atletas retornados")

	# Validar tática inicial configurada no clube
	check(club.ext.has("tactics"), "tática salva no ext do clube")
	var tac: Dictionary = club.ext["tactics"]
	check_eq(str(tac.get("formation", "")), "4-3-3", "formação padrão 4-3-3")
	var st11: Array = tac.get("starting_11", [])
	check_eq(st11.size(), 11, "11 titulares na tática")

	# Primeiro titular deve ser o goleiro
	var first_player: Athlete = world.athletes.get(st11[0])
	check(first_player != null, "primeiro titular existe")
	check_eq(first_player.position, "GK", "primeiro titular é o goleiro")


func test_elenco_de_emergencia_ganha_rosto_ao_ligar_o_gerador() -> void:
	# Clube criado sem packs nem gerador (ruleset padrão): 11 atletas provisórios, sem rosto.
	var backend := MemBackend.new()
	var world := World.new()
	world.date = "2026-09-28"
	var res := OnboardingService.create_club(world, {"name": "Vila Teste", "sigla": "VLT"}, Fixtures.registry(), backend)
	check(bool(res.ok), "clube criado")
	var club: Club = res.club
	var lineup: Array = (club.ext["tactics"]["starting_11"] as Array).duplicate()
	var ids := club.athlete_ids.duplicate()
	var positions := {}
	for aid in ids:
		var a: Athlete = world.athletes[aid]
		check(aid.begins_with(OnboardingService.PLACEHOLDER_PREFIX), "provisório: %s" % aid)
		check(not (a.dna.get("face") is Dictionary and not (a.dna.face as Dictionary).is_empty()), "sem rosto")
		positions[aid] = a.position
	var old_name: String = world.athletes[ids[0]].name

	# Com o gerador ligado, o conserto dá identidade gerada e mantém id, posição e escalação.
	var dev := Fixtures.registry("res://rulesets/dev.json")
	check_eq(OnboardingService.repair_placeholder_athletes(world, dev, backend), 11, "11 consertados")
	for aid in ids:
		var a: Athlete = world.athletes[aid]
		check(not (a.dna.get("face", {}) as Dictionary).is_empty(), "%s ganhou rosto" % aid)
		check_eq(a.position, positions[aid], "posição mantida")
	check(world.athletes[ids[0]].name != old_name, "nome de gente, não de posição")
	check_eq(club.athlete_ids, ids, "mesmo elenco")
	check_eq(club.ext["tactics"]["starting_11"], lineup, "mesma escalação")
	check_eq(OnboardingService.repair_placeholder_athletes(world, dev, backend), 0, "só uma vez")
	check_eq(OnboardingService.repair_placeholder_athletes(world, Fixtures.registry(), backend), 0, "sem gerador: não mexe")
