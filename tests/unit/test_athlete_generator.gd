extends TestCase
## athlete_generator: determinismo, orçamento por tier, especialidades, perfis de goleiro e de
## linha, UUID e DNA íntegros, unicidade (registro do mundo e dentro do lote), atomicidade,
## pares rejeitados, chances dos slots opcionais, commit=false, register, validate,
## unique=false e catálogo real.

const MID := "athlete_generator"
const GENERATE := "athlete_generator.generate"
const REGISTER := "athlete_generator.register"
const VALIDATE := "athlete_generator.validate"
const DATE := "2026-09-27"
const REAL_CATALOG := "res://data/portraits/catalog.json"
const NAMES := "res://mechanics/athlete_generator/names.json"
const TIERS := ["bronze", "prata", "ouro", "diamante", "deus"]
const OUTFIELD_PROFILE := ["pace", "physical", "passing", "finishing", "tackling", "positioning", "stamina"]
const GK_PROFILE := ["reflexes", "positioning", "elasticity", "stamina"]
const SAMPLE_PER_TIER := 60
const FREQ_SAMPLE := 600


# --- apoio -------------------------------------------------------------------------------------

func _world() -> World:
	var w := World.new()
	w.date = DATE
	return w


func _origin() -> Dictionary:
	return {"source": "test", "pack_type": "", "pack_id": "", "club_id": "", "date": DATE}


