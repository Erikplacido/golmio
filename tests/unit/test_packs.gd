extends TestCase
## packs: concessão (id determinístico, lacrado, tipo desconhecido), abertura de cada tipo
## (1/3/6 atletas + 1/2/3 slots reservados, cartas, club_history, dna.origin), garantia de tier,
## atomicidade (elenco cheio, erro do gerador, gerador indisponível), já aberto, inexistente,
## "guardar" com save/load, packs.collectibles, packs.opened, unicidade entre pacotes,
## dependência do athlete_generator e entropia do LocalBackend.

const MID := "packs"
const GEN := "athlete_generator"
const GRANT := "packs.grant"
const OPEN := "packs.open"
const INVENTORY := "packs.inventory"
const TYPES := "packs.types"
const COLLECTIBLES := "packs.collectibles"
const OPENED := "packs.opened"
const VALIDATE := "athlete_generator.validate"
const DATE := "2026-09-27"
const LATER := "2026-10-15"
const TIER_ORDER := ["bronze", "prata", "ouro", "diamante", "deus"]
## tipo -> [atletas, slots colecionáveis]
const EXPECTED := {"comum": [1, 1], "raro": [3, 2], "gol": [6, 3]}
const GUARANTEE_SAMPLE := 100
const UNIQUE_SAMPLE := 10


# --- apoio -------------------------------------------------------------------------------------

func _reg(params: Dictionary = {}) -> MechanicRegistry:
	return Fixtures.registry_with([GEN, MID], params)


func _world(date: String = DATE) -> World:
	var w := World.new()
	w.date = date
	return w


## Clube no mundo, com `veterans` atletas fictícios no elenco (só ids, para ocupar vagas).
func _club(world: World, cid: String = "clube_a", veterans: int = 0) -> Club:
	var c := Club.new()
	c.id = cid
	c.name = cid
	for i in veterans:
		c.athlete_ids.append("%s_veterano_%d" % [cid, i])
	world.add_club(c)
	return c


func _grant(reg: MechanicRegistry, world: World, club: Club, type_id: String, p_seed: Variant,
		source: String = "teste") -> Dictionary:
	var res: Variant = reg.bus.decide(GRANT, {"world": world, "club": club, "type": type_id, "seed": p_seed, "source": source})
	check(res is Dictionary, "packs.grant precisa responder com a mecânica ligada")
	return res if res is Dictionary else {"ok": false, "error": "sem resposta"}


func _open(reg: MechanicRegistry, world: World, club: Club, pack_id: String) -> Dictionary:
	var res: Variant = reg.bus.decide(OPEN, {"world": world, "club": club, "pack_id": pack_id})
	check(res is Dictionary, "packs.open precisa responder com a mecânica ligada")
	return res if res is Dictionary else {"ok": false, "error": "sem resposta", "needed_slots": 0}


## Concede e abre; falha o teste se algo der errado.
func _grant_open(reg: MechanicRegistry, world: World, club: Club, type_id: String, p_seed: int) -> Dictionary:
	var g := _grant(reg, world, club, type_id, p_seed)
	check(bool(g.get("ok", false)), "grant %s: %s" % [type_id, str(g.get("detail", ""))])
	if not bool(g.get("ok", false)):
		return g
	var o := _open(reg, world, club, str(g.pack.id))
	check(bool(o.get("ok", false)), "open %s: %s %s" % [type_id, str(o.get("error", "")), str(o.get("detail", ""))])
	return o


func _inventory(reg: MechanicRegistry, club: Club) -> Array:
	var inv: Variant = reg.bus.decide(INVENTORY, {"club": club})
	check(inv is Array, "packs.inventory devolve Array")
	return inv if inv is Array else []


## Tudo que uma abertura pode mudar.
func _snapshot(world: World, club: Club) -> Dictionary:
	var ath: Array = world.athletes.keys()
	ath.sort()
	return {"athletes": ath, "world_ext": world.ext.duplicate(true), "club": club.to_dict()}


