extends TestCase
## DNA digital (AthleteDna) e extensões do Athlete: hashes canônicos, UUID v4, sementes,
## verificação de integridade, club_history e rename.

const SEED := 140737488355327  # 2^47 - 1: exercita inteiros grandes no JSON
## Referências calculadas fora do Godot (Python: json.dumps(sort_keys=True,
## separators=(",", ":"), ensure_ascii=False) + hashlib.sha256). Garantem que o JSON canônico
## é JSON padrão e que um servidor em outra linguagem reproduz os mesmos hashes.
const REF_FACE_HASH := "dce0b297cc8f26a08ee3d15a562f791dba6edf27b5d8d06f8d561c1d1f5cbb3f"
const REF_ATTRIBUTES_HASH := "c85d72ce770b98910dc88c5cba9b6843e4a911b9fc4430927202b54ee85156cd"
const REF_DNA_HASH := "21b1f80de6dc8df618defe4987759862c0eaddb3a21df752e367fc03edfd8eed"
const TWO_POW_48 := 281474976710656


func _face() -> Dictionary:
	return {
		"head": "head_007", "ear": "ear_003", "eye": "eye_012", "eyebrow": "eyebrow_002",
		"nose": "nose_009", "mouth": "mouth_002", "hair": "hair_015", "chin": "",
		"skin_mark": "skin_mark_001", "body": "body_002", "arm": "arm_001",
	}


func _attrs() -> Dictionary:
	return {
		"pace": 71, "physical": 55, "passing": 60, "finishing": 78, "tackling": 30,
		"positioning": 64, "reflexes": 9, "elasticity": 12, "stamina": 66,
	}


func _raw_dna() -> Dictionary:
	return {
		"generator": "athlete_generator@1", "seed": SEED, "catalog": "retratos-2026.09",
		"face": _face(), "nationality": "BR", "position": "FWD", "tier": "ouro", "initial_age": 17,
		"base_attributes": _attrs(), "birth_name": "Tião Moreira",
		"origin": {"source": "test", "pack_type": "", "pack_id": "", "club_id": "", "date": "2026-09-27"},
	}


func _sealed() -> Dictionary:
	return AthleteDna.seal(_raw_dna())


func _json_round_trip(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v))


# --- forma canônica ------------------------------------------------------------------------

func test_json_canonico_ordena_chaves_sem_espacos_e_normaliza_floats() -> void:
	var v := {"é": "ção", "b": 1.0, "a": [2.0, "x"]}
	check_eq(AthleteDna.canonical_json(v), "{\"a\":[2,\"x\"],\"b\":1,\"é\":\"ção\"}", "JSON canônico")
	check_eq(AthleteDna.sha256(v), "77813307881a4aace478e4369c5dcd62ca63d28855184daf7657fb472b717bed",
		"sha256 igual ao de referência (UTF-8)")
	var c: Dictionary = AthleteDna.canonical({"n": 3.0, "f": 0.5, "l": [1.0, {"x": 2.0}]})
	check_eq(typeof(c.n), TYPE_INT, "float integral vira int")
	check_eq(typeof(c.f), TYPE_FLOAT, "float não integral continua float")
	check_eq(typeof(c.l[0]), TYPE_INT, "normalização recursiva em arrays")
	check_eq(typeof(c.l[1].x), TYPE_INT, "normalização recursiva em dicionários")


func test_canonical_copia_sem_alterar_original() -> void:
	var original := {"a": {"b": [1.0]}}
	var c: Dictionary = AthleteDna.canonical(original)
	c.a.b.append(2)
	check_eq(original.a.b.size(), 1, "canonical devolve cópia profunda")
	check_eq(typeof(original.a.b[0]), TYPE_FLOAT, "original intacto")


func test_hashes_batem_com_referencia_externa() -> void:
	var dna := _sealed()
	check_eq(dna.face_hash, REF_FACE_HASH, "face_hash")
	check_eq(dna.attributes_hash, REF_ATTRIBUTES_HASH, "attributes_hash")
	check_eq(dna.dna_hash, REF_DNA_HASH, "dna_hash")
	# fórmula do contrato, sem atalhos
	check_eq(AthleteDna.face_hash(_face()), JSON.stringify(_face(), "", true).sha256_text(), "face_hash = sha256(json(face))")
	check_eq(AthleteDna.HASHED_FIELDS, ["generator", "seed", "face", "nationality", "base_attributes"])


