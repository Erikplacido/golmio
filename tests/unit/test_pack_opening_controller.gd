extends TestCase
## PackOpeningController (revelação de pacotes no cliente): todas as transições com um open_fn
## falso (sucesso, squad_full, erro, sem resposta), ordem de revelação (tier crescente, reservados
## no fim), sinais emitidos, transições inválidas em cada estado (devolvem false, não mudam nada e
## não emitem sinal), reentrância durante OPENING e integração com o servidor local
## (Fixtures.registry_with(["athlete_generator", "packs"])). Também: StickerCard (headless: nós,
## retrato, faces, estilos, bandeiras, textos) e os ajudantes estáticos da tela de demonstração.

const S := PackOpeningController.State
const GEN := "athlete_generator"
const PACKS := "packs"
const DATE := "2026-09-27"
const SEALED := {"id": "pack-1", "type": "gol", "seed": 7, "status": "sealed", "source": "teste",
	"granted_on": DATE, "opened_on": "", "contents": []}
const TIER_ORDER := ["bronze", "prata", "ouro", "diamante", "deus"]
const ALL_ACTIONS := ["present", "keep", "open", "reveal_next", "reveal_all", "finish", "back"]
## Ações aceitas em cada estado estável (as demais devem devolver false).
const VALID := {
	S.IDLE: ["present"],
	S.PREVIEW: ["present", "keep", "open"],
	S.KEPT: ["present", "back"],
	S.BLOCKED: ["back"],
	S.REVEALING: ["reveal_next", "reveal_all"],
	S.COMPLETE: ["finish"],
	S.DELIVERED: ["present", "back"],
	S.FAILED: ["back"],
}


# --- apoio -------------------------------------------------------------------------------------------

## Registra tudo que o controlador emite, em ordem.
class Recorder:
	extends RefCounted
	var events: Array = []

	func attach(c: PackOpeningController) -> void:
		c.state_changed.connect(func(a: int, b: int) -> void: events.append(["state", a, b]))
		c.card_revealed.connect(func(i: int, card: Dictionary) -> void: events.append(["card", i, card]))
		c.opened.connect(func(r: Dictionary) -> void: events.append(["opened", r]))
		c.delivered.connect(func(ids: Array) -> void: events.append(["delivered", ids]))
		c.failed.connect(func(e: String, info: Dictionary) -> void: events.append(["failed", e, info]))
		c.blocked.connect(func(n: int, info: Dictionary) -> void: events.append(["blocked", n, info]))

	func of(kind: String) -> Array:
		return events.filter(func(e: Array) -> bool: return e[0] == kind)

	func states() -> Array:
		return of("state").map(func(e: Array) -> Array: return [e[1], e[2]])


## open_fn falso: devolve `response` e conta as chamadas.
class FakeServer:
	extends RefCounted
	var response: Variant = null
	var calls: Array = []

	func _init(p_response: Variant = null) -> void:
		response = p_response

	func open(pack_id: String) -> Variant:
		calls.append(pack_id)
		return response.duplicate(true) if response is Dictionary else response


func _athlete_card(aid: String, tier: String) -> Dictionary:
	return {"kind": "athlete", "athlete_id": aid, "tier": tier, "name": "Atleta %s" % aid, "position": "MID",
		"nationality": "BR", "face": {}}


## Resposta ok com tiers fora de ordem e 2 slots reservados.
func _ok_response() -> Dictionary:
	var cards := [_athlete_card("a0", "ouro"), _athlete_card("a1", "bronze"), _athlete_card("a2", "deus"),
		_athlete_card("a3", "bronze"), _athlete_card("a4", "prata"), _athlete_card("a5", "diamante"),
		{"kind": "reserved", "slot": 0}, {"kind": "reserved", "slot": 1}]
	var opened := SEALED.duplicate(true)
	opened["status"] = "opened"
	opened["opened_on"] = DATE
	return {"ok": true, "pack": opened, "athletes": [], "cards": cards}


func _ctrl(response: Variant = null) -> Array:
	var server := FakeServer.new(response)
	var c := PackOpeningController.new(server.open)
	var rec := Recorder.new()
	rec.attach(c)
	return [c, server, rec]


## Leva um controlador novo ao estado pedido (estados estáveis).
func _drive_to(target: int) -> Array:
	var response: Variant = _ok_response()
	if target == S.BLOCKED:
		response = {"ok": false, "error": "squad_full", "detail": "x", "needed_slots": 2}
	elif target == S.FAILED:
		response = {"ok": false, "error": "uniqueness_exhausted", "detail": "x", "needed_slots": 0}
	var t := _ctrl(response)
	var c: PackOpeningController = t[0]
	if target == S.IDLE:
		return t
	c.present(SEALED)
	if target == S.KEPT:
		c.keep()
	elif target != S.PREVIEW:
		c.open()
		if target == S.COMPLETE or target == S.DELIVERED:
			c.reveal_all()
		if target == S.DELIVERED:
			c.finish()
	check_eq(c.state, target, "chegar em %s" % PackOpeningController.state_name(target))
	return t


