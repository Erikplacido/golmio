extends Mechanic
## Gerador de atletas (GDD 5.3 e 5.4; docs/RETRATOS.md 4.4). Camada meta, AUTORITATIVA NO
## SERVIDOR: roda headless, lê o catálogo de retratos só como JSON (nunca abre PNG) e é
## determinística. Mesma semente + mesmos parâmetros + mesmo catálogo = mesmos atletas, bit a
## bit, em qualquer plataforma. Não há autoload: tudo passa pelos hooks de provides_hooks.
##
## ALGORITMO DE UM ATLETA (i-ésimo do lote)
##   Semente do atleta: s_i = AthleteDna.derive_seed(seed_do_lote, "athlete:<i>").
##   Cada aspecto usa um fluxo próprio de SeededRng(s_i). Mudar a regra de um aspecto não muda
##   os outros:
##   1. fork("identity"): posição por peso (position_weights). A posição é SEMPRE sorteada; a
##      forçada pelo payload só é aplicada depois, então nacionalidade e nome não dependem dela.
##      Depois vem a nacionalidade por peso (nationality_weights) e o nome = primeiro nome +
##      sobrenome do pool do país (names.json).
##   2. fork("face"): cabeça por peso entre as peças "active". Depois, na ordem de
##      catalog.face_slots: o slot opcional rola a chance de draw_rules (se falhar, fica ""); o
##      slot escolhe por peso entre as peças "active" que não formem par rejeitado
##      (validation.rejected) com a cabeça. Com avoid_conflicts, também evita os trios de
##      validation.conflicts com peças já escolhidas. Pesos = round(weight × 1000), IDs em ordem
##      alfabética. Paletas não vazias sorteiam índices skin/hair_color.
##   3. fork("attributes"): ver _draw_attributes (orçamento exato, especialidades, fora do perfil).
##   4. fork("uuid"): athlete.id = UUID v4 (AthleteDna.uuid_v4_from_rng). Se colidir com
##      world.athletes ou com o lote, continua o mesmo fluxo.
##
## UNICIDADE (unique = true): um face_hash repetido (no registro do mundo ou no próprio lote)
## redesenha o rosto CONTINUANDO o mesmo fluxo; o mesmo vale para attributes_hash. Depois de
## max_attempts desenhos -> "uniqueness_exhausted". Com unique = false (atletas de IA), o registro
## não é consultado nem gravado.
##
## LOTE: tudo ou nada. Com commit = true, world.athletes e o registro só são gravados se os count
## atletas saírem; com commit = false nada é gravado (quem chama pode registrar depois com
## athlete_generator.register).
##
## Registro de unicidade (dados desta mecânica): world.ext["athlete_generator"] =
##   {"face_hashes": {hash: athlete_id}, "attribute_hashes": {hash: athlete_id},
##    "dna_hashes": {hash: athlete_id}}

const HOOK_GENERATE := "athlete_generator.generate"
const HOOK_REGISTER := "athlete_generator.register"
const HOOK_VALIDATE := "athlete_generator.validate"
const NAMES_PATH := "res://mechanics/athlete_generator/names.json"
## Chave do registro em world.ext[id] -> campo do DNA com o hash correspondente.
const REGISTRY_FIELDS := {
	"face_hashes": "face_hash",
	"attribute_hashes": "attributes_hash",
	"dna_hashes": "dna_hash",
}
## Pesos (catálogo e params) viram inteiros: round(peso × WEIGHT_SCALE).
const WEIGHT_SCALE := 1000.0
## SeededRng.int_between usa o randi_range de 32 bits do Godot: a soma dos pesos JÁ ESCALADOS de
## um sorteio precisa caber em int32 (soma dos pesos crus <= ~2.147.483). Acima disso o sorteio
## sairia distorcido sem erro nenhum; generate recusa antes de sortear.
const MAX_WEIGHT_TOTAL := 2147483647
## Tabelas de pesos de params conferidas por _check_weight_totals.
const WEIGHT_PARAMS := ["position_weights", "nationality_weights"]

## JSON lido do disco (catálogo, nomes), por caminho. É cache de arquivo imutável, não estado
## de mecânica, e por isso é estático. Só guarda leituras bem-sucedidas.
static var _json_cache: Dictionary = {}