func test_hash_estavel_apos_ida_e_volta_por_json() -> void:
	var dna := _sealed()
	var back: Dictionary = _json_round_trip(dna)
	check_eq(typeof(back.seed), TYPE_FLOAT, "JSON devolve números como float (pré-condição do teste)")
	check_eq(AthleteDna.compute_hashes(back), AthleteDna.compute_hashes(dna), "hashes iguais após JSON")
	check_eq(AthleteDna.verify(back), [], "DNA carregado do JSON continua íntegro")
	check_eq(int(back.seed), SEED, "semente de 47 bits sobrevive ao JSON")
	# duas idas e voltas e selar de novo não muda nada
	var twice: Dictionary = _json_round_trip(_json_round_trip(dna))
	check_eq(AthleteDna.seal(twice).dna_hash, dna.dna_hash, "reselar após JSON dá o mesmo hash")
	check_eq(typeof(AthleteDna.seal(back).seed), TYPE_INT, "seal devolve forma canônica (seed int)")


func test_hash_independe_da_ordem_das_chaves() -> void:
	var a := _raw_dna()
	var b := {}
	var keys: Array = a.keys()
	keys.reverse()
	for k in keys:
		b[k] = a[k]
	var face_rev := {}
	var fk: Array = _face().keys()
	fk.reverse()
	for k in fk:
		face_rev[k] = _face()[k]
	b["face"] = face_rev
	var attrs_rev := {}
	var ak: Array = _attrs().keys()
	ak.reverse()
	for k in ak:
		attrs_rev[k] = _attrs()[k]
	b["base_attributes"] = attrs_rev
	check_eq(AthleteDna.canonical_json(a), AthleteDna.canonical_json(b), "JSON canônico igual")
	check_eq(AthleteDna.compute_hashes(a), AthleteDna.compute_hashes(b), "hashes iguais")


func test_dna_hash_ignora_estado_e_metadados() -> void:
	var base := _sealed()
	var h: String = base.dna_hash
	var variants := {
		"birth_name": "Outro Nome", "catalog": "retratos-2099.01", "tier": "deus",
		"initial_age": 30, "position": "GK",
		"origin": {"source": "pack", "pack_type": "gol", "pack_id": "x", "club_id": "c", "date": "2030-01-01"},
	}
	for k in variants:
		var d := base.duplicate(true)
		d[k] = variants[k]
		check_eq(AthleteDna.dna_hash(d), h, "dna_hash não depende de %s" % k)
	var with_catalog := base.duplicate(true)
	with_catalog.face["catalog"] = "retratos-2099.01"
	check_eq(AthleteDna.dna_hash(with_catalog), h, "face.catalog fora do dna_hash")
	check_eq(AthleteDna.face_hash(with_catalog.face), base.face_hash, "face.catalog fora do face_hash")
	# estado do atleta (atributos atuais, histórico, nome) não toca o DNA
	var a := Athlete.new()
	a.id = AthleteDna.uuid_v4_from_seed(SEED)
	a.name = "Tião Moreira"
	a.dna = base.duplicate(true)
	for k in AthleteDna.BASE_ATTRIBUTE_IDS:
		a.attributes[k] = float(base.base_attributes[k])
	a.attributes["pace"] = 99.0
	a.club_history.append({"club_id": "rubro", "from": "2026-09-27", "to": "", "via": "pack"})
	a.rename("Tiãozinho")
	check_eq(a.dna_hash(), h, "Athlete.dna_hash() lê o DNA")
	check_eq(AthleteDna.dna_hash(a.dna), h, "atributos atuais, club_history e nome não entram")
	check_eq(AthleteDna.verify(a.dna), [], "DNA intacto após mudar o estado")
	check_eq(a.tier(), "ouro", "Athlete.tier() lê o DNA")


