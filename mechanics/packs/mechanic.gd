extends Mechanic
## Pacotes de figurinhas (GDD 5.3; docs/RETRATOS.md seção 6). Camada meta, AUTORITATIVA NO
## SERVIDOR: concede pacotes, abre de forma atômica e entrega os atletas ao elenco. A revelação
## no cliente (PackOpeningController) só exibe o que o servidor devolveu.
##
## TIPOS SÃO DADOS: cada tipo em params.types diz quantos atletas traz, quantos slots
## colecionáveis reserva, os pesos inteiros de cada tier e a garantia opcional. Criar um tipo
## novo ou mudar probabilidades é só mudar o ruleset.
##
## CONCESSÃO (packs.grant): o pacote entra lacrado ("sealed") no inventário do clube, com a
## semente fornecida pelo servidor (Backend.new_seed; esta mecânica NUNCA cria semente com
## relógio). id = AthleteDna.uuid_v4_from_seed(seed); se já existir no mundo, continua o mesmo
## fluxo. "Guardar" o pacote = não chamar packs.open: ele segue lacrado e, quando for aberto, o
## conteúdo sai da mesma semente (os atletas só passam a existir na abertura, GDD 5.3).
##
## ABERTURA ATÔMICA (packs.open), nesta ordem; qualquer falha antes do passo 6 não muda nada:
##   1. o pacote existe no inventário do clube (not_found);
##   2. o tipo ainda existe no ruleset (unknown_type) e é válido (invalid_params);
##   3. o pacote está lacrado (already_opened);
##   4. há vagas para TODOS os atletas: squad_limit - elenco >= athletes, se require_free_slots
##      (squad_full, com needed_slots = athletes - (squad_limit - elenco): as vagas que faltam
##      liberar, contando também os atletas que já passam do limite);
##   5. tiers: SeededRng(derive_seed(seed, "tiers")) sorteia um tier por atleta pelos pesos
##      inteiros, na ordem de tier_order. Garantia {min_tier, count}: se menos de count atletas
##      atingiram min_tier, os ÚLTIMOS sorteados abaixo dele sobem para min_tier;
##   6. athlete_generator.generate (commit = true, unique = true, semente
##      derive_seed(seed, "athletes")): tudo ou nada. Resposta null -> generator_unavailable;
##      erro do gerador é repassado e nada muda;
##   7. atletas entram em club.athlete_ids e ganham club_history {club_id, from, to: "", via: "pack"};
##   8. pacote vira "opened" com contents e opened_on;
##   9. packs.collectibles (pipe) preenche os slots colecionáveis reservados;
##  10. packs.opened (emit).
##
## Dados desta mecânica: club.ext["packs"] = {"inventory": [pacote, ...]}, com pacote =
##   {"id": uuid v4, "type": String, "seed": int, "status": "sealed"|"opened", "source": String,
##    "granted_on": "AAAA-MM-DD", "opened_on": "" | "AAAA-MM-DD",
##    "contents": [] | [{"kind": "athlete", "athlete_id", "tier"}..., {"kind": "reserved", "slot": i}...]}

const HOOK_GRANT := "packs.grant"
const HOOK_OPEN := "packs.open"
const HOOK_INVENTORY := "packs.inventory"
const HOOK_TYPES := "packs.types"
const HOOK_COLLECTIBLES := "packs.collectibles"
const HOOK_OPENED := "packs.opened"
const HOOK_GRANT_STARTER := "packs.grant_starter"
## Hook oferecido pelo athlete_generator (dependência declarada em depends_on).
const HOOK_GENERATE := "athlete_generator.generate"
const STATUS_SEALED := "sealed"
const STATUS_OPENED := "opened"
const KIND_ATHLETE := "athlete"
const KIND_RESERVED := "reserved"
const VIA_PACK := "pack"
const ORIGIN_SOURCE := "pack"
## Sais das sementes derivadas do pacote: cada etapa usa um fluxo próprio.
const SALT_TIERS := "tiers"
const SALT_ATHLETES := "athletes"
const SALT_COLLECTIBLES := "collectibles"
## SeededRng.int_between usa o randi_range de 32 bits do Godot: a soma dos pesos de um sorteio
## precisa caber em int32, senão o sorteio sai distorcido sem erro nenhum.
const MAX_WEIGHT_TOTAL := 2147483647


