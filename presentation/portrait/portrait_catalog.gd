class_name PortraitCatalog
extends RefCounted
## Catálogo de retratos no cliente (docs/RETRATOS.md 4.2): lê jogo/data/portraits/catalog.json e as
## cópias fiéis de head_anchors.json, part_anchors.json e body_anchors.json, geradas por
## visuais/exportar_catalogo.py. Resolve ID -> arquivo original, dimensões ORIGINAIS, textura
## exportada, encaixe (pivot + escala nativa), soquetes da cabeça, calibração de torso e braço e golas.
##
## Os JSON de âncoras usam o NOME DO ARQUIVO original (NFC) como chave; o catálogo liga cada ID
## (head_007, ear_003...) a esse nome em parts[slot][id].file. Toda a matemática usa (w, h)
## originais; a textura exportada pode ser menor e é esticada para Rect2(0, 0, w, h).
##
## Torsos e braços trazem os mapas do uniforme já calculados pelo exportador (parts[slot][id].maps,
## lidos por UniformMaps.for_part) e os torsos, a detecção de gola, escudo e ombros
## (parts.body[id].detected): o cliente não analisa pixels para desenhar. fingerprint() identifica
## o conteúdo inteiro (catálogo + âncoras) para o cache do PortraitBaker.
##
## O servidor (athlete_generator) lê só o catalog.json; esta classe é do cliente (abre imagens).

const DEFAULT_DIR := "res://data/portraits"
const CATALOG_FILE := "catalog.json"
const HEAD_ANCHORS_FILE := "head_anchors.json"
const PART_ANCHORS_FILE := "part_anchors.json"
const BODY_ANCHORS_FILE := "body_anchors.json"
## Encaixe padrão por slot quando o catálogo não traz default_pivots (= ENCAIXE_PADRAO de montagem.js).
const FALLBACK_PIVOTS := {
	"ear": [0.85, 0.5], "body": [0.5, 0.12], "hair": [0.5, 0.35], "arm": [0.5, 0.06],
	"chin": [0.5, 0.5], "skin_mark": [0.5, 0.5],
}
## Valor de kit.collar que desliga a gola (Montagem.GOLAS["nenhuma"]).
const NO_COLLAR := "nenhuma"

static var _shared: PortraitCatalog = null

## catalog.json inteiro.
var data: Dictionary = {}
## head_anchors.json -> heads: {arquivo da cabeça: {soquete: {...}}}.
var heads: Dictionary = {}
## part_anchors.json inteiro ({version, rules, parts: {slot: {arquivo: {pivot, native_scale}}}}).
var part_anchors: Dictionary = {}
## body_anchors.json inteiro ({version, bodies: {arquivo: {...}}, arms: {arquivo: {...}}}).
var body_anchors: Dictionary = {}
var version: String = ""
var content_hash: String = ""
## Pasta de onde veio (vazia se montado em memória).
var source_dir: String = ""

var _textures: Dictionary = {}      # "slot/id" -> Texture2D (ou null, se falhou)
var _detected: Dictionary = {}      # body_id -> detecção automática (catálogo ou UniformMaps.detect_body)
var _fingerprint: String = ""


## Catálogo padrão do jogo, carregado uma vez (res://data/portraits/).
static func shared() -> PortraitCatalog:
	if _shared == null:
		_shared = load_from(DEFAULT_DIR.path_join(CATALOG_FILE))
	return _shared


## Esquece o catálogo compartilhado (ex.: depois de baixar um catálogo novo).
static func reset_shared() -> void:
	_shared = null


## Carrega um catalog.json; os três arquivos de âncoras são lidos da mesma pasta.
static func load_from(path: String) -> PortraitCatalog:
	var dir := path.get_base_dir()
	var cat := from_data(
		_read_json(path), _read_json(dir.path_join(HEAD_ANCHORS_FILE)),
		_read_json(dir.path_join(PART_ANCHORS_FILE)), _read_json(dir.path_join(BODY_ANCHORS_FILE)))
	cat.source_dir = dir
	if cat.data.is_empty():
		push_warning("PortraitCatalog: catálogo vazio ou ilegível em %s" % path)
	return cat


## Monta um catálogo a partir de dicionários já carregados (útil em testes).
static func from_data(catalog: Dictionary, head_anchors: Dictionary, p_part_anchors: Dictionary,
		p_body_anchors: Dictionary) -> PortraitCatalog:
	var cat := PortraitCatalog.new()
	cat.data = catalog
	cat.heads = head_anchors.get("heads", head_anchors)
	cat.part_anchors = p_part_anchors
	cat.body_anchors = p_body_anchors
	cat.version = str(catalog.get("version", ""))
	cat.content_hash = str(catalog.get("content_hash", ""))
	return cat