func _tiers_of(pack: Dictionary) -> Array:
	var out: Array = []
	for c in pack.get("contents", []):
		if str(c.get("kind", "")) == "athlete":
			out.append(str(c.tier))
	return out


func _count_at_least(tiers: Array, min_tier: String) -> int:
	var n := 0
	for t in tiers:
		if TIER_ORDER.find(t) >= TIER_ORDER.find(min_tier):
			n += 1
	return n


# --- metadados ---------------------------------------------------------------------------------

func test_metadados_e_hooks() -> void:
	var reg := _reg()
	var m := reg.get_mechanic(MID)
	check(m != null, "packs descoberta e ligada junto do gerador")
	if m == null:
		reg.dispose()
		return
	check_eq(m.layer, "meta")
	check_eq(m.stage, "experimental")
	check_eq(m.enabled_by_default, false, "experimental nasce desligada")
	check_eq(m.depends_on, [GEN], "depende do athlete_generator")
	check_eq(m.version, 1)
	check_eq(m.data_version, 1)
	for h in [GRANT, OPEN, INVENTORY, COLLECTIBLES, OPENED]:
		check(m.provides_hooks.has(h), "provides_hooks declara %s" % h)
	for h in [GRANT, OPEN, INVENTORY, TYPES]:
		check(reg.bus.has_handlers(h), "install registra %s" % h)
	for t in EXPECTED:
		check_eq(int(m.params.types[t].athletes), int(EXPECTED[t][0]), "%s: atletas" % t)
		check_eq(int(m.params.types[t].collectible_slots), int(EXPECTED[t][1]), "%s: slots colecionáveis" % t)
	check_eq(m.params.tier_order, TIER_ORDER)
	check_eq(m.params.require_free_slots, true)
	var types: Variant = reg.bus.decide(TYPES, {})
	check(types is Dictionary and types.types.has("gol") and types.tier_order == TIER_ORDER, "packs.types publica tipos e ordem")
	if types is Dictionary:
		types.types.gol.athletes = 99
		check_eq(int(m.param("types").gol.athletes), 6, "packs.types devolve cópia")
	var prod := Fixtures.registry()
	check(not prod.is_enabled(MID), "desligada no ruleset padrão")
	prod.dispose()
	reg.dispose()


func test_sem_gerador_packs_fica_desligada() -> void:
	var reg := Fixtures.registry_with([MID])
	check(not reg.is_enabled(MID), "sem athlete_generator a packs cai pela dependência")
	check(Array(reg.warnings).any(func(w: String) -> bool: return MID in w and GEN in w), "registro avisa a dependência")
	check_eq(reg.bus.decide(GRANT, {"world": _world(), "club": Club.new(), "type": "comum", "seed": 1}), null,
		"hook de mecânica desligada não responde")
	reg.dispose()


# --- grant -------------------------------------------------------------------------------------