func _call(c: PackOpeningController, action: String) -> bool:
	match action:
		"present":
			return c.present(SEALED)
		"keep":
			return c.keep()
		"open":
			return c.open()
		"reveal_next":
			return c.reveal_next()
		"reveal_all":
			return c.reveal_all()
		"finish":
			return c.finish()
		"back":
			return c.back()
	return false


# --- estado inicial e nomes ----------------------------------------------------------------------------

func test_estado_inicial() -> void:
	var c := PackOpeningController.new()
	check_eq(c.state, S.IDLE, "começa em IDLE")
	check_eq(c.cards, [])
	check_eq(c.revealed_count, 0)
	check_eq(c.athlete_ids(), [])
	check_eq(c.tier_order(), TIER_ORDER, "ordem padrão dos tiers")
	check_eq(PackOpeningController.state_name(S.REVEALING), "REVEALING")
	check_eq(PackOpeningController.state_name(S.DELIVERED), "DELIVERED")
	check_eq(PackOpeningController.state_name(99), "?")
	check_eq(S.keys(), ["IDLE", "PREVIEW", "KEPT", "OPENING", "BLOCKED", "REVEALING", "COMPLETE", "DELIVERED", "FAILED"],
		"estados do contrato")


# --- fluxo de sucesso ----------------------------------------------------------------------------------

func test_fluxo_completo_com_sinais() -> void:
	var t := _ctrl(_ok_response())
	var c: PackOpeningController = t[0]
	var server: FakeServer = t[1]
	var rec: Recorder = t[2]

	check(c.present(SEALED), "present aceito")
	check_eq(c.state, S.PREVIEW)
	check_eq(c.pack, SEALED, "pacote em foco é cópia do apresentado")
	check_eq(server.calls, [], "present não fala com o servidor")

	check(c.open(), "open aceito")
	check_eq(server.calls, ["pack-1"], "open chama open_fn uma vez com o id")
	check_eq(c.state, S.REVEALING)
	check_eq(rec.states(), [[S.IDLE, S.PREVIEW], [S.PREVIEW, S.OPENING], [S.OPENING, S.REVEALING]],
		"passa por OPENING")
	var opened := rec.of("opened")
	check_eq(opened.size(), 1, "opened emitido uma vez")
	if opened.size() == 1:
		check_eq(opened[0][1].cards, _ok_response().cards, "opened leva a resposta inteira")
	check_eq(str(c.pack.status), "opened", "pacote em foco vira o devolvido pelo servidor")
	check_eq(c.cards.size(), 8)
	check_eq(c.remaining(), 8)
	check(rec.of("card").is_empty(), "nada revelado antes de reveal_next")

	var expected_ids := ["a1", "a3", "a4", "a0", "a5", "a2"]
	for i in 6:
		check(c.reveal_next(), "reveal_next %d" % i)
		check_eq(c.revealed_count, i + 1)
		check(c.is_revealed(i) and not c.is_revealed(i + 1), "is_revealed %d" % i)
	check_eq(c.state, S.REVEALING, "faltam os reservados")
	var cards_ev := rec.of("card")
	check_eq(cards_ev.map(func(e: Array) -> int: return e[1]), [0, 1, 2, 3, 4, 5], "índices na ordem de revelação")
	check_eq(cards_ev.map(func(e: Array) -> String: return str(e[2].get("athlete_id", ""))), expected_ids,
		"do tier mais baixo ao mais alto")
	check(c.reveal_next(), "reservado 0")
	check(c.reveal_next(), "reservado 1")
	check_eq(c.state, S.COMPLETE, "a última carta leva a COMPLETE")
	check_eq(rec.of("card")[7][2], {"kind": "reserved", "slot": 1}, "reservados no fim")
	check(not c.reveal_next(), "nada mais para revelar")
	check_eq(rec.of("delivered"), [], "entrega só no finish")

	check(c.finish(), "finish aceito")
	check_eq(c.state, S.DELIVERED)
	var delivered := rec.of("delivered")
	check_eq(delivered.size(), 1)
	if delivered.size() == 1:
		check_eq(delivered[0][1], ["a0", "a1", "a2", "a3", "a4", "a5"], "ids na ordem do servidor (a do elenco)")
	check_eq(rec.of("failed"), [])
	check_eq(rec.of("blocked"), [])

	check(c.back(), "DELIVERED -> IDLE")
	check_eq(c.state, S.IDLE)
	check_eq(c.cards, [], "back esquece as cartas")
	check_eq(c.pack, {}, "back esquece o pacote")


func test_reveal_all_revela_o_resto_em_ordem() -> void:
	var t := _ctrl(_ok_response())
	var c: PackOpeningController = t[0]
	var rec: Recorder = t[2]
	c.present(SEALED)
	c.open()
	c.reveal_next()
	check(c.reveal_all(), "reveal_all aceito")
	check_eq(c.state, S.COMPLETE)
	check_eq(c.revealed_count, 8)
	var idx: Array = rec.of("card").map(func(e: Array) -> int: return e[1])
	check_eq(idx, [0, 1, 2, 3, 4, 5, 6, 7], "um card_revealed por carta, em ordem")
	check_eq(rec.states().back(), [S.REVEALING, S.COMPLETE], "termina em COMPLETE")
	check(not c.reveal_all(), "reveal_all em COMPLETE é inválido")