func _init() -> void:
	id = "athlete_generator"
	title = "Gerador de atletas"
	description = "Nascimento determinístico de atletas (DNA: rosto, atributos por tier, identidade) com unicidade por hash (GDD 5.3, 5.4; RETRATOS 4.4)."
	version = 1
	data_version = 1
	layer = "meta"
	stage = "experimental"
	enabled_by_default = false
	default_params = {
		"generator_version": "athlete_generator@1",
		"catalog_path": "res://data/portraits/catalog.json",
		"names_path": NAMES_PATH,
		## País cujo pool de nomes é usado quando a nacionalidade sorteada não tem pool.
		"fallback_names": "BR",
		"initial_age": 17,
		## Desenhos por atleta (primeiro + novos) antes de desistir por colisão de hash.
		"max_attempts": 32,
		## null = usar catalog.draw_rules. Dicionário = sobrepõe chaves (ex.: {"chance_hair": 1.0}).
		"draw_rules": null,
		## Também evitar os trios cabeça × peça × peça de catalog.validation.conflicts.
		"avoid_conflicts": true,
		## Raridade de nascimento. mean: [mín, máx] da média sorteada (inteira) dos atributos de
		## perfil; floor/cap: limites de cada atributo de perfil; specialties: [mín, máx] de
		## especialidades; specialty_min: valor mínimo de uma especialidade.
		"tiers": {
			"bronze":   {"label": "Normal",   "mean": [30, 42], "floor": 12, "cap": 58, "specialties": [0, 0], "specialty_min": 0},
			"prata":    {"label": "Raro",    "mean": [42, 52], "floor": 18, "cap": 68, "specialties": [0, 1], "specialty_min": 62},
			"ouro":     {"label": "Lendário",     "mean": [52, 62], "floor": 25, "cap": 78, "specialties": [1, 1], "specialty_min": 72},
			"diamante": {"label": "Mítico", "mean": [62, 72], "floor": 32, "cap": 88, "specialties": [1, 2], "specialty_min": 82},
			"deus":     {"label": "Divino",     "mean": [72, 80], "floor": 40, "cap": 95, "specialties": [2, 3], "specialty_min": 90},
		},
		"position_weights": {"GK": 10, "DEF": 32, "MID": 33, "FWD": 25},
		## Atributos de PERFIL de cada posição e o peso relativo de cada um (100 = na média).
		## Os atributos que não aparecem aqui são "fora do perfil" (off_profile).
		"position_profiles": {
			"GK": {"reflexes": 115, "positioning": 105, "elasticity": 110, "stamina": 70},
			"DEF": {"pace": 95, "physical": 120, "passing": 90, "finishing": 55, "tackling": 130, "positioning": 125, "stamina": 85},
			"MID": {"pace": 95, "physical": 90, "passing": 130, "finishing": 85, "tackling": 95, "positioning": 100, "stamina": 105},
			"FWD": {"pace": 120, "physical": 95, "passing": 85, "finishing": 140, "tackling": 50, "positioning": 115, "stamina": 95},
		},
		## Faixas [mín, máx] dos atributos fora do perfil: habilidades de goleiro num jogador de
		## linha e habilidades de linha num goleiro.
		"off_profile": {"outfield_gk_skills": [3, 18], "gk_outfield_skills": [15, 45]},
		## Ruído inteiro somado a cada atributo de perfil: uniforme em [-noise, +noise].
		"noise": 6,
		## Especialidades saem entre os specialty_pool atributos de maior peso da posição...
		"specialty_pool": 3,
		## ...e sempre sobram pelo menos specialty_min_donors atributos de perfil para compensar.
		"specialty_min_donors": 2,
		## Soma 1000: Brasil com 45%.
		"nationality_weights": {
			"BR": 450, "AR": 80, "PT": 70, "ES": 45, "FR": 45, "UY": 40, "CO": 40, "IT": 40,
			"DE": 35, "CL": 25, "PY": 25, "MX": 25, "NG": 25, "NL": 20, "EC": 20, "JP": 15,
		},
	}
	provides_hooks = {
		HOOK_GENERATE: "decide {world: World, count: int, seed: int, tiers: Array (um tier por atleta), origin: Dictionary (com source), unique: bool = true, commit: bool = true, positions: Array opcional (\"\" = sortear), catalog: Dictionary opcional (substitui o catálogo; testes)} -> {ok: true, athletes: Array[Athlete]} | {ok: false, error: invalid_payload|unknown_tier|invalid_params|catalog_unavailable|catalog_exhausted|uniqueness_exhausted|invalid_dna, detail: String}. Tudo ou nada; commit=false não grava nada.",
		HOOK_REGISTER: "decide {world, athletes: Array[Athlete]} -> {ok: bool, error: String, detail: String}. Registra face/attributes/dna_hash de atletas gerados com commit=false. Recusa o lote inteiro (error collision|invalid_athlete|invalid_payload) se algum hash já pertencer a outro atleta.",
		HOOK_VALIDATE: "decide {world, athlete: Athlete, catalog: Dictionary opcional} -> {ok: bool, errors: Array[String]}. Recalcula os hashes (AthleteDna.verify), confere o UUID, os IDs da receita no catálogo, os pares rejeitados e o registro de unicidade.",
	}


func install(bus: HookBus) -> void:
	bus.on(HOOK_GENERATE, _on_generate, id)
	bus.on(HOOK_REGISTER, _on_register, id)
	bus.on(HOOK_VALIDATE, _on_validate, id)


# --- hook: generate --------------------------------------------------------------------------

