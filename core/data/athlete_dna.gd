class_name AthleteDna
extends RefCounted
## DNA digital do atleta (GDD 5.4, RETRATOS.md 4.3): forma canônica, hashes SHA-256 e UUID v4
## determinístico. Só funções estáticas: quem gera é a mecânica athlete_generator (servidor);
## o núcleo apenas sabe canonizar, selar e conferir um DNA.
##
## Identidade canônica (dna_hash) = generator + seed + face (sem "catalog") + nationality +
## base_attributes. Nome, catálogo, idade, atributos atuais, tier, origem e histórico de clubes
## são estado ou metadado e NÃO mudam o hash.
##
## O DNA canônico só tem inteiros e strings. JSON.parse devolve todo número como float, por isso
## canonical() transforma floats integrais em int antes de serializar: o hash é o mesmo antes e
## depois de salvar/carregar.

## Campos que todo DNA selado precisa ter.
const REQUIRED_FIELDS := [
	"generator", "seed", "catalog", "face", "nationality", "position", "tier", "initial_age",
	"base_attributes", "birth_name", "origin", "face_hash", "attributes_hash", "dna_hash",
]
## Campos que entram no dna_hash (identidade canônica).
const HASHED_FIELDS := ["generator", "seed", "face", "nationality", "base_attributes"]
## Chaves da receita visual, na ordem do contrato. Peça ausente = "".
const FACE_KEYS := ["head", "ear", "eye", "eyebrow", "nose", "mouth", "hair", "chin", "skin_mark", "body", "arm"]
## Chaves opcionais de paleta na receita (só existem quando o catálogo tem paletas).
const FACE_PALETTE_KEYS := ["skin", "hair_color"]
## Campo da receita que é versão do catálogo, não aparência: fora dos hashes.
const FACE_IGNORED_KEYS := ["catalog"]
## Os três hashes gravados por seal().
const HASH_KEYS := ["face_hash", "attributes_hash", "dna_hash"]
## Atributos base com que todo atleta nasce (ids de data/attributes.json).
const BASE_ATTRIBUTE_IDS := [
	"pace", "physical", "passing", "finishing", "tackling", "positioning", "reflexes", "elasticity", "stamina",
]
const ATTRIBUTE_MIN := 1
const ATTRIBUTE_MAX := 99
const POSITIONS := ["GK", "DEF", "MID", "FWD"]
## Sementes vivem em [0, 2^48): cabem sem perda num double (JSON).
const SEED_LIMIT := 281474976710656
## Maior inteiro que um double representa sem perda (2^53).
const MAX_SAFE_INT := 9007199254740992.0
const UUID_PATTERN := "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
const PACKED_ARRAY_TYPES := [
	TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY,
]


# --- forma canônica e hashes ---------------------------------------------------------------

## Cópia normalizada: floats integrais viram int (recursivo), chaves de dicionário viram String,
## StringName vira String, arrays empacotados viram Array. Dicionários e arrays são copiados.
static func canonical(v: Variant) -> Variant:
	var t := typeof(v)
	if t == TYPE_FLOAT:
		var f: float = v
		if is_finite(f) and f == floorf(f) and absf(f) <= MAX_SAFE_INT:
			return int(f)
		return f
	if t == TYPE_STRING_NAME:
		return str(v)
	if t == TYPE_DICTIONARY:
		var out := {}
		var d: Dictionary = v
		for k in d:
			out[str(k)] = canonical(d[k])
		return out
	if t == TYPE_ARRAY or PACKED_ARRAY_TYPES.has(t):
		var arr: Array = []
		for x in v:
			arr.append(canonical(x))
		return arr
	return v


## JSON canônico: chaves ordenadas (sort_keys), sem espaços nem indentação.
static func canonical_json(v: Variant) -> String:
	return JSON.stringify(canonical(v), "", true, false)


## SHA-256 (hex minúsculo) do JSON canônico de v.
static func sha256(v: Variant) -> String:
	return canonical_json(v).sha256_text()


## Receita visual como entra nos hashes: sem "catalog" (mesmo rosto em outra versão do
## catálogo continua sendo o mesmo rosto).
static func hashable_face(face: Dictionary) -> Dictionary:
	var out: Dictionary = canonical(face)
	for k in FACE_IGNORED_KEYS:
		out.erase(k)
	return out