func _init() -> void:
	id = "packs"
	title = "Pacotes de figurinhas"
	description = "Concessão, abertura atômica e entrega ao elenco de pacotes de atletas únicos, com tipos e probabilidades em params (GDD 5.3; RETRATOS 6)."
	version = 1
	data_version = 1
	layer = "meta"
	stage = "experimental"
	depends_on = ["athlete_generator"]
	enabled_by_default = false
	default_params = {
		## Tipos de pacote. athletes: atletas novos; collectible_slots: slots reservados para
		## colecionáveis (preenchidos por packs.collectibles); tier_weights: pesos INTEIROS >= 0
		## de cada tier (probabilidade = peso / soma; soma <= 2^31 - 1). Peso fracionário, negativo
		## ou não numérico torna o tipo inválido (invalid_params): 0.7 não vira 1 em silêncio.
		## guarantee: pelo menos `count` atletas com tier >= min_tier (na ordem de tier_order).
		"types": {
			"comum": {"label": "Básico", "athletes": 1, "collectible_slots": 1,
				"tier_weights": {"bronze": 700, "prata": 240, "ouro": 50, "diamante": 9, "deus": 1}},
			"raro": {"label": "Raro", "athletes": 3, "collectible_slots": 2,
				"tier_weights": {"bronze": 350, "prata": 400, "ouro": 200, "diamante": 45, "deus": 5},
				"guarantee": {"min_tier": "prata", "count": 1}},
			"gol": {"label": "Mítico", "athletes": 6, "collectible_slots": 3,
				"tier_weights": {"bronze": 200, "prata": 350, "ouro": 300, "diamante": 130, "deus": 20},
				"guarantee": {"min_tier": "ouro", "count": 1}},
			"starter": {"label": "Inicial", "athletes": 11, "collectible_slots": 0,
				"tier_weights": {"bronze": 600, "prata": 380, "ouro": 20, "diamante": 0, "deus": 0},
				"positions": ["GK", "DEF", "DEF", "DEF", "DEF", "MID", "MID", "MID", "FWD", "FWD", "FWD"],
				"guarantee": {"min_tier": "prata", "count": 2}},
		},
		## Do mais comum ao mais raro. Define a ordem do sorteio e o "tier >= min_tier" da garantia.
		"tier_order": ["bronze", "prata", "ouro", "diamante", "deus"],
		## true: o pacote só abre se houver vaga no elenco para todos os seus atletas (GDD 5.3).
		"require_free_slots": true,
	}
	provides_hooks = {
		HOOK_GRANT: "decide {world: World, club: Club, type: String, seed: int (Backend.new_seed), source: String} -> {ok: true, pack: Dictionary (cópia)} | {ok: false, error: unknown_type|invalid_payload|invalid_params, detail: String}. Põe um pacote lacrado no inventário do clube.",
		HOOK_OPEN: "decide {world: World, club: Club, pack_id: String} -> {ok: true, pack: Dictionary (cópia), athletes: Array[Athlete], cards: Array[Dictionary]} | {ok: false, error: squad_full|already_opened|not_found|unknown_type|generator_unavailable|invalid_payload|invalid_params|<erro do athlete_generator.generate>, detail: String, needed_slots: int (vagas a liberar; 0 fora de squad_full)}. Abertura atômica: em erro nada muda. cards: [{kind: \"athlete\", athlete_id, tier, name, position, nationality, face}..., entradas dos slots colecionáveis ({kind: \"reserved\", slot} se ninguém preencheu)].",
		HOOK_INVENTORY: "decide {club: Club} -> Array (cópia profunda dos pacotes do clube, lacrados e abertos).",
		HOOK_TYPES: "decide {} -> {types: Dictionary, tier_order: Array} (cópias) — tipos e probabilidades publicados, para a interface mostrar o conteúdo possível antes de abrir (GDD 5.3).",
		HOOK_COLLECTIBLES: "pipe Array (uma entrada por slot colecionável, inicialmente {kind: \"reserved\", slot: i}) ; payload {world, club, pack (cópia), rng: SeededRng} — mecânicas de colecionáveis trocam entradas por {kind: \"<tipo>\", slot: i, ...} serializável. Use payload.rng.fork(<seu_id>) para não depender da ordem dos handlers. Chamado depois do commit dos atletas.",
		HOOK_OPENED: "emit {world, club, pack (cópia), athletes: Array[Athlete]} — pacote aberto e atletas já no elenco.",
		HOOK_GRANT_STARTER: "decide {world: World, club: Club, seed: int opcional} -> {ok: true, pack: Dictionary, athletes: Array[Athlete], cards: Array[Dictionary]} | {ok: false, error: String, detail: String}. Concede e abre o pacote inicial (11 atletas) de forma atômica para onboarding.",
	}