func _on_generate(payload: Dictionary) -> Dictionary:
	var world_v: Variant = payload.get("world")
	if not (world_v is World):
		return _fail("invalid_payload", "world ausente")
	var world: World = world_v
	var seed_v: Variant = payload.get("seed")
	if not (seed_v is int or seed_v is float):
		return _fail("invalid_payload", "seed ausente (o servidor fornece a entropia; ver Backend.new_seed)")
	var batch_seed := int(seed_v)
	var count := int(payload.get("count", 0))
	if count < 0:
		return _fail("invalid_payload", "count negativo")
	var tiers := Array(payload.get("tiers", []))
	if tiers.size() < count:
		return _fail("invalid_payload", "tiers tem %d itens para %d atletas" % [tiers.size(), count])
	var positions := Array(payload.get("positions", []))
	var origin_v: Variant = payload.get("origin", {})
	if not (origin_v is Dictionary) or str(origin_v.get("source", "")) == "":
		return _fail("invalid_payload", "origin.source ausente")
	var origin: Dictionary = origin_v
	var unique := bool(payload.get("unique", true))
	var commit := bool(payload.get("commit", true))

	var tier_defs: Dictionary = param("tiers", {})
	var profiles: Dictionary = param("position_profiles", {})
	for i in count:
		if not (tier_defs.get(str(tiers[i])) is Dictionary):
			return _fail("unknown_tier", "tier desconhecido: %s" % str(tiers[i]))
		var forced := str(positions[i]) if i < positions.size() else ""
		if forced != "" and not AthleteDna.POSITIONS.has(forced):
			return _fail("invalid_payload", "posição inválida: %s" % forced)

	var catalog := _catalog_for(payload)
	if catalog.is_empty():
		return _fail("catalog_unavailable", "catálogo ausente ou inválido: %s" % str(param("catalog_path")))
	var index := _index_catalog(catalog, param("draw_rules"), bool(param("avoid_conflicts", true)))
	if str(index.version) == "":
		return _fail("catalog_unavailable", "catálogo sem version")
	if not (index.overweight as Array).is_empty():
		return _fail("catalog_unavailable", "soma dos pesos de %s passa de %d (limite do sorteio de 32 bits)"
			% [", ".join(PackedStringArray(index.overweight)), MAX_WEIGHT_TOTAL])
	var weight_problem := _check_weight_totals()
	if weight_problem != "":
		return _fail("invalid_params", weight_problem)

	# Leitura apenas: o registro só é criado/gravado no commit.
	var registry_data := _registry_of(world)
	var batch := {"ids": {}}
	for rk in REGISTRY_FIELDS:
		batch[rk] = {}
	var made: Array[Athlete] = []
	for i in count:
		var forced := str(positions[i]) if i < positions.size() else ""
		if forced != "" and not (profiles.get(forced) is Dictionary):
			return _fail("invalid_params", "position_profiles sem a posição %s" % forced)
		var res := _make_athlete(world, index, AthleteDna.derive_seed(batch_seed, "athlete:%d" % i),
			str(tiers[i]), forced, origin, unique, registry_data, batch)
		if not bool(res.ok):
			res["detail"] = "atleta %d: %s" % [i, str(res.get("detail", ""))]
			return res
		var a: Athlete = res.athlete
		made.append(a)
		batch.ids[a.id] = true
		if unique:
			for rk in REGISTRY_FIELDS:
				batch[rk][str(a.dna[REGISTRY_FIELDS[rk]])] = a.id

	if commit:
		for a in made:
			world.add_athlete(a)
		if unique and not made.is_empty():
			_write_registry(world, made)
	return {"ok": true, "athletes": made}


## Um atleta completo (ainda fora do mundo). Devolve {ok, athlete} ou um erro.
func _make_athlete(world: World, index: Dictionary, athlete_seed: int, tier_id: String,
		forced_position: String, origin: Dictionary, unique: bool, registry_data: Dictionary,
		batch: Dictionary) -> Dictionary:
	var root := SeededRng.new(athlete_seed)
	var max_attempts := maxi(1, int(param("max_attempts", 32)))

	var ident := _draw_identity(root.fork("identity"), forced_position)
	if not bool(ident.ok):
		return ident
	var position := str(ident.position)

	var face := {}
	var face_rng := root.fork("face")
	var attempts := 0
	while true:
		attempts += 1
		var drawn := _draw_face(face_rng, index)
		if not bool(drawn.ok):
			return drawn
		face = drawn.face
		if not unique or not _is_taken(registry_data, batch, "face_hashes", AthleteDna.face_hash(face)):
			break
		if attempts >= max_attempts:
			return _fail("uniqueness_exhausted", "rosto repetido em %d desenhos" % attempts)

	var tier: Dictionary = param("tiers", {})[tier_id]
	var base := {}
	var attr_rng := root.fork("attributes")
	attempts = 0
	while true:
		attempts += 1
		var drawn := _draw_attributes(attr_rng, tier, position)
		if not bool(drawn.ok):
			return drawn
		base = drawn.base
		if not unique or not _is_taken(registry_data, batch, "attribute_hashes", AthleteDna.attributes_hash(base)):
			break
		if attempts >= max_attempts:
			return _fail("uniqueness_exhausted", "atributos repetidos em %d desenhos" % attempts)

	var dna := AthleteDna.seal({
		"generator": str(param("generator_version")),
		"seed": athlete_seed,
		"catalog": str(index.version),
		"face": face,
		"nationality": str(ident.nationality),
		"position": position,
		"tier": tier_id,
		"initial_age": int(param("initial_age", 17)),
		"base_attributes": base,
		"birth_name": str(ident.birth_name),
		"origin": origin,
	})
	# Rede de segurança do servidor: nunca devolver um DNA que o núcleo recusaria (ex.: ruleset
	# com nacionalidade minúscula, origin com valor não canônico).
	var problems := AthleteDna.verify(dna)
	if not problems.is_empty():
		return _fail("invalid_dna", "; ".join(PackedStringArray(problems.slice(0, 3))))
	# Com rosto e atributos inéditos o dna_hash também é inédito; conferir custa pouco.
	if unique and _is_taken(registry_data, batch, "dna_hashes", str(dna.dna_hash)):
		return _fail("uniqueness_exhausted", "dna_hash repetido")

	var a := Athlete.new()
	a.id = _unique_uuid(root.fork("uuid"), world, batch.ids)
	a.name = str(ident.birth_name)
	a.nationality = str(ident.nationality)
	a.position = position
	a.status = "active"
	for k in base:
		a.attributes[k] = float(base[k])
	a.dna = dna
	return {"ok": true, "athlete": a}


