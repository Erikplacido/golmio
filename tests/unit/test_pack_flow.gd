extends TestCase
## Integração de ponta a ponta com o ruleset de desenvolvimento (rulesets/dev.json, que liga
## athlete_generator e packs por cima das regras de produção): mundo novo -> concede os três tipos
## de pacote (comum, raro, gol) com sementes fixas -> abre todos -> 10 atletas únicos no clube ->
## salva o mundo em JSON e recarrega (SaveMigrator + World.from_dict) -> DNA íntegro e dna_hash
## idêntico; nome e atributos atuais ficam fora do DNA; career_aging envelhece esses atletas a
## partir dos 17 anos, inclusive depois de uma partida oficial de verdade no motor.

const DEV_RULESET := "res://rulesets/dev.json"
const GEN := "athlete_generator"
const PACKS := "packs"
const AGING := "career_aging"
const GRANT := "packs.grant"
const OPEN := "packs.open"
const INVENTORY := "packs.inventory"
const VALIDATE := "athlete_generator.validate"
const DATE := "2026-09-27"
const CLUB_ID := "clube_fluxo"
## Sementes fixas (o servidor usaria Backend.new_seed()); a ordem é a da concessão.
const PACK_SEEDS := [["comum", 1001], ["raro", 2002], ["gol", 3003]]
## tipo -> atletas do pacote (packs.default_params).
const ATHLETES_PER_TYPE := {"comum": 1, "raro": 3, "gol": 6}
const TOTAL_ATHLETES := 10
const TIER_ORDER := ["bronze", "prata", "ouro", "diamante", "deus"]
const HASH_FIELDS := ["face_hash", "attributes_hash", "dna_hash"]
const MATCH_MINUTES := 4.0
const MATCH_SEED := 77
const DAYS_PER_YEAR := 25


# --- apoio -------------------------------------------------------------------------------------

## Mundo novo com um clube vazio, três pacotes concedidos e abertos. Devolve
## {world, club, packs: Array (respostas de packs.open, na ordem de PACK_SEEDS), athletes: Array}.
func _flow(reg: MechanicRegistry) -> Dictionary:
	var world := World.new()
	world.date = DATE
	var club := Club.new()
	club.id = CLUB_ID
	club.name = "Clube do Fluxo"
	club.short_name = "FLX"
	world.add_club(club)
	var opened: Array = []
	var athletes: Array = []
	for entry in PACK_SEEDS:
		var type_id: String = entry[0]
		var g: Variant = reg.bus.decide(GRANT, {"world": world, "club": club, "type": type_id,
			"seed": int(entry[1]), "source": "teste_fluxo"})
		check(g is Dictionary and bool(g.get("ok", false)), "grant %s: %s" % [type_id, str(g)])
		if not (g is Dictionary and bool(g.get("ok", false))):
			continue
		check_eq(str(g.pack.status), "sealed", "pacote %s nasce lacrado" % type_id)
		var o: Variant = reg.bus.decide(OPEN, {"world": world, "club": club, "pack_id": str(g.pack.id)})
		check(o is Dictionary and bool(o.get("ok", false)), "open %s: %s" % [type_id, str(o)])
		if not (o is Dictionary and bool(o.get("ok", false))):
			continue
		check_eq(o.athletes.size(), int(ATHLETES_PER_TYPE[type_id]), "atletas do pacote %s" % type_id)
		opened.append(o)
		athletes.append_array(o.athletes)
	return {"world": world, "club": club, "packs": opened, "athletes": athletes}


func _validate(reg: MechanicRegistry, world: World, a: Athlete) -> Dictionary:
	var v: Variant = reg.bus.decide(VALIDATE, {"world": world, "athlete": a})
	check(v is Dictionary, "athlete_generator.validate responde")
	return v if v is Dictionary else {"ok": false, "errors": ["sem resposta"]}