func install(bus: HookBus) -> void:
	bus.on(HOOK_GRANT, _on_grant, id)
	bus.on(HOOK_OPEN, _on_open, id)
	bus.on(HOOK_INVENTORY, _on_inventory, id)
	bus.on(HOOK_TYPES, _on_types, id)
	bus.on(HOOK_GRANT_STARTER, _on_grant_starter, id)


# --- hook: grant -------------------------------------------------------------------------------

func _on_grant(payload: Dictionary) -> Dictionary:
	var world_v: Variant = payload.get("world")
	var club_v: Variant = payload.get("club")
	if not (world_v is World) or not (club_v is Club):
		return _fail("invalid_payload", "world e club são obrigatórios")
	var world: World = world_v
	var club: Club = club_v
	var seed_v: Variant = payload.get("seed")
	if not _is_valid_seed(seed_v):
		return _fail("invalid_payload", "seed deve ser inteiro em [0, 2^48) (o servidor fornece a entropia; ver Backend.new_seed)")
	var type_id := str(payload.get("type", ""))
	var type_def: Variant = _types().get(type_id)
	if not (type_def is Dictionary):
		return _fail("unknown_type", "tipo de pacote desconhecido: %s" % type_id)
	var problem := _check_type(type_def)
	if problem != "":
		return _fail("invalid_params", "tipo %s: %s" % [type_id, problem])

	var pack_seed := int(seed_v)
	var pack := {
		"id": AthleteDna.uuid_v4_from_seed(pack_seed, _pack_ids(world, club)),
		"type": type_id,
		"seed": pack_seed,
		"status": STATUS_SEALED,
		"source": str(payload.get("source", "")),
		"granted_on": world.date,
		"opened_on": "",
		"contents": [],
	}
	_inventory_for_write(club).append(pack)
	return {"ok": true, "pack": pack.duplicate(true)}


# --- hook: open --------------------------------------------------------------------------------

