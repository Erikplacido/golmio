class_name Ruleset
extends RefCounted
## Conjunto de regras ativo: quais mecânicas estão ligadas e com quais parâmetros.
## Vem de JSON (res://rulesets/*.json localmente; no futuro, do servidor como "remote config").
##
## Formato:
## {
##   "id": "default", "version": "2026.09.0", "extends": "base.json" (opcional),
##   "core":      { "match_minutes": 90, "squad_limit": 30 },
##   "mechanics": { "stamina": { "enabled": true, "params": { "drain_per_minute": 0.007 } } },
##   "unlisted_mechanics": "default"   (opcional: "default" | "off" | "on")
## }
## Mecânica sem entrada usa enabled_by_default e default_params dela mesma
## (ou "off"/"on" para todas as não listadas, conforme unlisted_mechanics).

const CORE_DEFAULTS := {
	"match_minutes": 90.0,
	"squad_limit": 30,
	"lineup_size": 11,
	"bench_size": 5,
}

var id: String = "empty"
var version: String = "0"
var description: String = ""
var core: Dictionary = {}
var mechanics: Dictionary = {}
var unlisted_mechanics: String = "default"
var source_path: String = ""


static func from_dict(data: Dictionary) -> Ruleset:
	var rs := Ruleset.new()
	rs.id = str(data.get("id", "unnamed"))
	rs.version = str(data.get("version", "0"))
	rs.description = str(data.get("description", ""))
	rs.core = deep_merge(CORE_DEFAULTS, data.get("core", {}))
	rs.mechanics = data.get("mechanics", {}).duplicate(true)
	rs.unlisted_mechanics = str(data.get("unlisted_mechanics", "default"))
	return rs


static func load_file(path: String, _depth: int = 0) -> Ruleset:
	var data := _read_json(path, _depth)
	var rs := from_dict(data)
	rs.source_path = path
	return rs


static func _read_json(path: String, depth: int) -> Dictionary:
	if depth > 8:
		push_error("Ruleset: cadeia de 'extends' longa demais em %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("Ruleset inválido ou ausente: %s" % path)
		return {}
	var data: Dictionary = parsed
	if data.has("extends"):
		var base := _read_json(path.get_base_dir().path_join(str(data["extends"])), depth + 1)
		data.erase("extends")
		data = deep_merge(base, data)
	return data


static func deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if out.has(k) and out[k] is Dictionary and over[k] is Dictionary:
			out[k] = deep_merge(out[k], over[k])
		else:
			out[k] = over[k].duplicate(true) if (over[k] is Dictionary or over[k] is Array) else over[k]
	return out


func has_entry(mechanic_id: String) -> bool:
	return mechanics.has(mechanic_id)


func is_enabled(mechanic_id: String, default_enabled: bool) -> bool:
	match unlisted_mechanics:
		"off": default_enabled = false
		"on": default_enabled = true
	return bool(mechanics.get(mechanic_id, {}).get("enabled", default_enabled))


func params_for(mechanic_id: String, defaults: Dictionary) -> Dictionary:
	return deep_merge(defaults, mechanics.get(mechanic_id, {}).get("params", {}))


func core_param(key: String) -> Variant:
	return core.get(key, CORE_DEFAULTS.get(key))


func to_dict() -> Dictionary:
	return {"id": id, "version": version, "description": description, "core": core,
		"mechanics": mechanics, "unlisted_mechanics": unlisted_mechanics}