static func _is_taken(registry_data: Dictionary, batch: Dictionary, key: String, h: String) -> bool:
	var reg: Variant = registry_data.get(key)
	return (reg is Dictionary and reg.has(h)) or batch[key].has(h)


static func _unique_uuid(rng: SeededRng, world: World, batch_ids: Dictionary) -> String:
	var aid := AthleteDna.uuid_v4_from_rng(rng)
	while world.athletes.has(aid) or batch_ids.has(aid):
		aid = AthleteDna.uuid_v4_from_rng(rng)
	return aid


## Registro de unicidade do mundo (só leitura; {} se ainda não existir).
func _registry_of(world: World) -> Dictionary:
	var data: Variant = world.ext.get(id)
	return data if data is Dictionary else {}


func _write_registry(world: World, athletes: Array) -> void:
	if not (world.ext.get(id) is Dictionary):
		world.ext[id] = {}
	var data: Dictionary = world.ext[id]
	for rk in REGISTRY_FIELDS:
		if not (data.get(rk) is Dictionary):
			data[rk] = {}
	for a in athletes:
		for rk in REGISTRY_FIELDS:
			data[rk][str(a.dna[REGISTRY_FIELDS[rk]])] = a.id


# --- identidade --------------------------------------------------------------------------------

func _draw_identity(rng: SeededRng, forced_position: String) -> Dictionary:
	var pos_weights := {}
	var pw: Dictionary = param("position_weights", {})
	for p in AthleteDna.POSITIONS:
		if pw.has(p):
			pos_weights[p] = pw[p]
	var position := _pick_weighted_key(rng, pos_weights)
	if forced_position != "":
		position = forced_position
	if position == "":
		return _fail("invalid_params", "position_weights sem peso positivo")
	var nationality := _pick_weighted_key(rng, param("nationality_weights", {}))
	if nationality == "":
		return _fail("invalid_params", "nationality_weights sem peso positivo")
	return {"ok": true, "position": position, "nationality": nationality,
		"birth_name": _draw_name(rng, nationality)}


func _draw_name(rng: SeededRng, nationality: String) -> String:
	var pools := _load_json(str(param("names_path", NAMES_PATH)))
	var pool: Variant = pools.get(nationality, pools.get(str(param("fallback_names", "BR"))))
	var parts := PackedStringArray()
	if pool is Dictionary:
		for key in ["first", "last"]:
			var options: Variant = pool.get(key, [])
			if options is Array and not options.is_empty():
				parts.append(str(options[rng.int_between(0, options.size() - 1)]))
	if parts.is_empty():
		return "Atleta %s" % nationality
	return " ".join(parts)


# --- rosto -------------------------------------------------------------------------------------

## Receita visual: todas as chaves de AthleteDna.FACE_KEYS (peça ausente = "").
static func _draw_face(rng: SeededRng, index: Dictionary) -> Dictionary:
	var face := {}
	for k in AthleteDna.FACE_KEYS:
		face[k] = ""
	var head := _pick_weighted(rng, index.active.get("head", []), index.weights)
	if head == "":
		return _fail("catalog_exhausted", "nenhuma cabeça ativa no catálogo")
	face["head"] = head
	var banned: Dictionary = index.rejected.get(head, {})
	var head_conflicts: Dictionary = index.conflicts.get(head, {})
	var chosen: Array = []
	for slot in index.face_slots:
		var optional: bool = index.chances.has(slot)
		if optional and not rng.chance(float(index.chances[slot])):
			continue
		var candidates: Array = []
		for pid in index.active.get(slot, []):
			if banned.has(pid) or _conflicts_with(head_conflicts, pid, chosen):
				continue
			candidates.append(pid)
		var pick := _pick_weighted(rng, candidates, index.weights)
		if pick == "":
			if optional:
				continue
			return _fail("catalog_exhausted", "nenhuma peça de '%s' serve na cabeça %s" % [slot, head])
		face[slot] = pick
		chosen.append(pick)
	if int(index.skin_count) > 0:
		face["skin"] = rng.int_between(0, int(index.skin_count) - 1)
	if int(index.hair_count) > 0:
		face["hair_color"] = rng.int_between(0, int(index.hair_count) - 1)
	return {"ok": true, "face": face}