func test_grant_lacrado_com_id_deterministico() -> void:
	var reg := _reg()
	var world := _world()
	var club := _club(world)
	var res := _grant(reg, world, club, "gol", 777, "recompensa")
	check(bool(res.get("ok", false)), "grant ok")
	var pack: Dictionary = res.get("pack", {})
	check_eq(str(pack.get("id")), AthleteDna.uuid_v4_from_seed(777), "id = uuid_v4_from_seed(seed)")
	check(AthleteDna.is_uuid_v4(str(pack.get("id"))), "id é UUID v4")
	check_eq(pack.get("type"), "gol")
	check_eq(pack.get("seed"), 777)
	check_eq(pack.get("status"), "sealed")
	check_eq(pack.get("source"), "recompensa")
	check_eq(pack.get("granted_on"), DATE)
	check_eq(pack.get("opened_on"), "")
	check_eq(pack.get("contents"), [])

	var inv := _inventory(reg, club)
	check_eq(inv.size(), 1, "pacote no inventário")
	check(not inv.is_empty() and inv[0] == pack, "inventário igual ao pacote devolvido")
	inv[0]["status"] = "opened"
	check_eq(str(_inventory(reg, club)[0].status), "sealed", "inventory devolve cópia")
	check_eq(str(club.ext[MID].inventory[0].status), "sealed", "dados em club.ext[\"packs\"].inventory")

	# Mesma semente em outro mundo -> mesmo id.
	var w2 := _world()
	var other := _grant(reg, w2, _club(w2, "clube_b"), "gol", 777)
	check_eq(str(other.get("pack", {}).get("id")), str(pack.get("id")), "id depende só da semente")
	# Mesma semente no mesmo clube: o id colide e continua o fluxo.
	var dup := _grant(reg, world, club, "comum", 777)
	check(bool(dup.get("ok", false)) and str(dup.pack.id) != str(pack.get("id")), "id repetido continua o mesmo fluxo")
	check(AthleteDna.is_uuid_v4(str(dup.get("pack", {}).get("id", ""))), "id alternativo também é UUID v4")
	check_eq(_inventory(reg, club).size(), 2)

	# Erros não mexem no inventário.
	var unknown := _grant(reg, world, club, "mitico", 5)
	check_eq(unknown.get("ok"), false)
	check_eq(unknown.get("error"), "unknown_type")
	check_eq(_grant(reg, world, club, "comum", -1).get("error"), "invalid_payload", "semente negativa")
	check_eq(_grant(reg, world, club, "comum", null).get("error"), "invalid_payload", "sem semente")
	check_eq(_grant(reg, world, club, "comum", AthleteDna.SEED_LIMIT).get("error"), "invalid_payload", "semente >= 2^48")
	check_eq(_inventory(reg, club).size(), 2, "erros não concedem pacote")

	# Ler o inventário de um clube sem pacotes não cria dados nele.
	var empty := Club.new()
	check_eq(_inventory(reg, empty), [], "clube sem pacotes")
	check(not empty.ext.has(MID), "inventory só lê")
	reg.dispose()


# --- open --------------------------------------------------------------------------------------

func test_abrir_cada_tipo_entrega_atletas_e_reserva_slots() -> void:
	var reg := _reg()
	var type_seed := 1000
	for type_id in EXPECTED:
		type_seed += 1
		var n_athletes: int = EXPECTED[type_id][0]
		var n_slots: int = EXPECTED[type_id][1]
		var world := _world()
		var club := _club(world)
		var granted := _grant(reg, world, club, type_id, type_seed)
		var pack_id := str(granted.get("pack", {}).get("id", ""))
		var res := _open(reg, world, club, pack_id)
		check(bool(res.get("ok", false)), "%s abre: %s %s" % [type_id, str(res.get("error", "")), str(res.get("detail", ""))])
		if not bool(res.get("ok", false)):
			continue
		var athletes: Array = res.athletes
		check_eq(athletes.size(), n_athletes, "%s: atletas" % type_id)
		check_eq(world.athletes.size(), n_athletes, "%s: atletas no mundo" % type_id)
		check_eq(club.athlete_ids.size(), n_athletes, "%s: atletas no elenco" % type_id)

		var pack: Dictionary = res.pack
		check_eq(pack.status, "opened", "%s: status" % type_id)
		check_eq(pack.opened_on, DATE, "%s: opened_on" % type_id)
		check_eq(pack.granted_on, DATE)
		check_eq(pack.id, pack_id)
		var contents: Array = pack.contents
		check_eq(contents.size(), n_athletes + n_slots, "%s: contents" % type_id)
		var cards: Array = res.cards
		check_eq(cards.size(), n_athletes + n_slots, "%s: cards" % type_id)
		check_eq(_inventory(reg, club), [pack], "%s: inventário atualizado" % type_id)

		for i in athletes.size():
			var a: Athlete = athletes[i]
			check(world.athletes.get(a.id) == a, "%s: atleta %d no mundo" % [type_id, i])
			check_eq(club.athlete_ids[i], a.id, "%s: ordem do elenco" % type_id)
			check(TIER_ORDER.has(a.tier()), "%s: tier válido" % type_id)
			check_eq(contents[i], {"kind": "athlete", "athlete_id": a.id, "tier": a.tier()}, "%s: contents[%d]" % [type_id, i])
			check_eq(cards[i], {"kind": "athlete", "athlete_id": a.id, "tier": a.tier(), "name": a.name,
				"position": a.position, "nationality": a.nationality, "face": a.dna.face}, "%s: card %d" % [type_id, i])
			check_eq(a.club_history, [{"club_id": club.id, "from": DATE, "to": "", "via": "pack"}], "%s: club_history" % type_id)
			check_eq(a.dna.origin, {"source": "pack", "pack_type": type_id, "pack_id": pack_id,
				"club_id": club.id, "date": DATE}, "%s: dna.origin" % type_id)
			var v: Variant = reg.bus.decide(VALIDATE, {"world": world, "athlete": a})
			check(v is Dictionary and bool(v.ok), "%s: atleta %d válido: %s" % [type_id, i, str(v.get("errors", "")) if v is Dictionary else "?"])
		for s in n_slots:
			check_eq(contents[n_athletes + s], {"kind": "reserved", "slot": s}, "%s: slot reservado %d" % [type_id, s])
			check_eq(cards[n_athletes + s], {"kind": "reserved", "slot": s}, "%s: card reservado %d" % [type_id, s])
		var registry_data: Dictionary = world.ext.get(GEN, {})
		check_eq(registry_data.get("face_hashes", {}).size(), n_athletes, "%s: hashes registrados" % type_id)
	reg.dispose()