func _on_open(payload: Dictionary) -> Dictionary:
	var world_v: Variant = payload.get("world")
	var club_v: Variant = payload.get("club")
	if not (world_v is World) or not (club_v is Club):
		return _open_fail("invalid_payload", "world e club são obrigatórios")
	var world: World = world_v
	var club: Club = club_v
	var pack_id := str(payload.get("pack_id", ""))

	# 1..4: todas as checagens ANTES de gerar. Até o commit do gerador nada é gravado.
	var pack := _find_pack(club, pack_id)
	if pack.is_empty():
		return _open_fail("not_found", "pacote %s não está no inventário do clube %s" % [pack_id, club.id])
	var type_id := str(pack.get("type", ""))
	var type_def: Variant = _types().get(type_id)
	if not (type_def is Dictionary):
		return _open_fail("unknown_type", "tipo de pacote desconhecido: %s" % type_id)
	var problem := _check_type(type_def)
	if problem != "":
		return _open_fail("invalid_params", "tipo %s: %s" % [type_id, problem])
	if str(pack.get("status", "")) != STATUS_SEALED:
		return _open_fail("already_opened", "pacote %s já foi aberto em %s" % [pack_id, str(pack.get("opened_on", ""))])
	var n_athletes := int(type_def.get("athletes", 0))
	if bool(param("require_free_slots", true)):
		var free := int(registry.ruleset.core_param("squad_limit")) - club.athlete_ids.size()
		if free < n_athletes:
			var res := _open_fail("squad_full", "o pacote traz %d atletas e o elenco tem %d vagas" % [n_athletes, maxi(free, 0)])
			# free pode ser negativo (elenco acima do limite): essas vagas também precisam ser liberadas.
			res["needed_slots"] = n_athletes - free
			return res

	# 5: tiers.
	var pack_seed := int(pack.get("seed", 0))
	var tiers := _roll_tiers(type_def, pack_seed)

	# 6: geração atômica (o gerador grava world.athletes e o registro de unicidade só se todos saírem).
	var gen_payload: Dictionary = {
		"world": world,
		"count": n_athletes,
		"seed": AthleteDna.derive_seed(pack_seed, SALT_ATHLETES),
		"tiers": tiers,
		"origin": {"source": ORIGIN_SOURCE, "pack_type": type_id, "pack_id": str(pack.id),
			"club_id": club.id, "date": world.date},
		"unique": true,
		"commit": true,
	}
	if type_def.has("positions"):
		gen_payload["positions"] = type_def["positions"]
	var gen: Variant = registry.bus.decide(HOOK_GENERATE, gen_payload)
	if not (gen is Dictionary):
		return _open_fail("generator_unavailable", "ninguém respondeu a %s" % HOOK_GENERATE)
	if not bool(gen.get("ok", false)):
		return _open_fail(str(gen.get("error", "generator_failed")), str(gen.get("detail", "")))
	var athletes: Array = gen.get("athletes", [])
	if athletes.size() != n_athletes:
		# Nunca deveria acontecer (o gerador é tudo ou nada); não entregar lote incompleto.
		return _open_fail("generator_unavailable", "o gerador devolveu %d de %d atletas" % [athletes.size(), n_athletes])

	# 7: entrega ao elenco.
	for a in athletes:
		club.athlete_ids.append(a.id)
		a.club_history.append({"club_id": club.id, "from": world.date, "to": "", "via": VIA_PACK})

	# 8: pacote aberto.
	var n_slots := int(type_def.get("collectible_slots", 0))
	var contents: Array = []
	for a in athletes:
		contents.append({"kind": KIND_ATHLETE, "athlete_id": a.id, "tier": a.tier()})
	for i in n_slots:
		contents.append(_reserved(i))
	pack["status"] = STATUS_OPENED
	pack["opened_on"] = world.date
	pack["contents"] = contents

	# 9: colecionáveis (mecânicas futuras preenchem os slots reservados).
	var piped: Variant = registry.bus.pipe(HOOK_COLLECTIBLES, _reserved_slots(n_slots), {
		"world": world, "club": club, "pack": pack.duplicate(true),
		"rng": SeededRng.new(AthleteDna.derive_seed(pack_seed, SALT_COLLECTIBLES)),
	})
	var collectibles := _normalize_collectibles(piped, n_slots)
	contents.resize(athletes.size())
	contents.append_array(collectibles)

	# 10: aviso.
	registry.bus.emit(HOOK_OPENED, {"world": world, "club": club, "pack": pack.duplicate(true), "athletes": athletes})
	return {"ok": true, "pack": pack.duplicate(true), "athletes": athletes, "cards": _cards(athletes, collectibles)}


# --- hooks: inventory e types --------------------------------------------------------------------

func _on_inventory(payload: Dictionary) -> Array:
	var club_v: Variant = payload.get("club")
	if not (club_v is Club):
		return []
	return _inventory_of(club_v).duplicate(true)