func test_resposta_sem_cartas_vai_direto_para_complete() -> void:
	var t := _ctrl({"ok": true, "pack": SEALED, "athletes": [], "cards": []})
	var c: PackOpeningController = t[0]
	var rec: Recorder = t[2]
	c.present(SEALED)
	c.open()
	check_eq(c.state, S.COMPLETE)
	check_eq(rec.states(), [[S.IDLE, S.PREVIEW], [S.PREVIEW, S.OPENING], [S.OPENING, S.REVEALING],
		[S.REVEALING, S.COMPLETE]])
	check(c.finish())
	check_eq(rec.of("delivered")[0][1], [], "nenhum atleta")


# --- ordem de revelação --------------------------------------------------------------------------------

func test_ordem_de_revelacao() -> void:
	var cards := [
		{"kind": "reserved", "slot": 0},
		_athlete_card("x", "deus"),
		_athlete_card("y", "prata"),
		{"kind": "sticker", "slot": 1, "art": "escudo"},
		_athlete_card("z", "prata"),
		_athlete_card("w", "misterioso"),
		_athlete_card("v", "bronze"),
	]
	check_eq(PackOpeningController.sort_for_reveal(cards), [5, 6, 2, 4, 1, 0, 3],
		"tier desconhecido primeiro, empate estável, melhor por último, não-atletas no fim na ordem original")
	check_eq(PackOpeningController.sort_for_reveal(cards, ["deus", "prata", "bronze"]), [5, 1, 2, 4, 6, 0, 3],
		"segue a tier_order dada")
	check_eq(PackOpeningController.sort_for_reveal([]), [])
	check_eq(PackOpeningController.sort_for_reveal([null, _athlete_card("a", "ouro")]), [1, 0], "entrada inválida vai para o fim")

	# O controlador usa a tier_order do construtor.
	var server := FakeServer.new({"ok": true, "pack": SEALED, "athletes": [], "cards": [
		_athlete_card("a", "bronze"), _athlete_card("b", "deus")]})
	var c := PackOpeningController.new(server.open, ["deus", "bronze"])
	c.present(SEALED)
	c.open()
	check_eq(c.reveal_order, [1, 0], "ordem invertida pela tier_order")
	check_eq(str(c.cards[0].athlete_id), "b")
	check_eq(c.athlete_ids(), ["a", "b"], "athlete_ids continua na ordem do servidor")


# --- squad_full, erros e servidor ausente --------------------------------------------------------------

func test_squad_full_bloqueia_e_volta() -> void:
	var t := _ctrl({"ok": false, "error": "squad_full", "detail": "o pacote traz 6", "needed_slots": 4})
	var c: PackOpeningController = t[0]
	var rec: Recorder = t[2]
	c.present(SEALED)
	check(c.open(), "open aceito mesmo terminando bloqueado")
	check_eq(c.state, S.BLOCKED)
	check_eq(c.needed_slots, 4, "vagas a liberar")
	check_eq(c.last_error, "squad_full")
	check_eq(rec.states().back(), [S.OPENING, S.BLOCKED])
	var blocked := rec.of("blocked")
	check_eq(blocked.size(), 1, "blocked emitido")
	if blocked.size() == 1:
		check_eq(blocked[0][1], 4)
		check_eq(str(blocked[0][2].get("pack_id")), "pack-1", "info traz o pacote")
		check_eq(str(blocked[0][2].get("detail")), "o pacote traz 6")
	check_eq(rec.of("failed"), [], "squad_full não é FAILED")
	check_eq(rec.of("opened"), [])
	check_eq(c.cards, [])
	check(c.back(), "BLOCKED -> IDLE")
	check_eq(c.state, S.IDLE)
	check_eq(c.needed_slots, 0, "back limpa o bloqueio")
	check(c.present(SEALED), "pode apresentar de novo")
	check_eq(c.state, S.PREVIEW)


func test_erro_do_servidor_vai_para_failed() -> void:
	var t := _ctrl({"ok": false, "error": "uniqueness_exhausted", "detail": "32 tentativas", "needed_slots": 0})
	var c: PackOpeningController = t[0]
	var rec: Recorder = t[2]
	c.present(SEALED)
	c.open()
	check_eq(c.state, S.FAILED)
	check_eq(c.last_error, "uniqueness_exhausted")
	var failed := rec.of("failed")
	check_eq(failed.size(), 1)
	if failed.size() == 1:
		check_eq(failed[0][1], "uniqueness_exhausted")
		check_eq(str(failed[0][2].detail), "32 tentativas")
		check_eq(str(failed[0][2].pack_id), "pack-1")
	check_eq(rec.of("opened"), [])
	check(c.back(), "FAILED -> IDLE")
	check_eq(c.last_error, "", "back limpa o erro")

	# ok = false sem código.
	var t2 := _ctrl({"ok": false})
	var c2: PackOpeningController = t2[0]
	c2.present(SEALED)
	c2.open()
	check_eq(c2.last_error, PackOpeningController.ERR_UNKNOWN, "erro sem código")