## Unicidade visual.
static func face_hash(face: Dictionary) -> String:
	return sha256(hashable_face(face))


## Unicidade do vetor exato de atributos base.
static func attributes_hash(base_attributes: Dictionary) -> String:
	return sha256(base_attributes)


## Identidade canônica: só HASHED_FIELDS (face sem "catalog").
static func dna_hash(dna: Dictionary) -> String:
	var subset := {}
	for k in HASHED_FIELDS:
		subset[k] = dna.get(k)
	var face: Variant = dna.get("face")
	if face is Dictionary:
		subset["face"] = hashable_face(face)
	return sha256(subset)


## Os três hashes calculados a partir do conteúdo (ignora hashes já gravados).
static func compute_hashes(dna: Dictionary) -> Dictionary:
	var face: Variant = dna.get("face", {})
	var attrs: Variant = dna.get("base_attributes", {})
	return {
		"face_hash": face_hash(face if face is Dictionary else {}),
		"attributes_hash": attributes_hash(attrs if attrs is Dictionary else {}),
		"dna_hash": dna_hash(dna),
	}


## Cópia canônica do DNA com os três hashes gravados. Chame uma vez, no nascimento.
static func seal(dna: Dictionary) -> Dictionary:
	var out: Dictionary = canonical(dna)
	out.merge(compute_hashes(out), true)
	return out


# --- verificação ---------------------------------------------------------------------------

## Confere um DNA selado. Devolve mensagens de erro (vazio = íntegro): campos obrigatórios
## ausentes, tipos, faixa dos 9 atributos base (inteiros 1..99), chaves da receita e hashes
## divergentes (adulteração).
static func verify(dna: Dictionary) -> Array:
	var errors: Array = []
	for k in REQUIRED_FIELDS:
		if not dna.has(k):
			errors.append("campo obrigatório ausente: %s" % k)
	_check_values_canonical(dna, "dna", errors)

	if dna.has("generator") and not _is_nonempty_string(dna["generator"]):
		errors.append("generator deve ser texto não vazio")
	if dna.has("seed"):
		var s: Variant = _as_int(dna["seed"])
		if s == null:
			errors.append("seed deve ser inteiro")
		elif int(s) < 0 or int(s) >= SEED_LIMIT:
			errors.append("seed fora de [0, 2^48): %s" % str(dna["seed"]))
	if dna.has("catalog") and not _is_nonempty_string(dna["catalog"]):
		errors.append("catalog deve ser texto não vazio")
	if dna.has("face"):
		_verify_face(dna["face"], errors)
	if dna.has("nationality") and not _is_iso_alpha2(dna["nationality"]):
		errors.append("nationality deve ser ISO alfa-2 maiúsculo: %s" % str(dna["nationality"]))
	if dna.has("position") and not POSITIONS.has(dna["position"]):
		errors.append("position inválida: %s" % str(dna["position"]))
	if dna.has("tier") and not _is_nonempty_string(dna["tier"]):
		errors.append("tier deve ser texto não vazio")
	if dna.has("initial_age"):
		var age: Variant = _as_int(dna["initial_age"])
		if age == null or int(age) < 1:
			errors.append("initial_age deve ser inteiro positivo")
	if dna.has("base_attributes"):
		_verify_attributes(dna["base_attributes"], errors)
	if dna.has("birth_name") and not _is_nonempty_string(dna["birth_name"]):
		errors.append("birth_name deve ser texto não vazio")
	if dna.has("origin"):
		if not (dna["origin"] is Dictionary):
			errors.append("origin deve ser dicionário")
		elif not _is_nonempty_string(dna["origin"].get("source")):
			errors.append("origin.source ausente")

	var expected := compute_hashes(dna)
	for k in HASH_KEYS:
		if dna.has(k) and str(dna[k]) != expected[k]:
			errors.append("%s divergente (gravado %s, calculado %s)" % [k, str(dna[k]), expected[k]])
	return errors