func _on_types(_payload: Dictionary) -> Dictionary:
	return {"types": _types().duplicate(true), "tier_order": _tier_order().duplicate()}


func _on_grant_starter(payload: Dictionary) -> Dictionary:
	var world_v: Variant = payload.get("world")
	var club_v: Variant = payload.get("club")
	if not (world_v is World) or not (club_v is Club):
		return _open_fail("invalid_payload", "world e club são obrigatórios")
	var seed_v: Variant = payload.get("seed")
	if not (seed_v is int or seed_v is float):
		return _open_fail("invalid_payload", "seed ausente (o servidor fornece a entropia; ver Backend.new_seed)")
	var s := int(seed_v)
	var grant_res := _on_grant({
		"world": world_v,
		"club": club_v,
		"type": "starter",
		"seed": s,
		"source": "onboarding_starter",
	})
	if not bool(grant_res.get("ok", false)):
		return grant_res
	var pack: Dictionary = grant_res.get("pack", {})
	return _on_open({
		"world": world_v,
		"club": club_v,
		"pack_id": str(pack.get("id", "")),
	})


# --- tiers ---------------------------------------------------------------------------------------

## Um tier por atleta, sorteado por peso inteiro (ordem de tier_order), mais a garantia.
func _roll_tiers(type_def: Dictionary, pack_seed: int) -> Array:
	var order := _tier_order()
	var weights: Dictionary = type_def.get("tier_weights", {})
	var rng := SeededRng.new(AthleteDna.derive_seed(pack_seed, SALT_TIERS))
	var total := 0
	for t in order:
		total += _weight(weights.get(t, 0))
	var tiers: Array = []
	for _i in int(type_def.get("athletes", 0)):
		var r := rng.int_between(0, total - 1)
		for t in order:
			var w := _weight(weights.get(t, 0))
			if r < w:
				tiers.append(str(t))
				break
			r -= w

	var guarantee: Variant = type_def.get("guarantee")
	if guarantee is Dictionary:
		var min_tier := str(guarantee.get("min_tier", ""))
		var min_rank := order.find(min_tier)
		var reached := 0
		for t in tiers:
			if order.find(t) >= min_rank:
				reached += 1
		var need := mini(int(guarantee.get("count", 0)), tiers.size()) - reached
		var i := tiers.size() - 1
		while need > 0 and i >= 0:
			if order.find(tiers[i]) < min_rank:
				tiers[i] = min_tier
				need -= 1
			i -= 1
	return tiers


## "" se o tipo é utilizável; senão, o motivo (vira invalid_params).
func _check_type(type_def: Dictionary) -> String:
	var order := _tier_order()
	if order.is_empty():
		return "tier_order vazio"
	if int(type_def.get("athletes", -1)) < 0:
		return "athletes deve ser inteiro >= 0"
	if int(type_def.get("collectible_slots", 0)) < 0:
		return "collectible_slots deve ser inteiro >= 0"
	var weights: Variant = type_def.get("tier_weights")
	if not (weights is Dictionary):
		return "tier_weights ausente"
	var total := 0
	for t in weights:
		if not order.has(str(t)):
			return "tier '%s' em tier_weights não está em tier_order" % str(t)
		if not _is_weight(weights[t]):
			return "tier_weights.%s deve ser inteiro >= 0 e <= %d (recebido %s)" % [str(t), MAX_WEIGHT_TOTAL, str(weights[t])]
		total += _weight(weights[t])
		if total > MAX_WEIGHT_TOTAL:
			return "a soma de tier_weights passa de %d (limite do sorteio de 32 bits)" % MAX_WEIGHT_TOTAL
	if total <= 0 and int(type_def.get("athletes", 0)) > 0:
		return "tier_weights sem peso positivo"
	var guarantee: Variant = type_def.get("guarantee")
	if guarantee != null:
		if not (guarantee is Dictionary):
			return "guarantee deve ser {min_tier, count}"
		if not order.has(str(guarantee.get("min_tier", ""))):
			return "guarantee.min_tier '%s' não está em tier_order" % str(guarantee.get("min_tier", ""))
	return ""