func test_garantia_de_tier_em_100_pacotes() -> void:
	var reg := _reg()
	for spec in [["gol", "ouro"], ["raro", "prata"]]:
		var world := _world()
		var failures_before := failures.size()
		var missing := 0
		for i in GUARANTEE_SAMPLE:
			var club := _club(world, "clube_%s_%03d" % [spec[0], i])
			var res := _grant_open(reg, world, club, spec[0], 20000 + i)
			if not bool(res.get("ok", false)):
				break
			if _count_at_least(_tiers_of(res.pack), spec[1]) < 1:
				missing += 1
		check_eq(missing, 0, "%s: todo pacote com pelo menos 1 %s+" % spec)
		check_eq(failures.size(), failures_before, "%s: todos os pacotes abriram" % spec[0])
	reg.dispose()


## Com pesos que nunca sorteiam ouro, a garantia eleva exatamente os ÚLTIMOS sorteados.
func test_garantia_eleva_os_ultimos_sorteados() -> void:
	var base_type := {"label": "Teste", "athletes": 3, "collectible_slots": 0,
		"tier_weights": {"bronze": 90, "prata": 10}}
	var with_g := base_type.duplicate(true)
	with_g["guarantee"] = {"min_tier": "ouro", "count": 2}
	var reg_g := _reg({MID: {"types": {"teste": with_g}}})
	var reg_n := _reg({MID: {"types": {"teste": base_type}}})
	for i in 20:
		var wg := _world()
		var wn := _world()
		var tg := _tiers_of(_grant_open(reg_g, wg, _club(wg), "teste", 300 + i).get("pack", {}))
		var tn := _tiers_of(_grant_open(reg_n, wn, _club(wn), "teste", 300 + i).get("pack", {}))
		check_eq(tn.size(), 3)
		check_eq(tg.size(), 3)
		if tg.size() != 3 or tn.size() != 3:
			continue
		check(["bronze", "prata"].has(tn[0]) and ["bronze", "prata"].has(tn[1]) and ["bronze", "prata"].has(tn[2]),
			"sem garantia só sai bronze/prata: %s" % str(tn))
		check_eq(tg, [tn[0], "ouro", "ouro"], "garantia eleva os 2 últimos, mesmo sorteio base")
	reg_g.dispose()
	reg_n.dispose()