static func _conflicts_with(head_conflicts: Dictionary, pid: String, chosen: Array) -> bool:
	var others: Variant = head_conflicts.get(pid)
	if not (others is Dictionary):
		return false
	for c in chosen:
		if others.has(c):
			return true
	return false


## Pré-processa o catálogo para o sorteio: peças ativas por slot (IDs em ordem alfabética),
## pesos inteiros, chances dos slots opcionais, pares rejeitados e trios em conflito por cabeça.
static func _index_catalog(catalog: Dictionary, rules_override: Variant, avoid_conflicts: bool) -> Dictionary:
	var weights := {}
	var active := {}
	var overweight: Array = []
	var parts: Variant = catalog.get("parts", {})
	if parts is Dictionary:
		for slot in parts:
			var slot_parts: Variant = parts[slot]
			if not (slot_parts is Dictionary):
				continue
			var ids: Array = slot_parts.keys()
			ids.sort()
			var usable: Array = []
			var total := 0.0
			for pid in ids:
				var p: Variant = slot_parts[pid]
				if not (p is Dictionary) or str(p.get("status", "")) != "active":
					continue
				var scaled := roundf(float(p.get("weight", 1)) * WEIGHT_SCALE)
				if not (scaled > 0.0):
					continue
				total += scaled
				weights[str(pid)] = int(minf(scaled, float(MAX_WEIGHT_TOTAL)))
				usable.append(str(pid))
			if total > float(MAX_WEIGHT_TOTAL):
				overweight.append(str(slot))
			active[str(slot)] = usable
	overweight.sort()

	var face_slots: Array = []
	var declared: Variant = catalog.get("face_slots")
	if not (declared is Array):
		declared = AthleteDna.FACE_KEYS
	for slot in declared:
		if str(slot) != "head" and AthleteDna.FACE_KEYS.has(str(slot)):
			face_slots.append(str(slot))

	var rules := {}
	if catalog.get("draw_rules") is Dictionary:
		rules = catalog.draw_rules.duplicate()
	if rules_override is Dictionary:
		rules.merge(rules_override, true)
	var chances := {}
	var optional: Variant = catalog.get("optional_slots", {})
	if optional is Dictionary:
		for slot in optional:
			chances[str(slot)] = float(rules.get(str(optional[slot]), 1.0))

	var rejected := {}
	var conflicts := {}
	var validation: Variant = catalog.get("validation", {})
	if validation is Dictionary:
		for pair in validation.get("rejected", []):
			if pair is Array and pair.size() >= 2:
				var head := str(pair[0])
				if not rejected.has(head):
					rejected[head] = {}
				rejected[head][str(pair[1])] = true
		if avoid_conflicts:
			for trio in validation.get("conflicts", []):
				if trio is Array and trio.size() >= 3:
					_add_conflict(conflicts, str(trio[0]), str(trio[1]), str(trio[2]))
					_add_conflict(conflicts, str(trio[0]), str(trio[2]), str(trio[1]))

	var palettes: Variant = catalog.get("palettes", {})
	var skin_count := 0
	var hair_count := 0
	if palettes is Dictionary:
		if palettes.get("skin") is Array:
			skin_count = palettes.skin.size()
		if palettes.get("hair") is Array:
			hair_count = palettes.hair.size()
	return {
		"version": str(catalog.get("version", "")), "weights": weights, "active": active,
		"face_slots": face_slots, "chances": chances, "rejected": rejected, "conflicts": conflicts,
		"skin_count": skin_count, "hair_count": hair_count, "overweight": overweight,
	}


static func _add_conflict(conflicts: Dictionary, head: String, a: String, b: String) -> void:
	if not conflicts.has(head):
		conflicts[head] = {}
	if not conflicts[head].has(a):
		conflicts[head][a] = {}
	conflicts[head][a][b] = true


# --- atributos ---------------------------------------------------------------------------------