## Ida e volta pelo formato de save: JSON em texto, migração e World.from_dict.
func _save_load(reg: MechanicRegistry, world: World) -> World:
	var text := JSON.stringify(world.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	check(parsed is Dictionary, "save é JSON válido")
	var data: Dictionary = parsed if parsed is Dictionary else {}
	return World.from_dict(SaveMigrator.migrate(data, reg))


func _tier_rank(t: String) -> int:
	return TIER_ORDER.find(t)


# --- testes ------------------------------------------------------------------------------------

func test_dev_liga_gerador_e_pacotes() -> void:
	var reg := Fixtures.registry(DEV_RULESET)
	for mid in [GEN, PACKS, AGING]:
		check(reg.is_enabled(mid), "dev.json liga %s" % mid)
	var prod := Fixtures.registry()
	check(not prod.is_enabled(GEN) and not prod.is_enabled(PACKS),
		"default.json (produção) continua sem as mecânicas experimentais")
	prod.dispose()
	reg.dispose()


func test_tres_pacotes_dez_atletas_unicos() -> void:
	var reg := Fixtures.registry(DEV_RULESET)
	var f := _flow(reg)
	var world: World = f.world
	var club: Club = f.club
	var athletes: Array = f.athletes
	check_eq(f.packs.size(), 3, "os três pacotes abriram")
	check_eq(athletes.size(), TOTAL_ATHLETES, "1 + 3 + 6 atletas")
	check_eq(club.athlete_ids.size(), TOTAL_ATHLETES, "todos entregues ao elenco")
	check_eq(world.athletes.size(), TOTAL_ATHLETES, "todos no mundo")

	var seen := {"id": {}, "face_hash": {}, "attributes_hash": {}, "dna_hash": {}}
	for a in athletes:
		check(AthleteDna.is_uuid_v4(a.id), "id UUID v4: %s" % a.id)
		check(club.athlete_ids.has(a.id), "%s no elenco" % a.id)
		seen.id[a.id] = true
		for k in HASH_FIELDS:
			seen[k][str(a.dna.get(k, ""))] = true
		check(AthleteDna.verify(a.dna).is_empty(), "DNA íntegro: %s" % str(AthleteDna.verify(a.dna)))
		check_eq(int(a.dna.initial_age), 17, "nasce com 17 anos")
		check(_tier_rank(a.tier()) >= 0, "tier conhecido: %s" % a.tier())
		check_eq(str(a.dna.origin.source), "pack", "origem = pacote")
		check_eq(str(a.dna.origin.club_id), CLUB_ID, "origem registra o clube")
		check_eq(str(a.dna.origin.date), DATE, "origem registra a data")
		check_eq(a.name, str(a.dna.birth_name), "nome de exibição começa igual ao de nascimento")
		check_eq(a.club_history.size(), 1, "uma entrada de histórico")
		if a.club_history.size() == 1:
			check_eq(a.club_history[0], {"club_id": CLUB_ID, "from": DATE, "to": "", "via": "pack"})
		for k in AthleteDna.BASE_ATTRIBUTE_IDS:
			check(a.attributes.has(k), "%s tem %s" % [a.id, k])
			check_near(a.attr(k), float(a.dna.base_attributes[k]), 0.0001, "atual = base no nascimento")
		var v := _validate(reg, world, a)
		check(bool(v.ok), "validate: %s" % str(v.errors))
	for k in seen:
		check_eq(seen[k].size(), TOTAL_ATHLETES, "%s únicos" % k)
	var registry_data: Dictionary = world.ext.get(GEN, {})
	for rk in ["face_hashes", "attribute_hashes", "dna_hashes"]:
		check_eq((registry_data.get(rk, {}) as Dictionary).size(), TOTAL_ATHLETES, "registro %s" % rk)

	# Garantias dos tipos: raro >= prata, gol >= ouro.
	var min_by_type := {"raro": "prata", "gol": "ouro"}
	for o in f.packs:
		var type_id := str(o.pack.type)
		check_eq(str(o.pack.status), "opened", "pacote %s aberto" % type_id)
		if min_by_type.has(type_id):
			var best := -1
			for a in o.athletes:
				best = maxi(best, _tier_rank(a.tier()))
			check(best >= _tier_rank(min_by_type[type_id]), "garantia do %s" % type_id)
	var inv: Variant = reg.bus.decide(INVENTORY, {"club": club})
	check(inv is Array and inv.size() == 3, "inventário com os 3 pacotes")

	# Sementes fixas reproduzem o lote inteiro (outro registro, outro mundo).
	var reg2 := Fixtures.registry(DEV_RULESET)
	var f2 := _flow(reg2)
	var ids_a: Array = athletes.map(func(a: Athlete) -> String: return a.id + ":" + a.dna_hash())
	var ids_b: Array = f2.athletes.map(func(a: Athlete) -> String: return a.id + ":" + a.dna_hash())
	check_eq(ids_b, ids_a, "mesmas sementes -> mesmos atletas")
	reg2.dispose()
	reg.dispose()


func test_save_e_load_preservam_o_dna() -> void:
	var reg := Fixtures.registry(DEV_RULESET)
	var f := _flow(reg)
	var world: World = f.world
	var w2 := _save_load(reg, world)
	check_eq(w2.athletes.size(), TOTAL_ATHLETES, "atletas recarregados")
	var c2: Club = w2.clubs.get(CLUB_ID)
	check(c2 != null, "clube recarregado")
	if c2 != null:
		check_eq(c2.athlete_ids, (f.club as Club).athlete_ids, "elenco recarregado")
	for a in f.athletes:
		var b: Athlete = w2.athletes.get(a.id)
		check(b != null, "atleta %s recarregado" % a.id)
		if b == null:
			continue
		var errors := AthleteDna.verify(b.dna)
		check(errors.is_empty(), "DNA íntegro após o load: %s" % str(errors))
		check_eq(b.dna_hash(), a.dna_hash(), "dna_hash gravado idêntico")
		check_eq(AthleteDna.compute_hashes(b.dna), AthleteDna.compute_hashes(a.dna),
			"hashes recalculados idênticos (floats do JSON viram int)")
		check_eq(AthleteDna.canonical_json(b.dna), AthleteDna.canonical_json(a.dna), "DNA canônico idêntico")
		check_eq(b.tier(), a.tier())
		check_eq(b.club_history, a.club_history, "histórico de clubes recarregado")
		var v := _validate(reg, w2, b)
		check(bool(v.ok), "validate após o load: %s" % str(v.errors))
	# Uma segunda ida e volta não muda nada (o save é estável).
	var w3 := _save_load(reg, w2)
	check_eq(JSON.stringify(w3.to_dict(), "", true), JSON.stringify(w2.to_dict(), "", true), "save estável")
	reg.dispose()


func test_nome_e_atributos_atuais_nao_mudam_o_dna() -> void:
	var reg := Fixtures.registry(DEV_RULESET)
	var f := _flow(reg)
	var world: World = f.world
	var a: Athlete = f.athletes[0]
	var before := a.dna_hash()
	var birth_name := str(a.dna.birth_name)
	var base_before: Dictionary = a.dna.base_attributes.duplicate()
	a.rename("Apelido Novo")
	a.attributes["pace"] = clampf(a.attr("pace") + 7.0, 1.0, 99.0)
	a.attributes["finishing"] = clampf(a.attr("finishing") - 3.0, 1.0, 99.0)
	a.club_history.append({"club_id": "outro", "from": "2026-10-01", "to": "", "via": "transfer"})
	check_eq(a.name, "Apelido Novo", "rename troca o nome de exibição")
	check_eq(str(a.dna.birth_name), birth_name, "nome de nascimento não muda")
	check_eq(a.dna.base_attributes, base_before, "atributos base não mudam")
	check_eq(a.dna_hash(), before, "dna_hash gravado não muda")
	check_eq(AthleteDna.dna_hash(a.dna), before, "dna_hash recalculado não muda")
	check(AthleteDna.verify(a.dna).is_empty(), "DNA segue íntegro")
	check(bool(_validate(reg, world, a).ok), "validate segue ok")
	var w2 := _save_load(reg, world)
	var b: Athlete = w2.athletes.get(a.id)
	check(b != null)
	if b != null:
		check_eq(b.name, "Apelido Novo", "nome novo persiste")
		check_eq(b.dna_hash(), before, "dna_hash persiste")
		check_eq(AthleteDna.dna_hash(b.dna), before)
		check_near(b.attr("pace"), a.attr("pace"), 0.0001, "atributo atual persiste")
		check_eq(b.club_history.size(), 2, "histórico persiste")
	reg.dispose()


func test_career_aging_envelhece_atletas_gerados() -> void:
	var reg := Fixtures.registry(DEV_RULESET)
	var f := _flow(reg)
	var world: World = f.world
	var athletes: Array = f.athletes
	for a in athletes:
		check_near(MatchReporter.athlete_age(reg, a), 17.0, 0.0001, "17 anos no nascimento")

	# Partida oficial de verdade: os 10 gerados + 1 atleta de demonstração (fora do mundo).
	var setup := DemoData.match_setup(MATCH_SEED, MATCH_MINUTES, "official")
	for i in athletes.size():
		setup.home.lineup[i] = athletes[i]
	check(setup.home.validate(reg.ruleset, reg.bus).is_empty(), "escalação com atletas gerados é válida")
	var engine := MatchEngine.create(setup, reg)
	var result := engine.run_to_end()
	check(engine.is_finished(), "partida terminou")
	engine.dispose()
	for a in athletes:
		check(result.home.participants.has(a.id), "%s entrou em campo" % a.id)
	MatchReporter.report(reg, world, result, "2026-09-28")
	for a in athletes:
		check_eq(int(a.ext.get(AGING, {}).get("days", 0)), 1, "1 dia de carreira pela partida oficial")
		check_near(MatchReporter.athlete_age(reg, a), 17.0 + 1.0 / DAYS_PER_YEAR, 0.0001)

	# Mais 24 jogos oficiais em datas diferentes: 18 anos e o primeiro +1 do crescimento.
	var ids: Array = athletes.map(func(a: Athlete) -> String: return a.id)
	for d in DAYS_PER_YEAR - 1:
		var r := {"kind": "official", "home": {"participants": ids}, "away": {"participants": []}}
		MatchReporter.report(reg, world, r, "dia-%03d" % d)
	for a in athletes:
		var hash_before := str(a.dna.dna_hash)
		check_near(MatchReporter.athlete_age(reg, a), 18.0, 0.0001, "18 anos depois de 25 jogos oficiais")
		for k in AthleteDna.BASE_ATTRIBUTE_IDS:
			var base := float(a.dna.base_attributes[k])
			check_near(a.attr(k), minf(base + 1.0, 99.0), 0.0001, "%s: +1 aos 18" % k)
		check_eq(AthleteDna.dna_hash(a.dna), hash_before, "envelhecer não muda o DNA")
		check(AthleteDna.verify(a.dna).is_empty(), "DNA íntegro depois de envelhecer")
		check(a.is_active())
	# A idade sobrevive ao save.
	var w2 := _save_load(reg, world)
	for a in athletes:
		check_near(MatchReporter.athlete_age(reg, w2.athletes[a.id]), 18.0, 0.0001, "idade persiste no save")
	reg.dispose()