func test_elenco_cheio_nao_muda_nada() -> void:
	var reg := _reg()
	var world := _world()
	var club := _club(world, "clube_a", 28)
	var gol := _grant(reg, world, club, "gol", 42)
	var before := _snapshot(world, club)
	var res := _open(reg, world, club, str(gol.pack.id))
	check_eq(res.get("ok"), false)
	check_eq(res.get("error"), "squad_full")
	check_eq(res.get("needed_slots"), 4, "gol traz 6 e há 2 vagas: liberar 4")
	check_eq(_snapshot(world, club), before, "nada muda: mundo, registro de hashes, elenco e pacote")
	check(world.ext.is_empty(), "registro de unicidade não foi criado")
	check_eq(str(_inventory(reg, club)[0].status), "sealed", "pacote segue lacrado")

	# Com 2 vagas, um comum abre; o gol continua exigindo 6.
	check(bool(_grant_open(reg, world, club, "comum", 43).get("ok", false)), "comum abre com vaga")
	check_eq(club.athlete_ids.size(), 29)
	check_eq(_open(reg, world, club, str(gol.pack.id)).get("needed_slots"), 5)
	# Liberando vagas o mesmo pacote abre.
	for i in 5:
		club.athlete_ids.erase("clube_a_veterano_%d" % i)
	var ok := _open(reg, world, club, str(gol.pack.id))
	check(bool(ok.get("ok", false)), "gol abre depois de liberar vagas")
	check_eq(club.athlete_ids.size(), 30)
	# Elenco no limite: até o comum recusa.
	var last := _grant(reg, world, club, "comum", 44)
	var full := _open(reg, world, club, str(last.pack.id))
	check_eq(full.get("error"), "squad_full")
	check_eq(full.get("needed_slots"), 1)
	reg.dispose()

	# require_free_slots = false: abre mesmo acima do limite.
	var loose := _reg({MID: {"require_free_slots": false}})
	var w2 := _world()
	var c2 := _club(w2, "clube_b", 30)
	check(bool(_grant_open(loose, w2, c2, "raro", 45).get("ok", false)), "sem exigir vagas o pacote abre")
	check_eq(c2.athlete_ids.size(), 33)
	loose.dispose()


func test_elenco_acima_do_limite_pede_todas_as_vagas() -> void:
	# Regressão: com 33/30 (squad_limit reduzido, ruleset antigo sem require_free_slots...) o
	# servidor dizia needed_slots = 1 a cada tentativa. Um comum precisa de 1 vaga livre: faltam 3
	# excedentes + 1 = 4, e liberar exatamente needed_slots abre de primeira.
	var reg := _reg()
	var world := _world()
	var club := _club(world, "clube_a", 33)
	var comum := _grant(reg, world, club, "comum", 46)
	var gol := _grant(reg, world, club, "gol", 47)
	var before := _snapshot(world, club)
	var res := _open(reg, world, club, str(comum.pack.id))
	check_eq(res.get("error"), "squad_full")
	check_eq(res.get("needed_slots"), 4, "33/30 e o comum traz 1: liberar 4")
	check_eq(_open(reg, world, club, str(gol.pack.id)).get("needed_slots"), 9, "33/30 e o gol traz 6: liberar 9")
	check_eq(_snapshot(world, club), before, "nada muda")
	for i in int(res.get("needed_slots", 0)):
		club.athlete_ids.pop_back()
	var ok := _open(reg, world, club, str(comum.pack.id))
	check(bool(ok.get("ok", false)), "liberando needed_slots o pacote abre de primeira: %s" % str(ok.get("error", "")))
	check_eq(club.athlete_ids.size(), 30)
	reg.dispose()