func test_sem_resposta_packs_unavailable() -> void:
	var t := _ctrl(null)
	var c: PackOpeningController = t[0]
	var rec: Recorder = t[2]
	c.present(SEALED)
	c.open()
	check_eq(c.state, S.FAILED)
	check_eq(c.last_error, "packs_unavailable", "null -> packs_unavailable")
	check_eq(rec.of("failed").size(), 1)
	# Callable inválida também.
	var c2 := PackOpeningController.new()
	c2.present(SEALED)
	check(c2.open())
	check_eq(c2.last_error, "packs_unavailable", "sem open_fn")
	# Resposta que não é Dictionary.
	var t3 := _ctrl("resposta estranha")
	var c3: PackOpeningController = t3[0]
	c3.present(SEALED)
	c3.open()
	check_eq(c3.last_error, "packs_unavailable", "resposta não-Dictionary")


func test_present_de_pacote_aberto_ou_invalido_falha() -> void:
	var t := _ctrl(_ok_response())
	var c: PackOpeningController = t[0]
	var server: FakeServer = t[1]
	var rec: Recorder = t[2]
	var opened := SEALED.duplicate(true)
	opened["status"] = "opened"
	check(c.present(opened), "present aceito (vai para FAILED)")
	check_eq(c.state, S.FAILED)
	check_eq(c.last_error, "already_opened")
	check_eq(rec.of("failed")[0][1], "already_opened")
	check(not c.open(), "não abre a partir de FAILED")
	check_eq(server.calls, [], "servidor não é chamado")
	c.back()
	check(c.present({}), "present de pacote vazio")
	check_eq(c.last_error, "invalid_pack")
	check_eq(c.state, S.FAILED)


func test_guardar_nao_chama_o_servidor() -> void:
	var t := _ctrl(_ok_response())
	var c: PackOpeningController = t[0]
	var server: FakeServer = t[1]
	var rec: Recorder = t[2]
	c.present(SEALED)
	check(c.keep(), "keep aceito em PREVIEW")
	check_eq(c.state, S.KEPT)
	check_eq(server.calls, [], "guardar não fala com o servidor")
	check(not c.open(), "open inválido em KEPT")
	check(c.back(), "KEPT -> IDLE")
	check_eq(rec.states(), [[S.IDLE, S.PREVIEW], [S.PREVIEW, S.KEPT], [S.KEPT, S.IDLE]])
	check_eq(rec.of("opened") + rec.of("failed") + rec.of("delivered"), [], "nenhum outro sinal")
	# Guardado, pode ser apresentado e aberto depois.
	c.present(SEALED)
	c.open()
	check_eq(c.state, S.REVEALING)
	check_eq(server.calls.size(), 1)


func test_trocar_de_pacote_na_previa() -> void:
	var t := _ctrl(_ok_response())
	var c: PackOpeningController = t[0]
	c.present(SEALED)
	var other := SEALED.duplicate(true)
	other["id"] = "pack-2"
	check(c.present(other), "present aceito em PREVIEW")
	check_eq(c.state, S.PREVIEW)
	check_eq(str(c.pack.id), "pack-2")
	c.open()
	check_eq((t[1] as FakeServer).calls, ["pack-2"], "abre o último apresentado")


func test_open_so_abre_o_pacote_confirmado() -> void:
	# Regressão: a tela confirma Abrir num pacote e só chama open() depois da animação; se a prévia
	# trocou de pacote nesse meio tempo, abrir o outro seria irreversível sem confirmação.
	var t := _ctrl(_ok_response())
	var c: PackOpeningController = t[0]
	var server: FakeServer = t[1]
	var rec: Recorder = t[2]
	c.present(SEALED)
	var other := SEALED.duplicate(true)
	other["id"] = "pack-2"
	c.present(other)
	var before := rec.events.size()
	check(not c.open("pack-1"), "open recusa quando a prévia não é o pacote confirmado")
	check_eq(c.state, S.PREVIEW, "segue na prévia")
	check(server.calls.is_empty(), "o servidor não foi chamado")
	check_eq(rec.events.size(), before, "nenhum sinal")
	check(c.open("pack-2"), "o pacote confirmado abre")
	check_eq(server.calls, ["pack-2"])
	check_eq(c.state, S.REVEALING)


# --- transições inválidas ------------------------------------------------------------------------------