func test_dna_hash_muda_com_a_identidade() -> void:
	var base := _sealed()
	var h: String = base.dna_hash
	var d := base.duplicate(true)
	d["seed"] = SEED - 1
	check(AthleteDna.dna_hash(d) != h, "seed muda o hash")
	d = base.duplicate(true)
	d["generator"] = "athlete_generator@2"
	check(AthleteDna.dna_hash(d) != h, "generator muda o hash")
	d = base.duplicate(true)
	d["nationality"] = "AR"
	check(AthleteDna.dna_hash(d) != h, "nacionalidade muda o hash")
	d = base.duplicate(true)
	d["face"]["hair"] = ""
	check(AthleteDna.dna_hash(d) != h, "rosto muda o hash")
	check(AthleteDna.face_hash(d.face) != base.face_hash, "rosto muda o face_hash")
	check_eq(AthleteDna.attributes_hash(d.base_attributes), base.attributes_hash, "rosto não muda attributes_hash")
	d = base.duplicate(true)
	d["base_attributes"]["stamina"] = 67
	check(AthleteDna.dna_hash(d) != h, "atributo base muda o hash")
	check(AthleteDna.attributes_hash(d.base_attributes) != base.attributes_hash, "atributo base muda attributes_hash")
	check_eq(AthleteDna.face_hash(d.face), base.face_hash, "atributo não muda face_hash")
	# mesma semente como float (JSON) ou int: mesmo hash
	d = base.duplicate(true)
	d["seed"] = float(SEED)
	check_eq(AthleteDna.dna_hash(d), h, "seed float integral = seed int")


# --- sementes e UUID -----------------------------------------------------------------------

func test_derive_seed_deterministico_e_48_bits() -> void:
	check_eq(AthleteDna.derive_seed(SEED, "athletes"), 17001350526201, "valor de referência (sha256 em Python)")
	check_eq(AthleteDna.derive_seed(SEED, "athletes"), AthleteDna.derive_seed(SEED, "athletes"), "determinístico")
	check(AthleteDna.derive_seed(SEED, "athletes") != AthleteDna.derive_seed(SEED, "tiers"), "sal muda a semente")
	check(AthleteDna.derive_seed(1, "x") != AthleteDna.derive_seed(2, "x"), "pai muda a semente")
	var seen := {}
	for i in 500:
		var s := AthleteDna.derive_seed(i, "athlete:%d" % i)
		check(s >= 0 and s < TWO_POW_48, "semente fora de [0, 2^48): %d" % s)
		seen[s] = true
	check_eq(seen.size(), 500, "sementes derivadas distintas")
	# encadeável: a semente derivada é uma semente válida de DNA e de novo derivável
	var child := AthleteDna.derive_seed(AthleteDna.derive_seed(SEED, "athletes"), "athlete:0")
	check(child >= 0 and child < TWO_POW_48, "derivação encadeada em 48 bits")


func test_uuid_v4_formato_versao_variante_e_determinismo() -> void:
	var u := AthleteDna.uuid_v4_from_seed(SEED)
	check(AthleteDna.is_uuid_v4(u), "formato UUID v4: %s" % u)
	check_eq(len(u), 36, "36 caracteres")
	check_eq(u.substr(14, 1), "4", "versão 4")
	check("89ab".contains(u.substr(19, 1)), "variante RFC 4122: %s" % u)
	check_eq(u, u.to_lower(), "hex minúsculo")
	check_eq(AthleteDna.uuid_v4_from_seed(SEED), u, "determinístico")
	# mesmo fluxo da especificação: SeededRng(seed).fork("uuid"), 16 bytes
	check_eq(AthleteDna.uuid_v4_from_rng(SeededRng.new(SEED).fork("uuid")), u, "fluxo fork(\"uuid\")")
	check(not AthleteDna.is_uuid_v4("00000000-0000-1000-8000-000000000000"), "rejeita versão 1")
	check(not AthleteDna.is_uuid_v4("00000000-0000-4000-c000-000000000000"), "rejeita variante errada")
	check(not AthleteDna.is_uuid_v4("00000000-0000-4000-8000-00000000000G"), "rejeita não hex")
	check(not AthleteDna.is_uuid_v4("00000000-0000-4000-8000-00000000000A"), "rejeita maiúsculas")
	check(not AthleteDna.is_uuid_v4(""), "rejeita vazio")