func test_pesos_de_tier_invalidos_sao_recusados() -> void:
	# Regressão: 0.7 virava 1 e 0.24 virava 0 em silêncio (pacote 100% Bronze), e uma soma acima
	# de 2^31 - 1 estourava o sorteio de 32 bits. Pesos de tier são inteiros >= 0.
	var bad := {
		"fracao": {"bronze": 0.7, "prata": 0.24, "ouro": 0.05, "diamante": 0.009, "deus": 0.001},
		"negativo": {"bronze": 10, "prata": -1},
		"texto": {"bronze": "10"},
		"grande": {"bronze": 2147483647, "prata": 1},
	}
	var types := {}
	for k in bad:
		types[k] = {"label": k, "athletes": 1, "collectible_slots": 0, "tier_weights": bad[k]}
	# Floats integrais (como o JSON do ruleset devolve) continuam valendo.
	types["json"] = {"label": "json", "athletes": 1, "collectible_slots": 0, "tier_weights": {"bronze": 700.0, "prata": 300.0}}
	var reg := _reg({MID: {"types": types}})
	var world := _world()
	var club := _club(world)
	for k in bad:
		var g := _grant(reg, world, club, k, 50)
		check_eq(g.get("error"), "invalid_params", "tipo %s" % k)
		check(str(g.get("detail", "")).contains("tier_weights"), "detalhe cita tier_weights (%s): %s" % [k, str(g.get("detail", ""))])
	check(_inventory(reg, club).is_empty(), "nada concedido")
	check(bool(_grant_open(reg, world, club, "json", 51).get("ok", false)), "pesos inteiros em float abrem")
	reg.dispose()


func test_erro_do_gerador_nao_muda_nada() -> void:
	# Tier que o gerador não conhece: o erro dele é repassado e nada é gravado.
	var reg := _reg({MID: {
		"types": {"lendario": {"label": "Lendário", "athletes": 2, "collectible_slots": 1, "tier_weights": {"lenda": 1}}},
		"tier_order": ["bronze", "prata", "ouro", "diamante", "deus", "lenda"],
	}})
	var world := _world()
	var club := _club(world)
	var g := _grant(reg, world, club, "lendario", 9)
	var before := _snapshot(world, club)
	var res := _open(reg, world, club, str(g.pack.id))
	check_eq(res.get("ok"), false)
	check_eq(res.get("error"), "unknown_tier", "erro do gerador repassado")
	check_eq(res.get("needed_slots"), 0)
	check_eq(_snapshot(world, club), before, "nada muda")
	# Tipo que saiu do ruleset depois da concessão.
	var reg2 := _reg()
	check_eq(_open(reg2, world, club, str(g.pack.id)).get("error"), "unknown_type")
	check_eq(_snapshot(world, club), before, "nada muda")
	reg.dispose()
	reg2.dispose()


func test_gerador_indisponivel_nao_muda_nada() -> void:
	var reg := _reg()
	# Bus só com a packs: ninguém responde a athlete_generator.generate.
	reg.bus = HookBus.new(reg.known_hooks())
	reg.get_mechanic(MID).install(reg.bus)
	var world := _world()
	var club := _club(world)
	var g := _grant(reg, world, club, "raro", 11)
	var before := _snapshot(world, club)
	var res := _open(reg, world, club, str(g.pack.id))
	check_eq(res.get("error"), "generator_unavailable")
	check_eq(_snapshot(world, club), before, "nada muda")
	reg.dispose()


func test_ja_aberto_e_inexistente() -> void:
	var reg := _reg()
	var world := _world()
	var club := _club(world)
	var first := _grant_open(reg, world, club, "raro", 77)
	var pack_id := str(first.get("pack", {}).get("id", ""))
	var before := _snapshot(world, club)
	var again := _open(reg, world, club, pack_id)
	check_eq(again.get("ok"), false)
	check_eq(again.get("error"), "already_opened")
	check_eq(_snapshot(world, club), before, "reabrir não muda nada")

	check_eq(_open(reg, world, club, "00000000-0000-4000-8000-000000000000").get("error"), "not_found")
	check_eq(_open(reg, world, club, "").get("error"), "not_found")
	var other := _club(world, "clube_b")
	check_eq(_open(reg, world, other, pack_id).get("error"), "not_found", "pacote de outro clube")
	var foreign := _grant(reg, world, other, "comum", 78)
	check_eq(_open(reg, world, club, str(foreign.pack.id)).get("error"), "not_found", "só abre pacote do próprio inventário")
	check_eq(_snapshot(world, club), before, "nada muda")
	check_eq(reg.bus.decide(OPEN, {"club": club, "pack_id": pack_id}).get("error"), "invalid_payload", "sem world")
	reg.dispose()