## Peso válido: inteiro (ou float integral, como o JSON devolve) em [0, MAX_WEIGHT_TOTAL].
static func _is_weight(v: Variant) -> bool:
	if v is int:
		return v >= 0 and v <= MAX_WEIGHT_TOTAL
	if v is float:
		return is_finite(v) and v == floorf(v) and v >= 0.0 and v <= float(MAX_WEIGHT_TOTAL)
	return false


## Peso já validado por _check_type (_is_weight); qualquer outro valor conta 0.
static func _weight(v: Variant) -> int:
	return int(v) if _is_weight(v) else 0


# --- colecionáveis e cartas ------------------------------------------------------------------------

static func _reserved(slot: int) -> Dictionary:
	return {"kind": KIND_RESERVED, "slot": slot}


static func _reserved_slots(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(_reserved(i))
	return out


## Exatamente n entradas, uma por slot (na ordem). Entrada ausente ou inválida volta a ser
## "reserved"; "slot" é sempre o índice e "kind" nunca fica vazio.
static func _normalize_collectibles(piped: Variant, n: int) -> Array:
	var out: Array = []
	for i in n:
		var entry: Variant = piped[i] if piped is Array and i < piped.size() else null
		if not (entry is Dictionary) or str(entry.get("kind", "")) == "":
			out.append(_reserved(i))
			continue
		var e: Dictionary = entry.duplicate(true)
		e["slot"] = i
		out.append(e)
	return out


static func _cards(athletes: Array, collectibles: Array) -> Array:
	var cards: Array = []
	for a in athletes:
		cards.append({
			"kind": KIND_ATHLETE, "athlete_id": a.id, "tier": a.tier(), "name": a.name,
			"position": a.position, "nationality": a.nationality,
			"face": a.dna.get("face", {}).duplicate(true),
		})
	for c in collectibles:
		cards.append(c.duplicate(true))
	return cards


# --- dados ---------------------------------------------------------------------------------------

func _types() -> Dictionary:
	var t: Variant = param("types", {})
	return t if t is Dictionary else {}


func _tier_order() -> Array:
	var out: Array = []
	var order: Variant = param("tier_order", [])
	if order is Array:
		for t in order:
			out.append(str(t))
	return out


## Inventário do clube só para leitura ([] se ainda não existir; não cria nada no clube).
func _inventory_of(club: Club) -> Array:
	var data: Variant = club.ext.get(id)
	if data is Dictionary and data.get("inventory") is Array:
		return data.inventory
	return []


func _inventory_for_write(club: Club) -> Array:
	var data := club.ext_for(id)
	if not (data.get("inventory") is Array):
		data["inventory"] = []
	return data.inventory


## Referência ao pacote dentro do inventário ({} se não achar).
func _find_pack(club: Club, pack_id: String) -> Dictionary:
	if pack_id == "":
		return {}
	for p in _inventory_of(club):
		if p is Dictionary and str(p.get("id", "")) == pack_id:
			return p
	return {}


## IDs de pacotes já usados no mundo (todos os clubes) e no clube do payload.
func _pack_ids(world: World, club: Club) -> Dictionary:
	var taken := {}
	var clubs: Array = world.clubs.values()
	clubs.append(club)
	for c in clubs:
		for p in _inventory_of(c):
			if p is Dictionary:
				taken[str(p.get("id", ""))] = true
	return taken


static func _is_valid_seed(v: Variant) -> bool:
	if v is int:
		return v >= 0 and v < AthleteDna.SEED_LIMIT
	if v is float:
		return v == floorf(v) and v >= 0.0 and v < float(AthleteDna.SEED_LIMIT)
	return false


static func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "error": code, "detail": detail}


static func _open_fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "error": code, "detail": detail, "needed_slots": 0}