func test_transicoes_invalidas_devolvem_false_sem_efeito() -> void:
	for st in VALID:
		for action in ALL_ACTIONS:
			if (VALID[st] as Array).has(action):
				continue
			var t := _drive_to(st)
			var c: PackOpeningController = t[0]
			var server: FakeServer = t[1]
			var rec: Recorder = t[2]
			var events_before := rec.events.size()
			var calls_before := server.calls.size()
			var snapshot := [c.pack.duplicate(true), c.cards.duplicate(true), c.revealed_count, c.needed_slots, c.last_error]
			var name := "%s em %s" % [action, PackOpeningController.state_name(st)]
			check_eq(_call(c, action), false, "%s devolve false" % name)
			check_eq(c.state, st, "%s não muda o estado" % name)
			check_eq(rec.events.size(), events_before, "%s não emite sinal" % name)
			check_eq(server.calls.size(), calls_before, "%s não chama o servidor" % name)
			check_eq([c.pack, c.cards, c.revealed_count, c.needed_slots, c.last_error], snapshot, "%s não muda dados" % name)
	# As válidas de fato são aceitas (cobertura do quadro).
	for st in VALID:
		for action in VALID[st]:
			var t := _drive_to(st)
			check(_call(t[0], action), "%s em %s é aceito" % [action, PackOpeningController.state_name(st)])


func test_nada_e_aceito_durante_opening() -> void:
	var seen := {}
	var holder: Array = []
	var fn := func(pack_id: String) -> Variant:
		var c: PackOpeningController = holder[0]
		seen["state"] = c.state
		var accepted: Array = []
		for action in ALL_ACTIONS:
			if _call(c, action):
				accepted.append(action)
		seen["accepted"] = accepted
		seen["pack_id"] = pack_id
		return _ok_response()
	var ctrl := PackOpeningController.new(fn)
	holder.append(ctrl)
	ctrl.present(SEALED)
	ctrl.open()
	check_eq(seen.get("state"), S.OPENING, "open_fn roda em OPENING")
	check_eq(seen.get("accepted"), [], "nenhuma ação é aceita em OPENING")
	check_eq(ctrl.state, S.REVEALING, "a resposta continua o fluxo")
	holder.clear()


# --- integração com o servidor local ---------------------------------------------------------------------

func test_integracao_com_packs_e_gerador() -> void:
	var reg := Fixtures.registry_with([GEN, PACKS])
	var world := World.new()
	world.date = DATE
	var club := Club.new()
	club.id = "clube_int"
	world.add_club(club)
	var granted: Variant = reg.bus.decide("packs.grant", {"world": world, "club": club, "type": "gol", "seed": 4242, "source": "teste"})
	check(granted is Dictionary and bool(granted.ok), "grant")
	if not (granted is Dictionary and bool(granted.ok)):
		reg.dispose()
		return
	var c := PackOpeningController.for_registry(reg, world, club)
	var rec := Recorder.new()
	rec.attach(c)
	check_eq(c.tier_order(), TIER_ORDER, "tier_order de packs.types")
	var inv: Array = reg.bus.decide("packs.inventory", {"club": club})
	check(c.present(inv[0]))
	check(c.open())
	check_eq(c.state, S.REVEALING, "abre: %s" % c.last_error)
	check_eq(c.cards.size(), 9, "6 atletas + 3 colecionáveis")
	var ranks: Array = []
	for i in 6:
		check_eq(str(c.cards[i].kind), "athlete", "atletas primeiro")
		ranks.append(TIER_ORDER.find(str(c.cards[i].tier)))
	var sorted := ranks.duplicate()
	sorted.sort()
	check_eq(ranks, sorted, "tiers em ordem crescente")
	check(ranks.back() >= TIER_ORDER.find("ouro"), "garantia do Gol!: o melhor (último) é ouro ou mais")
	for i in range(6, 9):
		check_eq(c.cards[i], {"kind": "reserved", "slot": i - 6}, "reservados no fim")
	check(c.reveal_all())
	check(c.finish())
	var delivered := rec.of("delivered")
	check_eq(delivered.size(), 1)
	if delivered.size() == 1:
		check_eq(delivered[0][1], club.athlete_ids, "entregues = elenco, na ordem")
		for aid in delivered[0][1]:
			check(world.athletes.has(aid), "atleta %s existe no mundo" % aid)
	# O pacote agora está aberto: apresentar de novo falha sem chamar o servidor.
	var inv2: Array = reg.bus.decide("packs.inventory", {"club": club})
	c.back()
	c.present(inv2[0])
	check_eq(c.last_error, "already_opened")
	# E, com o elenco cheio, outro Gol! fica bloqueado sem mudar nada.
	for i in 23:
		club.athlete_ids.append("veterano_%d" % i)
	var second: Dictionary = reg.bus.decide("packs.grant", {"world": world, "club": club, "type": "gol", "seed": 4343, "source": "teste"})
	var before := [world.athletes.size(), club.athlete_ids.duplicate(), world.ext.duplicate(true)]
	c.back()
	c.present(second.pack)
	c.open()
	check_eq(c.state, S.BLOCKED)
	check_eq(c.needed_slots, 5, "29 no elenco, 1 vaga, Gol! traz 6")
	check_eq([world.athletes.size(), club.athlete_ids, world.ext], before, "bloqueio não muda nada")
	reg.dispose()