## Os 9 atributos base (inteiros 1..99) de um atleta de `tier` na posição `position`:
##   1. Perfil = atributos de position_profiles[posição] (N = 7 na linha, 4 no goleiro).
##      mean = inteiro sorteado em tier.mean (limitado a [floor, cap]); budget = mean × N.
##   2. Base: budget repartido pelos pesos do perfil (maiores restos, só inteiros): soma = budget.
##   3. Ruído: cada atributo de perfil recebe um inteiro uniforme em [-noise, +noise] e é
##      limitado a [floor, cap]. Reparo determinístico: a diferença para o budget é
##      redistribuída pelos pesos entre os atributos com folga até a soma voltar a ser
##      EXATAMENTE budget.
##   4. Especialidades: k em tier.specialties (no máximo N - specialty_min_donors), escolhidos
##      entre os specialty_pool atributos de maior peso. Cada um abaixo de specialty_min sobe para
##      um alvo sorteado em [specialty_min, cap]. O ganho sai dos atributos de perfil não
##      escolhidos, na proporção da folga de cada um acima do floor: a soma continua exata e
##      nenhum fura o floor. Se a folga não permitir chegar a specialty_min, aquela
##      especialidade é descartada. Com os tiers padrão isso não acontece.
##   5. Fora do perfil: uniforme em off_profile.outfield_gk_skills (linha) ou
##      off_profile.gk_outfield_skills (goleiro).
func _draw_attributes(rng: SeededRng, tier: Dictionary, position: String) -> Dictionary:
	var profile: Variant = param("position_profiles", {}).get(position)
	if not (profile is Dictionary):
		return _fail("invalid_params", "position_profiles sem a posição %s" % position)
	var ids: Array = []
	var weights := {}
	for k in AthleteDna.BASE_ATTRIBUTE_IDS:
		if profile.has(k):
			ids.append(k)
			weights[k] = maxi(0, int(round(float(profile[k]) * WEIGHT_SCALE)))
	if ids.is_empty():
		return _fail("invalid_params", "perfil vazio para %s" % position)
	var lo := clampi(int(tier.get("floor", AthleteDna.ATTRIBUTE_MIN)), AthleteDna.ATTRIBUTE_MIN, AthleteDna.ATTRIBUTE_MAX)
	var hi := clampi(int(tier.get("cap", AthleteDna.ATTRIBUTE_MAX)), lo, AthleteDna.ATTRIBUTE_MAX)
	var mean_range: Variant = tier.get("mean", [lo, hi])
	if not (mean_range is Array) or mean_range.size() < 2:
		return _fail("invalid_params", "tier.mean deve ser [mín, máx]")
	var mean := clampi(rng.int_between(int(mean_range[0]), int(mean_range[1])), lo, hi)
	var budget := mean * ids.size()

	var values := _apportion(budget, ids, weights)
	var noise := maxi(0, int(param("noise", 0)))
	for k in ids:
		values[k] = clampi(int(values[k]) + rng.int_between(-noise, noise), lo, hi)
	_repair_sum(values, ids, weights, budget, lo, hi)
	_apply_specialties(rng, values, ids, weights, tier, lo, hi)

	var off: Variant = param("off_profile", {})
	var off_key := "gk_outfield_skills" if position == "GK" else "outfield_gk_skills"
	var off_range: Variant = off.get(off_key, []) if off is Dictionary else []
	if not (off_range is Array) or off_range.size() < 2:
		return _fail("invalid_params", "off_profile.%s deve ser [mín, máx]" % off_key)
	var base := {}
	for k in AthleteDna.BASE_ATTRIBUTE_IDS:
		if values.has(k):
			base[k] = int(values[k])
		else:
			base[k] = clampi(rng.int_between(int(off_range[0]), int(off_range[1])),
				AthleteDna.ATTRIBUTE_MIN, AthleteDna.ATTRIBUTE_MAX)
	return {"ok": true, "base": base, "mean": mean}


func _apply_specialties(rng: SeededRng, values: Dictionary, ids: Array, weights: Dictionary,
		tier: Dictionary, lo: int, hi: int) -> void:
	var spec: Variant = tier.get("specialties", [0, 0])
	if not (spec is Array) or spec.size() < 2:
		return
	var k := rng.int_between(int(spec[0]), int(spec[1]))
	k = mini(k, maxi(0, ids.size() - int(param("specialty_min_donors", 2))))
	if k <= 0:
		return
	var smin := clampi(int(tier.get("specialty_min", 0)), lo, hi)
	var ranked := ids.duplicate()
	ranked.sort_custom(func(a: String, b: String) -> bool:
		if weights[a] != weights[b]:
			return weights[a] > weights[b]
		return ids.find(a) < ids.find(b))
	var pool := ranked.slice(0, clampi(maxi(int(param("specialty_pool", 3)), k), 0, ranked.size()))
	var chosen: Array = []
	for _j in k:
		var at := rng.int_between(0, pool.size() - 1)
		chosen.append(pool[at])
		pool.remove_at(at)
	var donors: Array = ids.filter(func(x: String) -> bool: return not chosen.has(x))
	for sp in chosen:
		var target := rng.int_between(smin, hi)
		var cur := int(values[sp])
		if cur >= smin:
			continue
		var slack := {}
		var total_slack := 0
		for d in donors:
			slack[d] = int(values[d]) - lo
			total_slack += int(slack[d])
		var gain := mini(target - cur, total_slack)
		if cur + gain < smin:
			continue
		values[sp] = cur + gain
		var take := _apportion(gain, donors, slack)
		for d in donors:
			values[d] = int(values[d]) - int(take[d])


## Reparte `total` (>= 0) entre `ids` na proporção de `weights`, só com inteiros (método dos
## maiores restos; empate: ordem de `ids`). A soma do resultado é exatamente `total` e, quando
## total <= soma dos pesos, ninguém recebe mais que o próprio peso (é o que garante o floor ao
## tirar pontos na proporção da folga). Pesos todos zero: divisão igual.
@warning_ignore("integer_division")
static func _apportion(total: int, ids: Array, weights: Dictionary) -> Dictionary:
	var out := {}
	if ids.is_empty():
		return out
	var w := {}
	var wsum := 0
	for k in ids:
		w[k] = maxi(0, int(weights.get(k, 0)))
		wsum += int(w[k])
	if wsum <= 0:
		for k in ids:
			w[k] = 1
		wsum = ids.size()
	var given := 0
	var rems: Array = []
	for i in ids.size():
		var num := total * int(w[ids[i]])
		out[ids[i]] = num / wsum
		given += int(out[ids[i]])
		rems.append([num % wsum, i])
	rems.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] > b[0]
		return a[1] < b[1])
	for j in total - given:
		var at: int = rems[j % rems.size()][1]
		out[ids[at]] = int(out[ids[at]]) + 1
	return out


