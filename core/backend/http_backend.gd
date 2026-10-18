class_name HttpBackend
extends Backend
## Backend HTTP: fala com o servidor local (ou remoto) via API REST.
## URL configurável por `user://backend_config.json` (criado automaticamente na primeira vez).
## Trocar do servidor local para o online: só mudar "url" no arquivo de configuração.
##
## Usa HTTPRequest do Godot com corrotinas (await) — compatível com a interface Backend.
## Requer que o nó HttpBackend esteja na árvore de cena (é um Node, não RefCounted).
## Use SceneTree.root.add_child(HttpBackend.new()) no boot ou crie via autoload.

extends Node

## URL padrão do servidor local. Substituída pelo backend_config.json se existir.
const DEFAULT_URL      := "http://localhost:3000"
const CONFIG_PATH      := "user://backend_config.json"
const REQUEST_TIMEOUT  := 10.0   # segundos

var base_url: String = DEFAULT_URL
var _pending: bool   = false


func _init() -> void:
	# Carregar configuração se existir
	if FileAccess.file_exists(CONFIG_PATH):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if raw is Dictionary and raw.has("url"):
			base_url = str(raw["url"])
	else:
		# Criar config padrão
		_save_config({"mode": "local_http", "url": DEFAULT_URL})


func _save_config(cfg: Dictionary) -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(cfg, "\t"))


# ------------------------------------------------------------------
# Implementações dos métodos da interface Backend
# ------------------------------------------------------------------

func fetch_ruleset() -> Dictionary:
	var resp := await _get("/ruleset")
	return resp if resp is Dictionary else {}


func load_world() -> Dictionary:
	var resp := await _get("/world")
	return resp if resp is Dictionary else {}


func save_world(data: Dictionary) -> bool:
	var resp := await _post("/world", data)
	return resp is Dictionary and bool(resp.get("ok", false))


func fetch_opponent_snapshot(_criteria: Dictionary) -> Dictionary:
	var resp := await _get("/opponent")
	return resp if resp is Dictionary else {}


func submit_match_result(result: Dictionary) -> Dictionary:
	var resp := await _post("/match_result", result)
	return resp if resp is Dictionary else {}


func new_seed() -> int:
	var resp := await _get("/seed")
	if resp is Dictionary and resp.has("seed"):
		return int(resp["seed"])
	# Fallback seguro: gerador criptográfico local (mesmo que LocalBackend)
	push_warning("HttpBackend.new_seed: servidor indisponível, usando fallback local")
	var bytes := Crypto.new().generate_random_bytes(6)
	var v := 0
	for b in bytes:
		v = (v << 8) | b
	return v


# ------------------------------------------------------------------
# Helpers HTTP
# ------------------------------------------------------------------

func _get(path: String) -> Variant:
	return await _request(path, HTTPClient.METHOD_GET, {})


func _post(path: String, body: Dictionary) -> Variant:
	return await _request(path, HTTPClient.METHOD_POST, body)


func _request(endpoint: String, method: int, body: Dictionary) -> Variant:
	var url := base_url + endpoint
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = REQUEST_TIMEOUT

	var headers := ["Content-Type: application/json", "Accept: application/json"]
	var body_str := "" if body.is_empty() else JSON.stringify(body)

	var err: int
	if body.is_empty():
		err = http.request(url, headers, method)
	else:
		err = http.request(url, headers, method, body_str)

	if err != OK:
		push_error("HttpBackend: erro ao iniciar requisição para %s: %s" % [url, error_string(err)])
		http.queue_free()
		return {}

	var result: Array = await http.request_completed
	http.queue_free()

	# result = [result_code, response_code, headers, body]
	var response_code: int = result[1]
	var body_bytes: PackedByteArray = result[3]

	if response_code < 200 or response_code >= 300:
		push_error("HttpBackend: %s retornou HTTP %d" % [url, response_code])
		return {}

	var parsed: Variant = JSON.parse_string(body_bytes.get_string_from_utf8())
	if parsed == null:
		push_error("HttpBackend: resposta de %s não é JSON válido" % url)
		return {}

	return parsed