## Guardar = não abrir. Depois de salvar/carregar e de outras aberturas, o conteúdo é o mesmo.
func test_guardar_mantem_lacrado_e_conteudo_da_semente() -> void:
	var reg := _reg()
	var w1 := _world()
	var ref := _grant_open(reg, w1, _club(w1), "gol", 424242)
	var ref_athletes: Array = ref.get("athletes", [])

	var w2 := _world()
	var club := _club(w2)
	var kept := _grant(reg, w2, club, "gol", 424242)
	var kept_id := str(kept.pack.id)
	check(bool(_grant_open(reg, w2, club, "comum", 99).get("ok", false)), "outra abertura enquanto guarda")
	var inv := _inventory(reg, club)
	check_eq(str(inv[0].status), "sealed", "guardado segue lacrado")
	check_eq(inv[0].contents, [], "lacrado não tem conteúdo")

	# Salva e carrega (JSON de verdade: números voltam como float) e passa o tempo.
	var loaded := World.from_dict(JSON.parse_string(JSON.stringify(w2.to_dict())))
	loaded.date = LATER
	var lclub: Club = loaded.clubs[club.id]
	check_eq(AthleteDna.canonical(_inventory(reg, lclub)), AthleteDna.canonical(inv), "inventário sobrevive ao save (JSON devolve float)")
	var res := _open(reg, loaded, lclub, kept_id)
	check(bool(res.get("ok", false)), "abre depois do save: %s" % str(res.get("detail", "")))
	var got: Array = res.get("athletes", [])
	check_eq(got.size(), ref_athletes.size())
	for i in mini(got.size(), ref_athletes.size()):
		var a: Athlete = got[i]
		var b: Athlete = ref_athletes[i]
		check_eq(a.id, b.id, "atleta %d: mesmo id" % i)
		check_eq(a.dna.face_hash, b.dna.face_hash, "atleta %d: mesmo rosto" % i)
		check_eq(a.dna.attributes_hash, b.dna.attributes_hash, "atleta %d: mesmos atributos" % i)
		check_eq(a.dna_hash(), b.dna_hash(), "atleta %d: mesmo DNA" % i)
		check_eq(a.tier(), b.tier(), "atleta %d: mesmo tier" % i)
		check_eq(a.dna.origin.date, LATER, "origin.date = data da abertura")
		check_eq(a.club_history[0].from, LATER)
	check_eq(res.pack.granted_on, DATE)
	check_eq(res.pack.opened_on, LATER)
	check_eq(_tiers_of(res.pack), _tiers_of(ref.get("pack", {})), "mesmos tiers")
	reg.dispose()


# --- hooks de extensão -------------------------------------------------------------------------

func test_collectibles_preenche_slot_reservado() -> void:
	var reg := _reg()
	var calls: Array = []
	var fill := func(value: Array, payload: Dictionary) -> Array:
		calls.append({"payload": payload, "value": value.duplicate(true)})
		var out := value.duplicate(true)
		out[0] = {"kind": "sticker", "slot": 0, "sticker": "escudo",
			"roll": payload.rng.fork("teste_colecionaveis").int_between(1, 1000000)}
		out[1] = {"kind": "sticker", "slot": 7, "sticker": "bandeira"}   # slot errado é corrigido
		return out
	var on_opened := func(_payload: Dictionary) -> void:
		calls.append("opened")
	reg.bus.on(COLLECTIBLES, fill, "teste_colecionaveis")
	reg.bus.on(OPENED, on_opened, "teste_colecionaveis")

	var world := _world()
	var club := _club(world)
	var res := _grant_open(reg, world, club, "gol", 5150)
	check_eq(calls.size(), 2, "collectibles e opened chamados uma vez cada")
	if calls.size() < 2 or not bool(res.get("ok", false)):
		reg.dispose()
		return
	check_eq(calls[1], "opened", "collectibles antes de opened")
	var call: Dictionary = calls[0]
	check_eq(call.value, [{"kind": "reserved", "slot": 0}, {"kind": "reserved", "slot": 1}, {"kind": "reserved", "slot": 2}],
		"valor inicial: slots reservados")
	var p: Dictionary = call.payload
	check(p.world == world and p.club == club, "payload com world e club")
	check(p.rng is SeededRng, "payload com SeededRng")
	check_eq(str(p.pack.id), str(res.pack.id))
	check_eq(str(p.pack.status), "opened", "pacote já aberto quando collectibles roda")

	var contents: Array = res.pack.contents
	check_eq(contents.size(), 9)
	check_eq(str(contents[6].kind), "sticker")
	check_eq(str(contents[6].sticker), "escudo")
	check_eq(contents[7], {"kind": "sticker", "slot": 1, "sticker": "bandeira"}, "slot normalizado para o índice")
	check_eq(contents[8], {"kind": "reserved", "slot": 2}, "slot não preenchido segue reservado")
	check_eq(res.cards[6], contents[6], "card do colecionável")
	check_eq(_inventory(reg, club)[0].contents, contents, "inventário guarda o colecionável")

	# Determinismo: mesma semente de pacote, mesmo sorteio do colecionável.
	var w2 := _world()
	var res2 := _grant_open(reg, w2, _club(w2), "gol", 5150)
	if bool(res2.get("ok", false)):
		check_eq(res2.pack.contents[6].roll, contents[6].roll, "rng do colecionável vem da semente do pacote")
	reg.dispose()