static func _verify_face(face: Variant, errors: Array) -> void:
	if not (face is Dictionary):
		errors.append("face deve ser dicionário")
		return
	for k in FACE_KEYS:
		if not face.has(k):
			errors.append("face sem a chave %s" % k)
		elif not (face[k] is String):
			errors.append("face.%s deve ser texto (ID do catálogo ou \"\")" % k)
	if face.get("head", "") is String and face.get("head", "") == "":
		errors.append("face.head vazio")
	for k in FACE_PALETTE_KEYS:
		if face.has(k) and _as_int(face[k]) == null:
			errors.append("face.%s deve ser índice inteiro de paleta" % k)
	for k in face:
		if not FACE_KEYS.has(k) and not FACE_PALETTE_KEYS.has(k) and not FACE_IGNORED_KEYS.has(k):
			errors.append("face com chave desconhecida: %s" % str(k))


static func _verify_attributes(attrs: Variant, errors: Array) -> void:
	if not (attrs is Dictionary):
		errors.append("base_attributes deve ser dicionário")
		return
	for k in BASE_ATTRIBUTE_IDS:
		if not attrs.has(k):
			errors.append("base_attributes sem %s" % k)
			continue
		var v: Variant = _as_int(attrs[k])
		if v == null:
			errors.append("base_attributes.%s deve ser inteiro: %s" % [k, str(attrs[k])])
		elif int(v) < ATTRIBUTE_MIN or int(v) > ATTRIBUTE_MAX:
			errors.append("base_attributes.%s fora de %d..%d: %d" % [k, ATTRIBUTE_MIN, ATTRIBUTE_MAX, int(v)])
	for k in attrs:
		if not BASE_ATTRIBUTE_IDS.has(k):
			errors.append("base_attributes com atributo desconhecido: %s" % str(k))


## O DNA canônico só tem textos, inteiros, dicionários e listas (floats integrais aceitos,
## porque é assim que o JSON devolve inteiros).
static func _check_values_canonical(v: Variant, path: String, errors: Array) -> void:
	match typeof(v):
		TYPE_STRING, TYPE_STRING_NAME, TYPE_INT:
			return
		TYPE_FLOAT:
			if _as_int(v) == null:
				errors.append("%s não é inteiro: %s" % [path, str(v)])
		TYPE_DICTIONARY:
			for k in v:
				_check_values_canonical(v[k], "%s.%s" % [path, str(k)], errors)
		TYPE_ARRAY:
			for i in v.size():
				_check_values_canonical(v[i], "%s[%d]" % [path, i], errors)
		_:
			errors.append("%s com tipo não canônico (%s)" % [path, type_string(typeof(v))])


## Inteiro (ou float integral vindo do JSON) -> int; qualquer outra coisa -> null.
static func _as_int(v: Variant) -> Variant:
	if v is int:
		return v
	if v is float:
		var c: Variant = canonical(v)
		if c is int:
			return c
	return null


static func _is_nonempty_string(v: Variant) -> bool:
	return (v is String or v is StringName) and str(v) != ""


static func _is_iso_alpha2(v: Variant) -> bool:
	if not (v is String) or len(v) != 2:
		return false
	for ch in str(v):
		if ch < "A" or ch > "Z":
			return false
	return true


# --- sementes e identificadores ------------------------------------------------------------

## Semente filha determinística, 48 bits (segura em JSON): 12 primeiros hex do SHA-256.
static func derive_seed(parent: int, salt: String) -> int:
	return ("%d:%s" % [parent, salt]).sha256_text().substr(0, 12).hex_to_int()


## UUID v4 determinístico da semente: 16 bytes do fluxo SeededRng(semente).fork("uuid").
## Se o resultado estiver em `taken` (ids já usados), continua o MESMO fluxo até achar um livre.
static func uuid_v4_from_seed(p_seed: int, taken: Dictionary = {}) -> String:
	var rng := SeededRng.new(p_seed).fork("uuid")
	var id := uuid_v4_from_rng(rng)
	while taken.has(id):
		id = uuid_v4_from_rng(rng)
	return id


## Consome 16 bytes de rng e formata como UUID v4 (versão 4, variante RFC 4122), hex minúsculo.
static func uuid_v4_from_rng(rng: SeededRng) -> String:
	var bytes: Array[int] = []
	for i in 16:
		bytes.append(rng.int_between(0, 255))
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex := ""
	for i in 16:
		if i == 4 or i == 6 or i == 8 or i == 10:
			hex += "-"
		hex += "%02x" % bytes[i]
	return hex


static func is_uuid_v4(s: String) -> bool:
	var re := RegEx.new()
	re.compile(UUID_PATTERN)
	return re.search(s) != null