func test_uuid_unico_em_2000_sementes() -> void:
	var seen := {}
	for i in 2000:
		var u := AthleteDna.uuid_v4_from_seed(AthleteDna.derive_seed(SEED, "athlete:%d" % i))
		if not AthleteDna.is_uuid_v4(u):
			failures.append("UUID inválido: %s" % u)
		seen[u] = true
	check_eq(seen.size(), 2000, "2000 sementes, 2000 UUIDs distintos")
	var small := {}
	for i in 2000:
		small[AthleteDna.uuid_v4_from_seed(i)] = true
	check_eq(small.size(), 2000, "sementes pequenas e consecutivas também não colidem")


func test_uuid_colisao_continua_o_mesmo_fluxo() -> void:
	var rng := SeededRng.new(SEED).fork("uuid")
	var first := AthleteDna.uuid_v4_from_rng(rng)
	var second := AthleteDna.uuid_v4_from_rng(rng)
	check(first != second, "fluxo avança")
	check_eq(AthleteDna.uuid_v4_from_seed(SEED, {first: true}), second, "colisão pega o próximo do mesmo fluxo")
	check(AthleteDna.is_uuid_v4(second), "o próximo também é UUID v4")


# --- verificação ---------------------------------------------------------------------------

func test_verify_aceita_dna_selado() -> void:
	check_eq(AthleteDna.verify(_sealed()), [], "DNA recém-selado")
	var no_hair := _raw_dna()
	no_hair["face"]["hair"] = ""
	no_hair["face"]["skin_mark"] = ""
	check_eq(AthleteDna.verify(AthleteDna.seal(no_hair)), [], "peças opcionais vazias são válidas")
	var palette := _raw_dna()
	palette.face["skin"] = 3
	palette.face["hair_color"] = 1
	check_eq(AthleteDna.verify(AthleteDna.seal(palette)), [], "índices de paleta aceitos quando presentes")
	check_eq(AthleteDna.BASE_ATTRIBUTE_IDS, Array(AttributeCatalog.ids()), "atributos base = data/attributes.json")


func test_verify_detecta_adulteracao() -> void:
	var d := _sealed()
	d["base_attributes"]["finishing"] = 99
	var errs := AthleteDna.verify(d)
	check(_has_error(errs, "attributes_hash divergente"), "atributo adulterado: %s" % str(errs))
	check(_has_error(errs, "dna_hash divergente"), "identidade adulterada: %s" % str(errs))
	check(not _has_error(errs, "face_hash divergente"), "rosto intacto não acusa")
	d = _sealed()
	d["face"]["nose"] = "nose_001"
	errs = AthleteDna.verify(d)
	check(_has_error(errs, "face_hash divergente"), "rosto adulterado: %s" % str(errs))
	d = _sealed()
	d["dna_hash"] = "0".repeat(64)
	check(_has_error(AthleteDna.verify(d), "dna_hash divergente"), "hash gravado adulterado")
	d = _sealed()
	d["seed"] = SEED + 1
	check(_has_error(AthleteDna.verify(d), "dna_hash divergente"), "semente adulterada")
	# metadados fora do hash podem mudar sem acusar divergência
	d = _sealed()
	d["birth_name"] = "Nome Novo"
	check_eq(AthleteDna.verify(d), [], "birth_name não é identidade")