func test_integracao_sem_packs_ligada() -> void:
	var reg := Fixtures.registry_with([GEN])
	var world := World.new()
	var club := Club.new()
	var c := PackOpeningController.for_registry(reg, world, club)
	check_eq(c.tier_order(), TIER_ORDER, "sem packs.types, ordem padrão")
	c.present(SEALED)
	c.open()
	check_eq(c.state, S.FAILED)
	check_eq(c.last_error, "packs_unavailable")
	reg.dispose()
	var c2 := PackOpeningController.for_registry(null, world, club)
	c2.present(SEALED)
	c2.open()
	check_eq(c2.last_error, "packs_unavailable", "sem registro")


# --- StickerCard (headless) --------------------------------------------------------------------------------

func _real_face() -> Dictionary:
	var cat := PortraitCatalog.shared()
	var face := {"chin": "", "skin_mark": "", "ear": "", "arm": ""}
	face["head"] = cat.ids_with_status("head", "active")[0]
	for slot in ["eye", "eyebrow", "nose", "mouth", "hair", "body"]:
		face[slot] = cat.ids_with_status(slot, "active")[0]
	return face


func test_sticker_card_faces_e_retrato() -> void:
	var sc := StickerCard.new()
	check_eq(sc.size, StickerCard.BASE_SIZE, "tamanho padrão")
	check_near(StickerCard.ASPECT, 1452.0 / 1122.0, 1e-9, "proporção do Card Studio")
	check(not sc.face_up, "nasce virada para baixo")
	check(sc.portrait() == null, "sem carta, sem retrato")
	var card := _athlete_card("a9", "ouro")
	card["face"] = _real_face()
	var club := Club.new()
	club.colors = {"primary": "#123456", "secondary": "#ffffff"}
	var kit := PortraitRenderer.kit_for_club(club)
	sc.set_card(card, kit, null, {"pace": 80, "finishing": 91, "passing": 60, "stamina": 80})
	check(sc.is_athlete() and not sc.is_reserved())
	check_eq(sc.tier(), "ouro")
	check_eq(sc.frame(), "lendario", "ouro usa a moldura lendária")
	check_eq(sc.overall_rating(), 78, "OVR = média dos atributos")
	var front := sc.get_node("Front") as Control
	var frame := sc.get_node("Frame") as ColorRect
	check(not front.visible and frame.visible, "verso: só o shader do verso")
	var mat := frame.material as ShaderMaterial
	check_eq(int(mat.get_shader_parameter("mode")), 1, "verso")
	var r := sc.portrait()
	check(r != null, "retrato montado")
	sc.set_face_up(true)
	check(front.visible and not frame.visible, "frente: camadas da moldura")
	var cfg := StickerCard.frame_config("lendario")
	check_eq((front.get_node("Base") as TextureRect).texture, StickerCard.card_texture(cfg.card_imagem), "base do nível")
	check_eq((front.get_node("Finish") as TextureRect).texture, StickerCard.card_texture(cfg.overlay_imagem), "acabamento do nível")
	var names: Array = front.get_children().map(func(n): return str(n.name))
	check(names.find("Base") < names.find("Foil") and names.find("Foil") < names.find("PortraitWindow")
		and names.find("PortraitWindow") < names.find("Finish"), "ordem do Card Studio: %s" % [names])
	var foil := front.get_node("Foil") as ColorRect
	var fm := foil.material as ShaderMaterial
	check(foil.visible, "lendário tem foil")
	check_eq(int(fm.get_shader_parameter("foil_type")), StickerCard.FOIL_TYPES.dourado_metalico, "foil dourado")
	check_eq(int(fm.get_shader_parameter("mask_mode")), 5, "máscara PNG")
	check_eq(fm.get_shader_parameter("mask_texture"), StickerCard.card_texture(cfg.foil.mascara_arquivo), "máscara do nível")
	check_eq(int(fm.get_shader_parameter("blend_mode")), StickerCard.BLEND_MODES["color-dodge"], "mesclagem color-dodge")
	check(bool(fm.get_shader_parameter("use_base_texture")), "foil mescla com a base")
	if r != null:
		check_eq(r.face, card.face, "retrato com a receita da carta")
		check_eq(r.kit.colors, kit.colors, "retrato com o kit do clube")
		check(r.find_layer("head") != null, "camada da cabeça")
		var win := r.get_parent() as Control
		check(win != null and win.clip_contents and win.name == "PortraitWindow", "retrato dentro de janela recortada")
		var k := sc.size.x / StickerCard.CARD_PX.x
		check_near(win.size.y, float(cfg.jogador.corte_inferior) * sc.size.y / StickerCard.CARD_PX.y, 0.001, "corte acima da placa")
		check_near(win.size.x, StickerCard.BODY_RECT.size.x * k, 0.001, "corte nas laterais do corpo da carta")
		# Enquadramento do Card Studio: caixa cabeça + tronco centrada em (jogador.x, jogador.y), escala x1.5.
		var box := Rect2()
		var first := true
		for layer in r.layers:
			if layer.slot == "head" or layer.slot == "body":
				box = PortraitLayout.layer_rect(layer) if first else box.merge(PortraitLayout.layer_rect(layer))
				first = false
		var center: Vector2 = win.position + r.transform * box.get_center()
		check_near(center.x, float(cfg.jogador.x) * k, 0.01, "centro x do jogador")
		check_near(center.y, float(cfg.jogador.y) * sc.size.y / StickerCard.CARD_PX.y, 0.01, "centro y do jogador")
		check_near(r.scale.x, float(cfg.jogador.escala) * 1.5 * k, 1e-6, "escala do jogador")
	check(sc.flip_to_front() == null, "já de frente: não anima")
	sc.size = Vector2(100, 100 * StickerCard.ASPECT)
	sc.set_face_up(false)   # fora da árvore não há RESIZED; set_face_up/set_card refazem o layout
	check_near(frame.size.x, StickerCard.BODY_RECT.size.x * 100.0 / StickerCard.CARD_PX.x, 0.001, "verso no corpo da carta")
	check_near(float(mat.get_shader_parameter("radius_px")), StickerCard.RADIUS_PX * 100.0 / StickerCard.CARD_PX.x, 0.001,
		"escala junto com o tamanho")
	check(sc.flip_to_front() == null, "fora da árvore: vira sem animar")
	check(sc.face_up)

	# Divino: jogador num SubViewport com o shader de brilho (aura + contorno).
	card["tier"] = "deus"
	sc.set_card(card, kit)
	check_eq(sc.frame(), "divino")
	var glow := front.get_node_or_null("PlayerGlow") as TextureRect
	check(glow != null and glow.visible, "divino desenha o brilho")
	check(sc.portrait() != null and sc.portrait().get_parent().get_parent() is SubViewport, "jogador dentro do SubViewport")
	if glow != null:
		var gm := glow.material as ShaderMaterial
		var bd: Dictionary = StickerCard.frame_config("divino").jogador.brilho_divino
		check_near(float(gm.get_shader_parameter("outer_radius")), float(bd.externo_raio) * 100.0 / StickerCard.CARD_PX.x, 1e-4,
			"raio da aura escala com a carta")
		check(bool(gm.get_shader_parameter("premultiplied_input")), "desfaz o alfa pré-multiplicado do viewport")
	# Volta para um nível sem brilho: o jogador sai do viewport.
	card["tier"] = "bronze"
	sc.set_card(card, kit)
	check_eq(sc.frame(), "normal")
	check(sc.portrait().get_parent().get_parent() == front, "normal: jogador direto na carta")
	check(not (front.get_node("PlayerGlow") as TextureRect).visible, "normal sem brilho")
	check(not (front.get_node("Foil") as ColorRect).visible, "normal sem foil")
	# Estrela convidada: escolhida por card.frame, independe do tier.
	card["frame"] = StickerCard.FRAME_GUEST_STAR
	sc.set_card(card, kit)
	check_eq(sc.frame(), "estrela_convidada", "card.frame escolhe a moldura")
	check_eq(int(((front.get_node("Foil") as ColorRect).material as ShaderMaterial).get_shader_parameter("foil_type")),
		StickerCard.FOIL_TYPES.prismatico_estrelas, "foil prismático de estrelas")
	check_eq(int(sc.style().rank), 5, "estrela convidada com 5 estrelas")

	# Slot reservado: sem retrato, face "Em breve".
	sc.set_card({"kind": "reserved", "slot": 2})
	check(sc.is_reserved() and not sc.is_athlete())
	check(sc.portrait() == null, "reservado não tem retrato")
	check_eq(int(mat.get_shader_parameter("mode")), 2, "face reservada")
	check(not front.visible and frame.visible)
	sc.free()