func test_opened_emitido_uma_vez() -> void:
	var reg := _reg()
	var events: Array = []
	var on_opened := func(payload: Dictionary) -> void:
		events.append(payload)
	reg.bus.on(OPENED, on_opened, "teste_opened")
	var world := _world()
	var club := _club(world)
	var res := _grant_open(reg, world, club, "raro", 31337)
	check_eq(events.size(), 1, "packs.opened emitido")
	if events.size() == 1 and bool(res.get("ok", false)):
		var ev: Dictionary = events[0]
		check(ev.world == world and ev.club == club, "payload com world e club")
		check_eq(str(ev.pack.id), str(res.pack.id))
		check_eq(str(ev.pack.status), "opened")
		check_eq(ev.athletes.size(), 3)
		for i in ev.athletes.size():
			check(ev.athletes[i] == res.athletes[i], "mesmos atletas")
	_open(reg, world, club, str(res.get("pack", {}).get("id", "")))
	check_eq(events.size(), 1, "falha não emite packs.opened")
	reg.dispose()


# --- unicidade ---------------------------------------------------------------------------------

func test_dez_pacotes_gol_atletas_unicos() -> void:
	var reg := _reg()
	var world := _world()
	var faces := {}
	var attrs := {}
	var dnas := {}
	var ids := {}
	var total := 0
	for i in UNIQUE_SAMPLE:
		var club := _club(world, "clube_%02d" % i)
		var res := _grant_open(reg, world, club, "gol", 7000 + i)
		for a in res.get("athletes", []):
			total += 1
			faces[str(a.dna.face_hash)] = true
			attrs[str(a.dna.attributes_hash)] = true
			dnas[a.dna_hash()] = true
			ids[a.id] = true
	check_eq(total, UNIQUE_SAMPLE * 6, "60 atletas")
	check_eq(faces.size(), total, "face_hash únicos")
	check_eq(attrs.size(), total, "attributes_hash únicos")
	check_eq(dnas.size(), total, "dna_hash únicos")
	check_eq(ids.size(), total, "ids únicos")
	check_eq(world.athletes.size(), total)
	check_eq(world.ext.get(GEN, {}).get("face_hashes", {}).size(), total, "registro de unicidade gravado")
	reg.dispose()


# --- backend -----------------------------------------------------------------------------------

func test_local_backend_new_seed() -> void:
	var backend := LocalBackend.new()
	var seen := {}
	for i in 8:
		var s := backend.new_seed()
		check(s >= 0 and s < AthleteDna.SEED_LIMIT, "semente em [0, 2^48): %d" % s)
		seen[s] = true
	check_eq(seen.size(), 8, "sementes diferentes entre chamadas")