func test_verify_detecta_campos_ausentes_e_valores_invalidos() -> void:
	for k in AthleteDna.REQUIRED_FIELDS:
		var d := _sealed()
		d.erase(k)
		check(_has_error(AthleteDna.verify(d), "campo obrigatório ausente: %s" % k), "sem %s" % k)
	var cases := {
		"pace": 0, "physical": 100, "passing": 55.5, "finishing": "80",
	}
	for k in cases:
		var d := _raw_dna()
		d.base_attributes[k] = cases[k]
		check(not AthleteDna.verify(AthleteDna.seal(d)).is_empty(), "atributo inválido %s=%s aceito" % [k, str(cases[k])])
	var missing_attr := _raw_dna()
	missing_attr.base_attributes.erase("stamina")
	check(_has_error(AthleteDna.verify(AthleteDna.seal(missing_attr)), "base_attributes sem stamina"), "atributo faltando")
	var extra_attr := _raw_dna()
	extra_attr.base_attributes["charisma"] = 50
	check(_has_error(AthleteDna.verify(AthleteDna.seal(extra_attr)), "atributo desconhecido"), "atributo novo recusado")
	var missing_face := _raw_dna()
	missing_face.face.erase("chin")
	check(_has_error(AthleteDna.verify(AthleteDna.seal(missing_face)), "face sem a chave chin"), "face sem chave")
	var no_head := _raw_dna()
	no_head["face"]["head"] = ""
	check(_has_error(AthleteDna.verify(AthleteDna.seal(no_head)), "face.head vazio"), "rosto sem cabeça")
	var float_seed := _raw_dna()
	float_seed["seed"] = 12.5
	check(_has_error(AthleteDna.verify(AthleteDna.seal(float_seed)), "seed deve ser inteiro"), "semente fracionária")
	var neg_seed := _raw_dna()
	neg_seed["seed"] = -1
	check(_has_error(AthleteDna.verify(AthleteDna.seal(neg_seed)), "seed fora"), "semente negativa")
	var big_seed := _raw_dna()
	big_seed["seed"] = TWO_POW_48
	check(_has_error(AthleteDna.verify(AthleteDna.seal(big_seed)), "seed fora"), "semente >= 2^48")
	var bad_nat := _raw_dna()
	bad_nat["nationality"] = "bra"
	check(_has_error(AthleteDna.verify(AthleteDna.seal(bad_nat)), "nationality"), "nacionalidade fora do ISO alfa-2")
	var bad_pos := _raw_dna()
	bad_pos["position"] = "ST"
	check(_has_error(AthleteDna.verify(AthleteDna.seal(bad_pos)), "position"), "posição inválida")
	var bad_type := _raw_dna()
	bad_type.origin["flag"] = true
	check(_has_error(AthleteDna.verify(AthleteDna.seal(bad_type)), "não canônico"), "bool não é canônico")


func _has_error(errors: Array, fragment: String) -> bool:
	for e in errors:
		if str(e).contains(fragment):
			return true
	return false


# --- Athlete: club_history e rename --------------------------------------------------------

func test_club_history_e_rename_ida_e_volta() -> void:
	var a := Athlete.new()
	a.id = AthleteDna.uuid_v4_from_seed(SEED)
	a.name = "Tião Moreira"
	a.dna = _sealed()
	a.attributes = {"pace": 71.0}
	a.club_history = [
		{"club_id": "anil", "from": "2026-09-01", "to": "2026-09-20", "via": "pack"},
		{"club_id": "rubro", "from": "2026-09-20", "to": "", "via": "market"},
	]
	var dna_before: Dictionary = a.dna.duplicate(true)
	a.rename("Moreirinha")
	check_eq(a.name, "Moreirinha", "rename troca o nome")
	check_eq(a.dna, dna_before, "rename não toca o DNA")
	check_eq(a.dna.birth_name, "Tião Moreira", "nome de nascimento preservado")
	var b := Athlete.from_dict(_json_round_trip(a.to_dict()))
	check_eq(b.name, "Moreirinha", "nome novo salvo")
	check_eq(b.club_history.size(), 2, "histórico salvo")
	check_eq(b.club_history, a.club_history, "histórico idêntico após JSON")
	check_eq(b.dna_hash(), a.dna_hash(), "dna_hash após JSON")
	check_eq(b.tier(), "ouro")
	check_eq(AthleteDna.verify(b.dna), [], "DNA íntegro após salvar/carregar")
	# cópia independente
	b.club_history[0]["to"] = "mudou"
	check_eq(a.club_history[0]["to"], "2026-09-20", "from_dict/to_dict copiam o histórico")


func test_save_antigo_sem_club_history() -> void:
	var old := {"id": "rub_01", "name": "Velho", "nationality": "BR", "position": "GK",
		"attributes": {"pace": 50}, "dna": {"generator": "demo", "initial_age": 17}}
	var a := Athlete.from_dict(old)
	check_eq(a.club_history, [], "ausente = []")
	check_eq(a.dna_hash(), "", "sem DNA selado = hash vazio")
	check_eq(a.tier(), "", "sem tier")
	check(a.to_dict().has("club_history"), "to_dict passa a gravar club_history")