func _repeat(v: Variant, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(v)
	return out


func _generate(reg: MechanicRegistry, world: World, p_seed: int, count: int, tier: String = "ouro",
		extra: Dictionary = {}) -> Dictionary:
	var payload := {"world": world, "count": count, "seed": p_seed, "tiers": _repeat(tier, count), "origin": _origin()}
	payload.merge(extra, true)
	var res: Variant = reg.bus.decide(GENERATE, payload)
	check(res is Dictionary, "generate precisa responder com a mecânica ligada")
	return res if res is Dictionary else {"ok": false, "error": "sem resposta", "athletes": []}


func _athletes(res: Dictionary) -> Array:
	return res.get("athletes", []) if bool(res.get("ok", false)) else []


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Catálogo de teste: `per_slot[slot]` peças ativas por slot (padrão 1); chances dos opcionais
## em `chances` (padrão 1.0 = sempre presentes); `extra` = peças adicionais por slot.
func _fake_catalog(per_slot: Dictionary = {}, chances: Dictionary = {}, rejected: Array = [],
		extra: Dictionary = {}, conflicts: Array = []) -> Dictionary:
	var parts := {}
	for slot in ["head", "ear", "eye", "eyebrow", "nose", "mouth", "chin", "skin_mark", "hair", "body", "arm"]:
		parts[slot] = {}
		for n in int(per_slot.get(slot, 1)):
			var pid := "%s_%03d" % [slot, n + 1]
			parts[slot][pid] = {"file": pid + ".png", "status": "active", "weight": 1}
	for slot in extra:
		for pid in extra[slot]:
			parts[slot][pid] = extra[slot][pid]
	return {
		"format": 1, "version": "teste-1",
		"face_slots": ["ear", "eye", "eyebrow", "nose", "mouth", "hair", "chin", "skin_mark", "body", "arm"],
		"optional_slots": {"hair": "chance_hair", "chin": "chance_chin", "skin_mark": "chance_skin_mark"},
		"draw_rules": {
			"chance_hair": float(chances.get("hair", 1.0)),
			"chance_chin": float(chances.get("chin", 1.0)),
			"chance_skin_mark": float(chances.get("skin_mark", 1.0)),
		},
		"palettes": {"skin": [], "hair": []},
		"parts": parts,
		"validation": {"rejected": rejected, "reasons": {}, "conflicts": conflicts},
	}


func _hash_set(athletes: Array, field: String) -> Dictionary:
	var out := {}
	for a in athletes:
		out[str(a.dna[field])] = true
	return out


# --- metadados ---------------------------------------------------------------------------------

func test_metadados_e_hooks() -> void:
	var reg := Fixtures.registry_with([MID])
	var m := reg.get_mechanic(MID)
	check(m != null, "mecânica descoberta e ligada")
	check_eq(m.layer, "meta")
	check_eq(m.stage, "experimental")
	check_eq(m.enabled_by_default, false, "experimental nasce desligada")
	for h in [GENERATE, REGISTER, VALIDATE]:
		check(m.provides_hooks.has(h), "provides_hooks declara %s" % h)
		check(reg.bus.has_handlers(h), "install registra %s" % h)
	var prod := Fixtures.registry()
	check(not prod.is_enabled(MID), "desligada no ruleset padrão")
	prod.dispose()
	reg.dispose()


# --- determinismo ------------------------------------------------------------------------------

func test_mesma_semente_gera_atletas_identicos() -> void:
	var reg := Fixtures.registry_with([MID])
	var r1 := _generate(reg, _world(), 12345, 3)
	var r2 := _generate(reg, _world(), 12345, 3)
	check(r1.ok and r2.ok, "gera: %s %s" % [str(r1.get("detail", "")), str(r2.get("detail", ""))])
	var a1 := _athletes(r1)
	var a2 := _athletes(r2)
	check_eq(a1.size(), 3)
	for i in mini(a1.size(), a2.size()):
		check_eq(a1[i].to_dict(), a2[i].to_dict(), "atleta %d idêntico" % i)
		check_eq(int(a1[i].dna.seed), AthleteDna.derive_seed(12345, "athlete:%d" % i), "semente derivada do lote")
	# O i-ésimo atleta não depende do tamanho do lote.
	var solo := _athletes(_generate(reg, _world(), 12345, 1))
	check(not solo.is_empty() and solo[0].to_dict() == a1[0].to_dict(), "atleta 0 igual num lote de 1")
	# Sementes diferentes, atletas diferentes.
	var a3 := _athletes(_generate(reg, _world(), 12346, 3))
	var faces_diff := 0
	for i in mini(a1.size(), a3.size()):
		check(a3[i].dna_hash() != a1[i].dna_hash(), "dna_hash muda com a semente")
		check(a3[i].id != a1[i].id, "id muda com a semente")
		if a3[i].dna.face_hash != a1[i].dna.face_hash:
			faces_diff += 1
	check(faces_diff >= 2, "rostos diferentes para sementes diferentes (%d de 3)" % faces_diff)
	reg.dispose()


# --- atributos ---------------------------------------------------------------------------------

func test_cada_tier_respeita_orcamento_piso_teto_e_especialidades() -> void:
	var reg := Fixtures.registry_with([MID])
	var tier_defs: Dictionary = reg.get_mechanic(MID).param("tiers")
	var off: Dictionary = reg.get_mechanic(MID).param("off_profile")
	var positions: Array = []
	for i in SAMPLE_PER_TIER:
		positions.append(["GK", "DEF", "MID", "FWD"][i % 4])
	var prev_avg := 0.0
	for tier in TIERS:
		var res := _generate(reg, _world(), 1000 + TIERS.find(tier), SAMPLE_PER_TIER, tier,
			{"positions": positions, "commit": false})
		check(res.ok, "%s: %s" % [tier, str(res.get("detail", ""))])
		var t: Dictionary = tier_defs[tier]
		var lo := int(t.floor)
		var hi := int(t.cap)
		var smin := int(t.specialty_min)
		var mean_sum := 0.0
		var list := _athletes(res)
		check_eq(list.size(), SAMPLE_PER_TIER, "%s: tamanho da amostra" % tier)
		for a in list:
			var base: Dictionary = a.dna.base_attributes
			check_eq(base.keys().size(), 9, "%s: 9 atributos" % tier)
			for k in AthleteDna.BASE_ATTRIBUTE_IDS:
				check(base.get(k) is int, "%s: %s inteiro" % [tier, k])
				check(int(base.get(k, 0)) >= 1 and int(base.get(k, 0)) <= 99, "%s: %s em 1..99" % [tier, k])
				check_eq(a.attributes.get(k), float(base.get(k, 0)), "%s: atributo atual = base" % tier)
			var gk: bool = a.position == "GK"
			var profile := GK_PROFILE if gk else OUTFIELD_PROFILE
			var total := 0
			var specials := 0
			for k in profile:
				var v := int(base[k])
				total += v
				check(v >= lo and v <= hi, "%s %s: %s=%d fora de [%d, %d]" % [tier, a.position, k, v, lo, hi])
				if v >= smin:
					specials += 1
			var n := profile.size()
			check_eq(total % n, 0, "%s: soma do perfil = mean × N" % tier)
			var mean := float(total) / float(n)
			mean_sum += mean
			check(mean >= float(t.mean[0]) and mean <= float(t.mean[1]),
				"%s: média do perfil %.2f fora de %s" % [tier, mean, str(t.mean)])
			check(specials >= int(t.specialties[0]),
				"%s %s: %d especialidades >= %d (mínimo %d) em %s" % [tier, a.position, specials, smin, int(t.specialties[0]), str(base)])
			var off_range: Array = off.gk_outfield_skills if gk else off.outfield_gk_skills
			for k in AthleteDna.BASE_ATTRIBUTE_IDS:
				if not profile.has(k):
					var v := int(base[k])
					check(v >= int(off_range[0]) and v <= int(off_range[1]), "%s %s: fora do perfil %s=%d" % [tier, a.position, k, v])
			check_eq(a.tier(), tier, "tier gravado no DNA")
			if tier == "deus":
				var top := 0
				for k in profile:
					if int(base[k]) >= 90:
						top += 1
				check(top >= 2, "deus: pelo menos 2 atributos >= 90 (%s)" % str(base))
		var avg := mean_sum / float(maxi(1, list.size()))
		check(avg > prev_avg, "%s: média (%.1f) acima do tier anterior (%.1f)" % [tier, avg, prev_avg])
		prev_avg = avg
	reg.dispose()


func test_perfis_de_goleiro_e_de_linha() -> void:
	var reg := Fixtures.registry_with([MID])
	var sums := {}
	for pos in ["GK", "DEF", "FWD"]:
		var res := _generate(reg, _world(), 555, 40, "ouro", {"positions": _repeat(pos, 40), "commit": false})
		var acc := {}
		for k in AthleteDna.BASE_ATTRIBUTE_IDS:
			acc[k] = 0
		for a in _athletes(res):
			check_eq(a.position, pos, "posição forçada respeitada")
			check_eq(a.dna.position, pos)
			for k in AthleteDna.BASE_ATTRIBUTE_IDS:
				acc[k] += int(a.dna.base_attributes[k])
		sums[pos] = acc
	var gk: Dictionary = sums.GK
	check(gk.reflexes > gk.finishing * 1.5 and gk.elasticity > gk.pace * 1.5, "goleiro: reflexo e elasticidade dominam")
	var fwd: Dictionary = sums.FWD
	check(fwd.finishing > fwd.tackling, "atacante finaliza mais do que desarma")
	check(fwd.reflexes * 3 < fwd.finishing, "atacante quase sem reflexo de goleiro")
	var df: Dictionary = sums.DEF
	check(df.tackling > df.finishing, "zagueiro desarma mais do que finaliza")
	reg.dispose()


func test_novo_tier_so_com_parametros() -> void:
	var lenda := {"label": "Lenda", "mean": [85, 88], "floor": 70, "cap": 99, "specialties": [3, 3], "specialty_min": 95}
	var reg := Fixtures.registry_with([MID], {MID: {"tiers": {"lenda": lenda}}})
	var res := _generate(reg, _world(), 9, 12, "lenda", {"commit": false, "positions": _repeat("MID", 12)})
	check(res.ok, "tier novo via ruleset: %s" % str(res.get("detail", "")))
	for a in _athletes(res):
		var top := 0
		for k in OUTFIELD_PROFILE:
			var v := int(a.dna.base_attributes[k])
			check(v >= 70 and v <= 99, "lenda: %s=%d em [70, 99]" % [k, v])
			if v >= 95:
				top += 1
		check(top >= 3, "lenda: 3 especialidades >= 95")
	var bad := _generate(reg, _world(), 9, 1, "platina")
	check_eq(bad.get("error"), "unknown_tier")
	reg.dispose()


# --- identidade e DNA --------------------------------------------------------------------------

func test_uuid_v4_dna_verificado_e_campos_do_atleta() -> void:
	var reg := Fixtures.registry_with([MID])
	var res := _generate(reg, _world(), 4242, 10, "prata")
	check(res.ok, str(res.get("detail", "")))
	var catalog := _json(REAL_CATALOG)
	for a in _athletes(res):
		check(AthleteDna.is_uuid_v4(a.id), "UUID v4: %s" % a.id)
		check_eq(a.id, AthleteDna.uuid_v4_from_seed(int(a.dna.seed)), "UUID = fluxo uuid da semente do atleta")
		check_eq(AthleteDna.verify(a.dna), [], "DNA íntegro")
		check_eq(a.dna.generator, "athlete_generator@1")
		check_eq(a.dna.catalog, catalog.version, "versão do catálogo gravada")
		check_eq(a.dna.initial_age, 17)
		check_eq(a.dna.origin, _origin(), "origin copiada")
		check_eq(a.name, a.dna.birth_name, "nome = nome de nascimento")
		check(a.name.contains(" "), "nome e sobrenome: %s" % a.name)
		check_eq(a.nationality, a.dna.nationality)
		check_eq(a.status, "active")
		check_eq(a.club_history, [], "nasce sem clube")
		check_eq(a.dna.face.keys().size(), AthleteDna.FACE_KEYS.size(), "receita com todas as chaves (sem paletas: catálogo sem cores)")
		for k in AthleteDna.FACE_KEYS:
			check(a.dna.face.has(k), "face.%s presente" % k)
	reg.dispose()


func test_posicoes_nacionalidades_e_nomes() -> void:
	var reg := Fixtures.registry_with([MID])
	var n := 300
	var res := _generate(reg, _world(), 31337, n, "bronze", {"unique": false, "commit": false})
	var pos_count := {}
	var nat_count := {}
	var names := _json(NAMES)
	var weights: Dictionary = reg.get_mechanic(MID).param("nationality_weights")
	for a in _athletes(res):
		pos_count[a.position] = int(pos_count.get(a.position, 0)) + 1
		nat_count[a.nationality] = int(nat_count.get(a.nationality, 0)) + 1
		check(weights.has(a.nationality), "nacionalidade dos pesos: %s" % a.nationality)
		var pool: Dictionary = names.get(a.nationality, {})
		var parts: PackedStringArray = a.name.split(" ", false, 1)
		check(parts.size() == 2 and pool.get("first", []).has(parts[0]), "primeiro nome do pool %s: %s" % [a.nationality, a.name])
		check(parts.size() == 2 and pool.get("last", []).has(parts[1]), "sobrenome do pool %s: %s" % [a.nationality, a.name])
	for p in AthleteDna.POSITIONS:
		check(int(pos_count.get(p, 0)) > 0, "posição %s aparece" % p)
	var gk_share := float(pos_count.get("GK", 0)) / float(n)
	check(gk_share > 0.04 and gk_share < 0.18, "goleiros ~10%% (%.2f)" % gk_share)
	var br_share := float(nat_count.get("BR", 0)) / float(n)
	check(br_share > 0.35 and br_share < 0.55, "Brasil ~45%% (%.2f)" % br_share)
	for nat in weights:
		check(names.has(nat), "names.json tem pool para %s" % nat)
		var pool: Dictionary = names.get(nat, {})
		check(pool.get("first", []).size() >= 20 and pool.get("last", []).size() >= 20, "pool %s com ~25 nomes" % nat)
	# Forçar a posição não muda nacionalidade, nome nem rosto.
	var free := _athletes(_generate(reg, _world(), 77, 8, "ouro", {"commit": false}))
	var forced := _athletes(_generate(reg, _world(), 77, 8, "ouro", {"commit": false, "positions": _repeat("GK", 8)}))
	for i in mini(free.size(), forced.size()):
		check_eq(forced[i].position, "GK")
		check_eq(forced[i].name, free[i].name, "nome independe da posição forçada")
		check_eq(forced[i].nationality, free[i].nationality, "nacionalidade independe da posição")
		check_eq(forced[i].dna.face, free[i].dna.face, "rosto independe da posição")
	reg.dispose()


# --- unicidade ---------------------------------------------------------------------------------

func test_colisao_com_registro_redesenha_rosto_e_atributos() -> void:
	var reg := Fixtures.registry_with([MID])
	var a0: Athlete = _athletes(_generate(reg, _world(), 777, 1, "prata", {"commit": false}))[0]
	var fh := str(a0.dna.face_hash)
	var ah := str(a0.dna.attributes_hash)

	var w := _world()
	w.ext[MID] = {"face_hashes": {fh: "outro"}, "attribute_hashes": {ah: "outro"}, "dna_hashes": {}}
	var res := _generate(reg, w, 777, 1, "prata")
	check(res.ok, str(res.get("detail", "")))
	var b0: Athlete = _athletes(res)[0]
	check(b0.dna.face_hash != fh, "rosto já registrado foi redesenhado")
	check(b0.dna.attributes_hash != ah, "atributos já registrados foram redesenhados")
	check_eq(b0.dna.seed, a0.dna.seed, "mesma semente")
	check_eq(b0.name, a0.name, "identidade não muda (fluxo próprio)")
	check_eq(b0.position, a0.position)
	check_eq(w.ext[MID].face_hashes.get(b0.dna.face_hash), b0.id, "novo rosto registrado")
	check_eq(w.ext[MID].face_hashes.get(fh), "outro", "registro anterior intacto")

	# Só o rosto registrado: os atributos continuam os mesmos (fluxos independentes).
	var w2 := _world()
	w2.ext[MID] = {"face_hashes": {fh: "outro"}}
	var c0: Athlete = _athletes(_generate(reg, w2, 777, 1, "prata"))[0]
	check(c0.dna.face_hash != fh, "rosto redesenhado")
	check_eq(c0.dna.base_attributes, a0.dna.base_attributes, "atributos iguais")
	reg.dispose()


func test_lote_de_30_unicos_com_catalogo_real() -> void:
	var reg := Fixtures.registry_with([MID])
	var w := _world()
	var res := _generate(reg, w, 2026, 30, "bronze")
	check(res.ok, str(res.get("detail", "")))
	var list := _athletes(res)
	check_eq(list.size(), 30)
	check_eq(_hash_set(list, "face_hash").size(), 30, "rostos únicos no lote")
	check_eq(_hash_set(list, "attributes_hash").size(), 30, "atributos únicos no lote")
	check_eq(_hash_set(list, "dna_hash").size(), 30, "DNAs únicos")
	check_eq(w.athletes.size(), 30, "commit grava no mundo")
	var data: Dictionary = w.ext.get(MID, {})
	for key in ["face_hashes", "attribute_hashes", "dna_hashes"]:
		check_eq(data.get(key, {}).size(), 30, "registro %s" % key)
	var catalog := _json(REAL_CATALOG)
	var rejected := {}
	for pair in catalog.validation.rejected:
		rejected["%s|%s" % [pair[0], pair[1]]] = true
	for a in list:
		check_eq(data.face_hashes.get(a.dna.face_hash), a.id, "registro aponta para o atleta")
		var face: Dictionary = a.dna.face
		for slot in AthleteDna.FACE_KEYS:
			var pid := str(face[slot])
			if pid == "":
				# Vazio só em slot opcional ou fora da receita (slot sem peça ativa, ex.: orelha).
				check(catalog.optional_slots.has(slot) or not catalog.face_slots.has(slot),
					"só slot opcional ou fora da receita fica vazio (%s)" % slot)
				continue
			check(catalog.parts[slot].has(pid), "%s existe no catálogo" % pid)
			check_eq(catalog.parts[slot].get(pid, {}).get("status"), "active", "só peças ativas")
			check(not rejected.has("%s|%s" % [face.head, pid]), "par rejeitado sorteado: %s × %s" % [face.head, pid])
		var v: Dictionary = reg.bus.decide(VALIDATE, {"world": w, "athlete": a})
		check(v.ok, "validate: %s" % str(v.errors))
	reg.dispose()


func test_esgotamento_falha_sem_gravar_nada() -> void:
	var reg := Fixtures.registry_with([MID], {MID: {"max_attempts": 5}})
	var cat := _fake_catalog()  # 1 peça por slot, opcionais sempre presentes: um único rosto possível
	var w := _world()
	var first := _generate(reg, w, 1, 1, "ouro", {"catalog": cat})
	check(first.ok, str(first.get("detail", "")))
	check_eq(w.athletes.size(), 1)
	var snapshot := w.to_dict()
	var again := _generate(reg, w, 2, 1, "ouro", {"catalog": cat})
	check_eq(again.get("ok"), false, "segundo rosto impossível")
	check_eq(again.get("error"), "uniqueness_exhausted")
	check(str(again.get("detail", "")).contains("5"), "respeita max_attempts: %s" % str(again.get("detail", "")))
	check_eq(w.to_dict(), snapshot, "nada gravado no mundo")

	# Dentro do lote: o segundo colide com o primeiro; o lote inteiro falha.
	var w2 := _world()
	var batch := _generate(reg, w2, 3, 2, "ouro", {"catalog": cat})
	check_eq(batch.get("error"), "uniqueness_exhausted", "colisão dentro do lote")
	check(w2.athletes.is_empty(), "nenhum atleta do lote gravado")
	check(not w2.ext.has(MID), "registro não criado")

	reg.dispose()

	# Dois rostos possíveis: um lote de 2 sai (redesenho), um de 3 não.
	reg = Fixtures.registry_with([MID])
	var two := _fake_catalog({"head": 2})
	var w3 := _world()
	var ok2 := _generate(reg, w3, 4, 2, "ouro", {"catalog": two})
	check(ok2.ok, "2 rostos para 2 atletas: %s" % str(ok2.get("detail", "")))
	check_eq(_hash_set(_athletes(ok2), "face_hash").size(), 2, "rostos distintos no lote")
	var w4 := _world()
	check_eq(_generate(reg, w4, 4, 3, "ouro", {"catalog": two}).get("error"), "uniqueness_exhausted")
	check(w4.athletes.is_empty())
	reg.dispose()


# --- rosto -------------------------------------------------------------------------------------

func test_pares_rejeitados_e_pecas_inativas_nunca_aparecem() -> void:
	var reg := Fixtures.registry_with([MID])
	var extra := {
		"ear": {
			"ear_004": {"file": "a.png", "status": "retired", "weight": 1},
			"ear_005": {"file": "b.png", "status": "missing", "weight": 1},
		},
		"eye": {"eye_009": {"file": "c.png", "status": "active", "weight": 0}},
	}
	var rejected := [["head_001", "ear_001"], ["head_001", "ear_002"], ["head_002", "ear_003"]]
	var cat := _fake_catalog({"head": 2, "ear": 3, "eye": 2}, {"hair": 0.5, "chin": 0.5, "skin_mark": 0.5}, rejected, extra)
	var res := _generate(reg, _world(), 99, 200, "bronze", {"catalog": cat, "unique": false, "commit": false})
	check(res.ok, str(res.get("detail", "")))
	var heads := {}
	var ears := {}
	for a in _athletes(res):
		var face: Dictionary = a.dna.face
		heads[face.head] = true
		ears[face.ear] = true
		if face.head == "head_001":
			check_eq(face.ear, "ear_003", "head_001 só aceita ear_003")
		else:
			check(face.ear != "ear_003", "head_002 rejeita ear_003")
		check(not ["ear_004", "ear_005"].has(face.ear), "retired/missing nunca sorteadas")
		check(face.eye != "eye_009", "peso 0 nunca sorteado")
		check_eq(a.dna.catalog, "teste-1")
	check_eq(heads.size(), 2, "as duas cabeças aparecem")
	check_eq(ears.size(), 3, "as três orelhas ativas aparecem")
	reg.dispose()


func test_trios_em_conflito_sao_evitados() -> void:
	var conflicts := [["head_001", "nose_001", "mouth_001"]]
	var cat := _fake_catalog({"mouth": 2}, {}, [], {}, conflicts)
	var reg := Fixtures.registry_with([MID])
	for a in _athletes(_generate(reg, _world(), 5, 40, "bronze", {"catalog": cat, "unique": false, "commit": false})):
		check_eq(a.dna.face.mouth, "mouth_002", "nose_001 encosta em mouth_001 nessa cabeça")
	reg.dispose()
	var off := Fixtures.registry_with([MID], {MID: {"avoid_conflicts": false}})
	var mouths := {}
	for a in _athletes(_generate(off, _world(), 5, 40, "bronze", {"catalog": cat, "unique": false, "commit": false})):
		mouths[a.dna.face.mouth] = true
	check(mouths.has("mouth_001"), "avoid_conflicts=false volta a sortear o trio")
	off.dispose()


func test_catalogo_esgotado_e_indisponivel() -> void:
	var reg := Fixtures.registry_with([MID])
	var cat := _fake_catalog({}, {}, [["head_001", "ear_001"]])
	var w := _world()
	var res := _generate(reg, w, 1, 1, "ouro", {"catalog": cat})
	check_eq(res.get("error"), "catalog_exhausted", "orelha obrigatória sem candidata")
	check(w.athletes.is_empty() and w.ext.is_empty(), "nada gravado")
	# Slot opcional sem candidata só fica vazio.
	var no_hair := _fake_catalog({"hair": 0})
	var ok := _generate(reg, _world(), 1, 1, "ouro", {"catalog": no_hair})
	check(ok.ok, str(ok.get("detail", "")))
	if ok.ok:
		check_eq(ok.athletes[0].dna.face.hair, "")
	reg.dispose()
	var missing := Fixtures.registry_with([MID], {MID: {"catalog_path": "res://data/portraits/nao_existe.json"}})
	check_eq(_generate(missing, _world(), 1, 1).get("error"), "catalog_unavailable")
	missing.dispose()


func test_pesos_que_estouram_32_bits_sao_recusados() -> void:
	# Regressão: SeededRng.int_between é de 32 bits. Com a soma dos pesos × 1000 acima de 2^31 - 1
	# o sorteio saía distorcido sem erro (40 de 40 atletas "AR", a primeira chave em ordem
	# alfabética, com BR tendo 87% do peso). Agora generate recusa antes de sortear.
	var big := Fixtures.registry_with([MID], {MID: {"nationality_weights": {"BR": 2000000, "AR": 300000}}})
	var w := _world()
	var res := _generate(big, w, 1, 1)
	check_eq(res.get("error"), "invalid_params", "nationality_weights grandes demais")
	check(str(res.get("detail", "")).contains("nationality_weights"), "detalhe cita a tabela: %s" % str(res.get("detail", "")))
	check(w.athletes.is_empty() and w.ext.is_empty(), "nada gravado")
	big.dispose()
	var pos := Fixtures.registry_with([MID], {MID: {"position_weights": {"GK": 3000000}}})
	check_eq(_generate(pos, _world(), 1, 1).get("error"), "invalid_params", "position_weights grandes demais")
	pos.dispose()
	var reg := Fixtures.registry_with([MID])
	var heavy := _fake_catalog({"hair": 2})
	heavy.parts.hair.hair_001.weight = 2200000
	var hres := _generate(reg, _world(), 1, 1, "ouro", {"catalog": heavy})
	check_eq(hres.get("error"), "catalog_unavailable", "pesos do catálogo grandes demais")
	check(str(hres.get("detail", "")).contains("hair"), "detalhe cita o slot: %s" % str(hres.get("detail", "")))
	reg.dispose()
	# Abaixo do limite, pesos grandes seguem as proporções (não grudam na primeira chave).
	var near := Fixtures.registry_with([MID], {MID: {"nationality_weights": {"BR": 1500000, "AR": 500000}}})
	var many := _generate(near, _world(), 7, 120, "ouro", {"unique": false})
	check(bool(many.get("ok", false)), str(many.get("detail", "")))
	var counts := {}
	for a in _athletes(many):
		counts[a.nationality] = int(counts.get(a.nationality, 0)) + 1
	check(int(counts.get("BR", 0)) >= 70 and int(counts.get("AR", 0)) >= 15, "proporções ~75/25: %s" % str(counts))
	near.dispose()


func test_frequencia_dos_slots_opcionais() -> void:
	var reg := Fixtures.registry_with([MID])
	var res := _generate(reg, _world(), 8080, FREQ_SAMPLE, "bronze", {"unique": false, "commit": false})
	check(res.ok, str(res.get("detail", "")))
	var counts := {"hair": 0, "chin": 0, "skin_mark": 0}
	# Na mesma amostra (catálogo real): nenhum par rejeitado nem trio em conflito.
	var catalog := _json(REAL_CATALOG)
	var rejected := {}
	for pair in catalog.validation.rejected:
		rejected["%s|%s" % [pair[0], pair[1]]] = true
	var trios: Array = catalog.validation.get("conflicts", [])
	var heads := {}
	for a in _athletes(res):
		var face: Dictionary = a.dna.face
		heads[face.head] = true
		for slot in counts:
			if str(face[slot]) != "":
				counts[slot] += 1
		for slot in AthleteDna.FACE_KEYS:
			check(not rejected.has("%s|%s" % [face.head, face[slot]]), "par rejeitado: %s × %s" % [face.head, face[slot]])
		var used := face.values()
		for trio in trios:
			check(not (face.head == trio[0] and used.has(trio[1]) and used.has(trio[2])), "trio em conflito: %s" % str(trio))
	var active := func(slot: String) -> int:
		return catalog.parts[slot].values().filter(func(p): return p.status == "active").size()
	check_eq(heads.size(), active.call("head"), "todas as cabeças ativas aparecem")
	var n := float(FREQ_SAMPLE)
	# Slot opcional sem peça ativa (ex.: queixo, hoje) nunca aparece.
	for row in [["hair", 0.95, 0.04], ["chin", 0.50, 0.07], ["skin_mark", 0.35, 0.07]]:
		var want: float = row[1] if active.call(row[0]) > 0 else 0.0
		check_near(counts[row[0]] / n, want, row[2], "%s ~%d%%" % [row[0], roundi(want * 100.0)])
	reg.dispose()
	# draw_rules do ruleset sobrepõem as do catálogo.
	var bald := Fixtures.registry_with([MID], {MID: {"draw_rules": {"chance_hair": 0.0}}})
	for a in _athletes(_generate(bald, _world(), 1, 30, "bronze", {"unique": false, "commit": false})):
		check_eq(a.dna.face.hair, "", "chance_hair 0 pelo ruleset")
	bald.dispose()


# --- commit, register, validate, unique=false ----------------------------------------------------

func test_commit_false_nao_grava() -> void:
	var reg := Fixtures.registry_with([MID])
	var w := _world()
	var res := _generate(reg, w, 321, 5, "ouro", {"commit": false})
	check(res.ok)
	check_eq(_athletes(res).size(), 5)
	check(w.athletes.is_empty(), "commit=false não grava atletas")
	check(w.ext.is_empty(), "commit=false não grava registro")
	var committed := _athletes(_generate(reg, w, 321, 5, "ouro"))
	for i in mini(committed.size(), 5):
		check_eq(committed[i].to_dict(), _athletes(res)[i].to_dict(), "commit não muda o conteúdo")
	check_eq(w.athletes.size(), 5)
	reg.dispose()


func test_register_grava_hashes_e_recusa_colisao_atomicamente() -> void:
	var reg := Fixtures.registry_with([MID])
	var w := _world()
	var list := _athletes(_generate(reg, w, 600, 3, "prata", {"commit": false}))
	var r: Dictionary = reg.bus.decide(REGISTER, {"world": w, "athletes": list})
	check(r.ok, "register: %s" % str(r))
	check_eq(w.ext[MID].face_hashes.size(), 3)
	check_eq(w.ext[MID].dna_hashes.get(list[0].dna_hash()), list[0].id)
	check(w.athletes.is_empty(), "register só grava hashes")
	check(reg.bus.decide(REGISTER, {"world": w, "athletes": list}).ok, "registrar de novo o mesmo atleta é idempotente")

	# Os hashes registrados passam a valer para o gerador: mesma semente, rostos novos.
	var again := _athletes(_generate(reg, w, 600, 3, "prata", {"commit": false}))
	for i in mini(again.size(), 3):
		check(again[i].dna.face_hash != list[i].dna.face_hash, "gerador respeita hashes registrados")

	# Colisão: um atleta novo + a cópia de um registrado com outro id -> recusa tudo.
	var fresh: Athlete = _athletes(_generate(reg, _world(), 601, 1, "prata", {"commit": false}))[0]
	var clone := Athlete.from_dict(list[0].to_dict())
	clone.id = AthleteDna.uuid_v4_from_seed(1)
	var before: Dictionary = w.ext[MID].duplicate(true)
	var bad: Dictionary = reg.bus.decide(REGISTER, {"world": w, "athletes": [fresh, clone]})
	check_eq(bad.ok, false)
	check_eq(bad.error, "collision")
	check_eq(w.ext[MID], before, "nada registrado quando há colisão")

	# Hash adulterado.
	var tampered := Athlete.from_dict(fresh.to_dict())
	tampered.dna.base_attributes.pace = int(tampered.dna.base_attributes.pace) % 99 + 1
	check_eq(reg.bus.decide(REGISTER, {"world": w, "athletes": [tampered]}).error, "invalid_athlete")
	check(reg.bus.decide(REGISTER, {"world": w, "athletes": [fresh]}).ok, "atleta íntegro registra")
	reg.dispose()


func test_validate_confere_hashes_catalogo_e_registro() -> void:
	var reg := Fixtures.registry_with([MID])
	var w := _world()
	var a: Athlete = _athletes(_generate(reg, w, 9000, 1, "diamante"))[0]
	var ok: Dictionary = reg.bus.decide(VALIDATE, {"world": w, "athlete": a})
	check(ok.ok, "atleta recém-gerado é válido: %s" % str(ok.errors))

	# Ida e volta pelo save (JSON devolve floats): continua válido.
	var loaded := World.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	var la: Athlete = loaded.athletes[a.id]
	var after_load: Dictionary = reg.bus.decide(VALIDATE, {"world": loaded, "athlete": la})
	check(after_load.ok, "válido depois de salvar/carregar: %s" % str(after_load.errors))

	var tampered := Athlete.from_dict(a.to_dict())
	tampered.dna.base_attributes.pace = int(tampered.dna.base_attributes.pace) % 99 + 1
	var t: Dictionary = reg.bus.decide(VALIDATE, {"world": w, "athlete": tampered})
	check(not t.ok and str(t.errors).contains("attributes_hash divergente"), "adulteração: %s" % str(t.errors))

	var unknown := Athlete.from_dict(a.to_dict())
	unknown.dna.face.ear = "ear_999"
	unknown.dna = AthleteDna.seal(unknown.dna)
	var u: Dictionary = reg.bus.decide(VALIDATE, {"athlete": unknown})
	check(not u.ok and str(u.errors).contains("ear_999"), "peça fora do catálogo: %s" % str(u.errors))

	# Primeiro par rejeitado do catálogo real: [cabeça, peça]; o slot é o prefixo do ID.
	var rejected_pair: Array = _json(REAL_CATALOG).validation.rejected[0]
	var pair_id := str(rejected_pair[1])
	var pair := Athlete.from_dict(a.to_dict())
	pair.dna.face.head = str(rejected_pair[0])
	pair.dna.face[pair_id.substr(0, pair_id.rfind("_"))] = pair_id
	pair.dna = AthleteDna.seal(pair.dna)
	var p: Dictionary = reg.bus.decide(VALIDATE, {"athlete": pair})
	check(not p.ok and str(p.errors).contains("par rejeitado"), "par rejeitado: %s" % str(p.errors))

	var other := Athlete.from_dict(a.to_dict())
	other.id = AthleteDna.uuid_v4_from_seed(123)
	var o: Dictionary = reg.bus.decide(VALIDATE, {"world": w, "athlete": other})
	check(not o.ok and str(o.errors).contains("outro atleta"), "hash de outro atleta: %s" % str(o.errors))

	var bad_id := Athlete.from_dict(a.to_dict())
	bad_id.id = "x1"
	var b: Dictionary = reg.bus.decide(VALIDATE, {"athlete": bad_id})
	check(not b.ok and str(b.errors).contains("UUID"), "id inválido: %s" % str(b.errors))
	reg.dispose()


func test_unique_false_nao_consulta_nem_grava_registro() -> void:
	var reg := Fixtures.registry_with([MID])
	var a0: Athlete = _athletes(_generate(reg, _world(), 4321, 1, "ouro", {"commit": false}))[0]
	var w := _world()
	w.ext[MID] = {"face_hashes": {a0.dna.face_hash: "outro"}, "attribute_hashes": {a0.dna.attributes_hash: "outro"}, "dna_hashes": {}}
	var before: Dictionary = w.ext.duplicate(true)
	var res := _generate(reg, w, 4321, 4, "ouro", {"unique": false})
	check(res.ok, str(res.get("detail", "")))
	var list := _athletes(res)
	check_eq(w.athletes.size(), 4, "atletas de IA entram no mundo")
	check_eq(w.ext, before, "registro intocado")
	if not list.is_empty():
		check_eq(list[0].dna.face_hash, a0.dna.face_hash, "não consultou o registro (mesmo rosto)")
		check_eq(list[0].to_dict(), a0.to_dict(), "mesmo atleta da semente")
	reg.dispose()


func test_erros_de_payload() -> void:
	var reg := Fixtures.registry_with([MID])
	var w := _world()
	check_eq(reg.bus.decide(GENERATE, {"count": 1, "seed": 1, "tiers": ["ouro"], "origin": _origin()}).error, "invalid_payload", "sem world")
	check_eq(reg.bus.decide(GENERATE, {"world": w, "count": 1, "tiers": ["ouro"], "origin": _origin()}).error, "invalid_payload", "sem seed")
	check_eq(reg.bus.decide(GENERATE, {"world": w, "count": 2, "seed": 1, "tiers": ["ouro"], "origin": _origin()}).error, "invalid_payload", "tiers curto")
	check_eq(reg.bus.decide(GENERATE, {"world": w, "count": 1, "seed": 1, "tiers": ["ouro"], "origin": {}}).error, "invalid_payload", "sem origin.source")
	check_eq(_generate(reg, w, 1, 1, "ouro", {"positions": ["ZAG"]}).get("error"), "invalid_payload", "posição inválida")
	check_eq(_generate(reg, w, 1, 1, "lata").get("error"), "unknown_tier")
	var bad_origin := _generate(reg, w, 1, 1, "ouro", {"origin": {"source": "test", "date": null}})
	check_eq(bad_origin.get("error"), "invalid_dna", "DNA que o núcleo recusaria não sai do gerador")
	var lower := Fixtures.registry_with([MID], {MID: {"nationality_weights": {"BR": 0, "AR": 0, "PT": 0, "ES": 0,
		"FR": 0, "UY": 0, "CO": 0, "IT": 0, "DE": 0, "CL": 0, "PY": 0, "MX": 0, "NG": 0, "NL": 0, "EC": 0, "JP": 0, "br": 1}}})
	check_eq(_generate(lower, w, 1, 1).get("error"), "invalid_dna", "nacionalidade fora do ISO alfa-2")
	lower.dispose()
	var empty := _generate(reg, w, 1, 0)
	check(empty.ok and empty.athletes.is_empty(), "count 0 devolve lote vazio")
	check(w.athletes.is_empty() and w.ext.is_empty(), "erros não gravam nada")
	reg.dispose()