## Traz a soma de `values[ids]` de volta a `target` sem sair de [lo, hi]: a diferença é
## repartida pelos pesos entre os atributos com folga na direção necessária; quem satura sai
## da rodada seguinte. Termina em no máximo N + 1 rodadas.
static func _repair_sum(values: Dictionary, ids: Array, weights: Dictionary, target: int, lo: int, hi: int) -> void:
	for _round in ids.size() + 2:
		var sum := 0
		for k in ids:
			sum += int(values[k])
		var diff := target - sum
		if diff == 0:
			return
		var movable: Array = []
		var w := {}
		for k in ids:
			var v := int(values[k])
			if (diff > 0 and v < hi) or (diff < 0 and v > lo):
				movable.append(k)
				w[k] = maxi(1, int(weights.get(k, 0)))
		if movable.is_empty():
			return
		var share := _apportion(absi(diff), movable, w)
		for k in movable:
			var v := int(values[k])
			var room := hi - v if diff > 0 else v - lo
			var step := mini(int(share[k]), room)
			values[k] = v + step if diff > 0 else v - step


# --- sorteio por peso --------------------------------------------------------------------------

## Escolhe um id de `ids` (já em ordem estável) com probabilidade proporcional a weights[id].
## "" se não houver peso positivo.
static func _pick_weighted(rng: SeededRng, ids: Array, weights: Dictionary) -> String:
	var total := 0
	for pid in ids:
		total += maxi(0, int(weights.get(pid, 0)))
	if total <= 0:
		return ""
	if total > MAX_WEIGHT_TOTAL:
		# generate recusa esses pesos antes de sortear; nunca sortear distorcido em silêncio.
		push_error("athlete_generator: soma de pesos %d passa do limite de 32 bits" % total)
		return ""
	var r := rng.int_between(0, total - 1)
	for pid in ids:
		var w := maxi(0, int(weights.get(pid, 0)))
		if r < w:
			return str(pid)
		r -= w
	return ""


## "" se as tabelas de pesos de params cabem no sorteio de 32 bits; senão, o motivo.
func _check_weight_totals() -> String:
	for key in WEIGHT_PARAMS:
		var total := _scaled_total(param(key, {}))
		if total > float(MAX_WEIGHT_TOTAL):
			return "soma de %s × %d passa de %d (limite do sorteio de 32 bits): use pesos menores" \
				% [key, int(WEIGHT_SCALE), MAX_WEIGHT_TOTAL]
	return ""


## Soma dos pesos de uma tabela {chave: peso} como _pick_weighted_key a usa (round(peso × 1000),
## só os positivos), em float para não estourar.
static func _scaled_total(table: Variant) -> float:
	var total := 0.0
	if table is Dictionary:
		for k in table:
			total += maxf(0.0, roundf(float(table[k]) * WEIGHT_SCALE))
	return total


## Chave de um dicionário {chave: peso} por peso (round(peso × 1000)), chaves em ordem alfabética.
static func _pick_weighted_key(rng: SeededRng, table: Variant) -> String:
	if not (table is Dictionary):
		return ""
	var keys: Array = table.keys()
	keys.sort()
	var weights := {}
	var ids: Array = []
	for k in keys:
		var scaled := roundf(float(table[k]) * WEIGHT_SCALE)
		if scaled > 0.0:
			ids.append(str(k))
			weights[str(k)] = int(minf(scaled, float(MAX_WEIGHT_TOTAL) + 1.0))
	return _pick_weighted(rng, ids, weights)


# --- hook: register ----------------------------------------------------------------------------

func _on_register(payload: Dictionary) -> Dictionary:
	var world_v: Variant = payload.get("world")
	if not (world_v is World):
		return {"ok": false, "error": "invalid_payload", "detail": "world ausente"}
	var world: World = world_v
	var list_v: Variant = payload.get("athletes", [])
	if not (list_v is Array):
		return {"ok": false, "error": "invalid_payload", "detail": "athletes deve ser Array"}
	var data := _registry_of(world)
	var seen := {}
	for rk in REGISTRY_FIELDS:
		seen[rk] = {}
	var athletes: Array = []
	for item in list_v:
		if not (item is Athlete):
			return {"ok": false, "error": "invalid_payload", "detail": "item não é Athlete"}
		var a: Athlete = item
		var expected := AthleteDna.compute_hashes(a.dna)
		for rk in REGISTRY_FIELDS:
			var field: String = REGISTRY_FIELDS[rk]
			var h := str(a.dna.get(field, ""))
			if h == "" or h != expected[field]:
				return {"ok": false, "error": "invalid_athlete", "detail": "%s: %s ausente ou divergente" % [a.id, field]}
			var owner: Variant = data.get(rk, {}).get(h) if data.get(rk) is Dictionary else null
			if owner != null and str(owner) != a.id:
				return {"ok": false, "error": "collision", "detail": "%s de %s já pertence a %s" % [field, a.id, str(owner)]}
			if seen[rk].has(h) and seen[rk][h] != a.id:
				return {"ok": false, "error": "collision", "detail": "%s repetido no lote (%s e %s)" % [field, seen[rk][h], a.id]}
			seen[rk][h] = a.id
		athletes.append(a)
	_write_registry(world, athletes)
	return {"ok": true, "error": "", "detail": ""}