## Impressão digital de TUDO o que o desenho lê dos JSON: o catalog.json inteiro (IDs, dimensões,
## tex_hash dos pixels de cada textura, mapas do uniforme, detecção dos torsos, anchors) e as três
## âncoras (soquetes, encaixes, calibração de torso e braço). SHA-256 do JSON canônico,
## calculado uma vez por catálogo. Recalibrar um soquete, trocar um encaixe ou redesenhar um PNG
## (e rodar o exportador) muda a impressão digital; é o que invalida o cache do PortraitBaker.
func fingerprint() -> String:
	if _fingerprint == "":
		_fingerprint = AthleteDna.sha256({
			"catalog": data, "heads": heads, "part_anchors": part_anchors, "body_anchors": body_anchors,
		})
	return _fingerprint


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("PortraitCatalog: arquivo ausente %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


# --- peças ------------------------------------------------------------------------------------

## Entrada do catálogo para a peça ({} se o slot ou o ID não existem).
func part(slot: String, id: String) -> Dictionary:
	if id == "":
		return {}
	var parts: Dictionary = data.get("parts", {})
	var of_slot: Dictionary = parts.get(slot, {})
	return of_slot.get(id, {})


func has_part(slot: String, id: String) -> bool:
	return not part(slot, id).is_empty()


## IDs de um slot em ordem alfabética (todos os status).
func ids(slot: String) -> Array:
	var parts: Dictionary = data.get("parts", {})
	var out: Array = parts.get(slot, {}).keys()
	out.sort()
	return out


## IDs de um slot com o status pedido ("active", "retired", "missing"), em ordem alfabética.
func ids_with_status(slot: String, status: String) -> Array:
	return ids(slot).filter(func(id): return str(part(slot, id).get("status", "")) == status)


## Nome do arquivo original (NFC), chave dos JSON de âncoras.
func file_of(slot: String, id: String) -> String:
	return str(part(slot, id).get("file", ""))


## Dimensões ORIGINAIS da peça em pixels (as de toda a matemática de montagem).
func size_of(slot: String, id: String) -> Vector2:
	var p := part(slot, id)
	return Vector2(float(p.get("w", 0)), float(p.get("h", 0)))


## Mapas do uniforme pré-calculados pelo exportador ({texture, w, h, median, bbox, hash}), só em
## torsos e braços; {} se a peça não tem.
func maps_info(slot: String, id: String) -> Dictionary:
	var info: Variant = part(slot, id).get("maps")
	return info if info is Dictionary else {}


## Encaixe da peça: fração (fx, fy) da imagem que toca o soquete (part_anchors, senão
## default_pivots do catálogo, senão centro). Igual a Montagem.encaixe().
func pivot(slot: String, id: String) -> Vector2:
	var xy := pivot_xy(slot, id)
	return Vector2(xy[0], xy[1])


## pivot() em float de 64 bits: [fx, fy] (Vector2 é de 32 bits; a montagem precisa de precisão).
func pivot_xy(slot: String, id: String) -> Array:
	var calib := _part_calibration(slot, id)
	if calib.has("pivot") and calib["pivot"] is Array and calib["pivot"].size() >= 2:
		return [float(calib["pivot"][0]), float(calib["pivot"][1])]
	var defaults: Dictionary = data.get("default_pivots", FALLBACK_PIVOTS)
	var pad: Variant = defaults.get(slot, FALLBACK_PIVOTS.get(slot, [0.5, 0.5]))
	return [float(pad[0]), float(pad[1])]


## Escala nativa da peça (part_anchors); 1 se não calibrada ou zero (como `native_scale || 1`).
func native_scale(slot: String, id: String) -> float:
	var ns := float(_part_calibration(slot, id).get("native_scale", 0.0))
	return ns if ns != 0.0 else 1.0


## A peça tem encaixe próprio em part_anchors.json?
func is_part_calibrated(slot: String, id: String) -> bool:
	return not _part_calibration(slot, id).is_empty()


func _part_calibration(slot: String, id: String) -> Dictionary:
	var file := file_of(slot, id)
	if file == "":
		return {}
	var parts: Dictionary = part_anchors.get("parts", {})
	var of_slot: Dictionary = parts.get(slot, {})
	var entry: Variant = of_slot.get(file, {})
	return entry if entry is Dictionary else {}


# --- cabeça, torso e braço ----------------------------------------------------------------------

## Soquetes da cabeça (head_anchors.json pelo arquivo): {ear_left: {x, y, scale, rotation,
## flipX, behind, scales}, ...}. {} se a cabeça não existe ou não foi calibrada.
func head_anchor(head_id: String) -> Dictionary:
	var file := file_of("head", head_id)
	if file == "":
		return {}
	var entry: Variant = heads.get(file, {})
	return entry if entry is Dictionary else {}


## Calibração salva do torso em body_anchors.json ({} se não calibrado).
func body_anchor(body_id: String) -> Dictionary:
	var bodies: Dictionary = body_anchors.get("bodies", {})
	var entry: Variant = bodies.get(file_of("body", body_id), {})
	return entry if entry is Dictionary else {}


## Calibração salva do braço em body_anchors.json ({} se não calibrado).
func arm_anchor(arm_id: String) -> Dictionary:
	var arms: Dictionary = body_anchors.get("arms", {})
	var entry: Variant = arms.get(file_of("arm", arm_id), {})
	return entry if entry is Dictionary else {}


## Calibração completa do torso, como Montagem.calibracaoCorpo(): a salva sobrepõe, campo a
## campo, a detecção automática. A detecção (que abre a imagem) só roda se faltar algum campo.
## {collar: {left, right, depth}, crest: {center, size}, shoulders: {left, right}, calibrated}.
func body_calibration(body_id: String) -> Dictionary:
	var saved := body_anchor(body_id)
	var auto := {}
	if not UniformMaps.calibration_complete(saved):
		auto = detected_body(body_id)
	return UniformMaps.merge_body_calibration(auto, saved)


## Detecção automática de gola, escudo e ombros do torso (cache por ID). Vem pronta do catálogo
## (parts.body[id].detected, calculada pelo exportador como o detectarCorpo do montagem.js); só
## sem ela a silhueta é analisada aqui.
func detected_body(body_id: String) -> Dictionary:
	if _detected.has(body_id):
		return _detected[body_id]
	var result := {}
	var saved: Variant = part("body", body_id).get("detected")
	if saved is Dictionary and saved.get("collar") is Dictionary and saved.get("crest") is Dictionary \
			and saved.get("shoulders") is Dictionary:
		result = (saved as Dictionary).duplicate(true)
	else:
		var maps := UniformMaps.for_part(self, "body", body_id)
		if maps != null:
			result = maps.detect_body()
		else:
			result = UniformMaps.detect_body_fallback()
	_detected[body_id] = result
	return result


## Calibração do braço, como Montagem.calibracaoBraco(): {sleeve: {a, b}, calibrated}.
func arm_calibration(arm_id: String) -> Dictionary:
	return UniformMaps.merge_arm_calibration(arm_anchor(arm_id))


# --- golas ------------------------------------------------------------------------------------

## Resolve kit.collar para um ID do catálogo: aceita ID ("collar_002"), nome de arquivo de
## visuais/gola/ (NFC ou NFD), rótulo ("Gola V") ou trecho do nome (como Montagem.obterGola).
## "" para "nenhuma", vazio ou desconhecido.
func collar_id(name_or_id: String) -> String:
	var key := name_or_id.strip_edges()
	if key == "" or key == NO_COLLAR:
		return ""
	if has_part("collar", key):
		return key
	var folded := _fold(key)
	var all := ids("collar")
	for id in all:
		var p := part("collar", id)
		if _fold(str(p.get("file", ""))) == folded or _fold(str(p.get("label", ""))) == folded:
			return id
	for id in all:
		var f := _fold(str(part("collar", id).get("file", "")))
		if f != "" and (f.contains(folded) or folded.contains(f)):
			return id
	return ""


## Calibração individual da gola (lida de part_anchors.parts.collar ou do catálogo):
## {width_factor, top_factor, offset: [dx, dy], scale}. Retorna {} se não calibrada (usa padrão).
func collar_calibration(name_or_id: String) -> Dictionary:
	var cid := collar_id(name_or_id)
	if cid == "":
		return {}
	var entry := _part_calibration("collar", cid)
	if not entry.is_empty():
		return entry
	var parts: Dictionary = part_anchors.get("parts", {})
	var by_slot: Dictionary = parts.get("collar", {})
	if by_slot.has(cid) and by_slot[cid] is Dictionary:
		return by_slot[cid]
	var p := part("collar", cid)
	if p.has("calibration") and p["calibration"] is Dictionary:
		return p["calibration"]
	if p.has("width_factor") or p.has("top_factor") or p.has("offset") or p.has("scale"):
		return p
	return {}


## Forma de comparação tolerante: minúsculas, sem acentos (NFC ou NFD) e sem espaços nas pontas.
static func _fold(s: String) -> String:
	const FROM := "àáâãäåçèéêëìíîïñòóôõöùúûüýÿ"
	const TO := "aaaaaaceeeeiiiinooooouuuuyy"
	var out := ""
	for ch in s.to_lower().strip_edges():
		var code := ch.unicode_at(0)
		if code >= 0x0300 and code <= 0x036F:
			continue  # marca combinante (NFD)
		var i := FROM.find(ch)
		out += TO[i] if i >= 0 else ch
	return out


# --- texturas -----------------------------------------------------------------------------------

## Textura exportada da peça (cache). null se a peça não existe ou a textura falta.
func texture(slot: String, id: String) -> Texture2D:
	var key := "%s/%s" % [slot, id]
	if _textures.has(key):
		return _textures[key]
	var tex: Texture2D = null
	var path := str(part(slot, id).get("texture", ""))
	if path != "" and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and id != "":
		push_warning("PortraitCatalog: sem textura para %s/%s" % [slot, id])
	_textures[key] = tex
	return tex