func test_sticker_card_estilos_e_textos() -> void:
	var seen_colors := {}
	var rank := 0
	var labels := []
	for t in TIER_ORDER:
		var s := StickerCard.tier_style(t)
		check_eq(int(s.rank), rank + 1, "%s: estrelas crescentes" % t)
		rank = int(s.rank)
		check(not seen_colors.has(s.mid), "%s: cor própria" % t)
		seen_colors[s.mid] = true
		for key in ["mid", "light"]:
			check(Color.html_is_valid(str(s[key])), "%s.%s é cor" % [t, key])
		labels.append(s.label)
	check_eq(labels, ["Normal", "Raro", "Lendário", "Mítico", "Divino"], "rótulos dos níveis do Card Studio")
	# Todos os níveis do card_config têm base e acabamento exportados.
	check_eq(StickerCard.frames(), ["normal", "raro", "lendario", "mitico", "divino", "estrela_convidada"], "níveis")
	for f in StickerCard.frames():
		var cfg := StickerCard.frame_config(f)
		check(StickerCard.card_texture(str(cfg.card_imagem)) != null, "base de %s exportada" % f)
		check(StickerCard.card_texture(str(cfg.overlay_imagem)) != null, "acabamento de %s exportado" % f)
		var foil: Dictionary = cfg.foil
		check(StickerCard.FOIL_TYPES.has(str(foil.tipo)), "foil conhecido em %s: %s" % [f, foil.tipo])
		check(StickerCard.BLEND_MODES.has(str(foil.blend)), "mesclagem conhecida em %s: %s" % [f, foil.blend])
		if foil.get("ativo", false) and foil.get("area_mascara") == "mascara_custom":
			check(StickerCard.card_texture(str(foil.mascara_arquivo)) != null, "máscara de %s exportada" % f)
	check_eq(StickerCard.frame_for_tier("lendario"), "lendario", "ID de nível também vale como tier")
	check_eq(StickerCard.tier_style("lendario").label, "Lendário")
	check_eq(StickerCard.tier_style("platina").label, "Platina", "tier desconhecido vira neutro")
	check_eq(int(StickerCard.tier_style("platina").rank), 0)
	check_eq(StickerCard.frame_for({"tier": "deus", "frame": "nao_existe"}), "divino", "frame inválido cai no tier")
	check_eq(StickerCard.position_label("FWD"), "ATA")
	check_eq(StickerCard.position_label("GK", true), "Goleiro")
	check_eq(StickerCard.position_label("XYZ"), "XYZ")
	check_eq(StickerCard.overall({}), -1, "sem atributos, sem OVR")
	check_eq(StickerCard._css_color("rgba(7,25,48,0.85)", Color.RED), Color(7 / 255.0, 25 / 255.0, 48 / 255.0, 0.85), "rgba do CSS")
	check_eq(StickerCard._css_color("#38bdf8", Color.RED), Color("#38bdf8"), "hex do CSS")
	check_eq(StickerCard.top_stats({"pace": 80, "finishing": 91.4, "passing": 60, "stamina": 80}),
		[["FIN", 91], ["VEL", 80], ["EST", 80]], "3 melhores; empate na ordem dos atributos")
	check_eq(StickerCard.top_stats({"desconhecido": 99}), [], "ignora atributo fora do catálogo")
	# Nome composto em duas linhas, como o quebrarNomeComposto do Card Studio.
	check_eq(StickerCard.split_composite_name("LUCAS SILVA"), ["LUCAS", "SILVA"])
	check_eq(StickerCard.split_composite_name("LUCAS DE OLIVEIRA"), ["LUCAS", "DE OLIVEIRA"], "preposição na 2ª linha")
	check_eq(StickerCard.split_composite_name("JOÃO PEDRO SILVA"), ["JOÃO PEDRO", "SILVA"])
	check_eq(StickerCard.split_composite_name("PELÉ"), ["PELÉ"])
	check_eq(StickerCard.split_composite_name("GABRIEL / DA SILVA SANTOS"), ["GABRIEL", "DA SILVA SANTOS"], "barra manual")
	# Nome que não cabe: encolhe, depois abrevia.
	var f := StickerCard.font(true)
	var fit := StickerCard.fit_text(f, "Ana", 200.0, 17.0, 10.0)
	check_eq(fit, ["Ana", 17.0], "nome curto fica igual")
	var long_name := "Maximiliano Bartholomeu Albuquerque"
	var fit2 := StickerCard.fit_text(f, long_name, 120.0, 17.0, 10.0)
	check(f.get_string_size(str(fit2[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(float(fit2[1]))).x <= 120.0, "cabe: %s" % str(fit2))
	check(float(fit2[1]) >= 10.0, "respeita o mínimo")


# --- tela de demonstração (ajudantes estáticos) ------------------------------------------------------------

func test_tela_demo_monta_servidor_local() -> void:
	var reg := PackOpeningView.build_registry()
	check(reg.is_enabled(GEN) and reg.is_enabled(PACKS), "dev.json + athlete_generator e packs ligados")
	var world := PackOpeningView.build_world()
	var club: Club = world.clubs.get(PackOpeningView.DEMO_CLUB_ID)
	check(club != null, "clube demo")
	if club == null:
		reg.dispose()
		return
	var limit := int(reg.ruleset.core_param("squad_limit"))
	check(limit - club.athlete_ids.size() >= 10, "espaço para os 3 pacotes (1 + 3 + 6)")
	var packs := PackOpeningView.grant_demo_packs(reg, world, club, 99)
	check_eq(packs.map(func(p: Dictionary) -> String: return str(p.type)), ["comum", "raro", "gol"], "um de cada tipo")
	var again := PackOpeningView.grant_demo_packs(reg, PackOpeningView.build_world(), Club.new(), 99)
	check_eq(again.map(func(p: Dictionary) -> int: return int(p.seed)), packs.map(func(p: Dictionary) -> int: return int(p.seed)),
		"com --seed as sementes se repetem")
	var c := PackOpeningController.for_registry(reg, world, club)
	for p in packs:
		check(c.present(p) and c.open(), "abre %s" % p.type)
		check(c.reveal_all() and c.finish(), "revela e entrega %s" % p.type)
		c.back()
	check_eq(club.athlete_ids.size(), 16 + 10, "elenco com os 10 novos")
	reg.dispose()