# --- hook: validate ----------------------------------------------------------------------------

func _on_validate(payload: Dictionary) -> Dictionary:
	var a_v: Variant = payload.get("athlete")
	if a_v is Dictionary:
		a_v = Athlete.from_dict(a_v)
	if not (a_v is Athlete):
		return {"ok": false, "errors": ["athlete ausente"]}
	var athlete: Athlete = a_v
	var errors: Array = AthleteDna.verify(athlete.dna)
	if not AthleteDna.is_uuid_v4(athlete.id):
		errors.append("id não é UUID v4: %s" % athlete.id)
	var catalog := _catalog_for(payload)
	if catalog.is_empty():
		errors.append("catálogo indisponível: %s" % str(param("catalog_path")))
	else:
		_check_face_in_catalog(athlete.dna.get("face"), catalog, errors)
	var world_v: Variant = payload.get("world")
	if world_v is World:
		var data := _registry_of(world_v)
		for rk in REGISTRY_FIELDS:
			var field: String = REGISTRY_FIELDS[rk]
			var h := str(athlete.dna.get(field, ""))
			var owner: Variant = data.get(rk, {}).get(h) if data.get(rk) is Dictionary else null
			if owner != null and str(owner) != athlete.id:
				errors.append("%s registrado para outro atleta (%s)" % [field, str(owner)])
	return {"ok": errors.is_empty(), "errors": errors}


## Confere a receita contra o catálogo: IDs existentes (qualquer status: peça aposentada continua
## válida em quem já a tem), slots obrigatórios preenchidos, pares rejeitados e índices de paleta.
static func _check_face_in_catalog(face_v: Variant, catalog: Dictionary, errors: Array) -> void:
	if not (face_v is Dictionary):
		return  # AthleteDna.verify já acusa
	var face: Dictionary = face_v
	var parts: Dictionary = catalog.get("parts", {}) if catalog.get("parts") is Dictionary else {}
	var optional: Dictionary = catalog.get("optional_slots", {}) if catalog.get("optional_slots") is Dictionary else {}
	var face_slots: Array = catalog.get("face_slots", AthleteDna.FACE_KEYS) if catalog.get("face_slots") is Array else AthleteDna.FACE_KEYS
	var version := str(catalog.get("version", "?"))
	for slot in AthleteDna.FACE_KEYS:
		var pid := str(face.get(slot, ""))
		if pid == "":
			if (slot == "head" or face_slots.has(slot)) and not optional.has(slot):
				errors.append("face.%s vazio, mas o slot é obrigatório no catálogo %s" % [slot, version])
			continue
		var slot_parts: Variant = parts.get(slot)
		if not (slot_parts is Dictionary) or not slot_parts.has(pid):
			errors.append("face.%s = %s não existe no catálogo %s" % [slot, pid, version])
	var validation: Variant = catalog.get("validation", {})
	if validation is Dictionary:
		var used := {}
		for slot in AthleteDna.FACE_KEYS:
			used[str(face.get(slot, ""))] = true
		for pair in validation.get("rejected", []):
			if pair is Array and pair.size() >= 2 and str(face.get("head", "")) == str(pair[0]) and used.has(str(pair[1])):
				errors.append("par rejeitado no catálogo %s: %s × %s" % [version, str(pair[0]), str(pair[1])])
	var palettes: Variant = catalog.get("palettes", {})
	for pair in [["skin", "skin"], ["hair_color", "hair"]]:
		if not face.has(pair[0]):
			continue
		var pal: Variant = palettes.get(pair[1]) if palettes is Dictionary else null
		var n: int = pal.size() if pal is Array else 0
		var idx := int(face[pair[0]])
		if idx < 0 or idx >= n:
			errors.append("face.%s = %d fora da paleta %s (%d cores)" % [pair[0], idx, pair[1], n])


# --- catálogo e arquivos -----------------------------------------------------------------------

## payload.catalog (dicionário não vazio) substitui o catálogo publicado (testes, ferramentas).
func _catalog_for(payload: Dictionary) -> Dictionary:
	var override: Variant = payload.get("catalog")
	if override is Dictionary and not override.is_empty():
		return override
	return _load_json(str(param("catalog_path")))


## JSON do disco com cache estático por caminho. {} se ausente ou inválido. O dicionário
## devolvido é compartilhado: só leitura.
static func _load_json(path: String) -> Dictionary:
	if _json_cache.has(path):
		return _json_cache[path]
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or parsed.is_empty():
		return {}
	_json_cache[path] = parsed
	return parsed


static func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "error": code, "detail": detail}
