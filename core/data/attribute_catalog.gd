class_name AttributeCatalog
extends RefCounted
## Lista oficial de atributos (data/attributes.json). Atributo novo = nova linha no JSON;
## o motor lê atributos por id e usa 50 quando um atleta ainda não tem o valor.

const PATH := "res://data/attributes.json"

static var _cache: Dictionary = {}


static func data() -> Dictionary:
	if _cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cache = parsed if parsed is Dictionary else {"attributes": []}
	return _cache


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for a in data().attributes:
		out.append(str(a.id))
	return out


static func label(attr_id: String) -> String:
	for a in data().attributes:
		if a.id == attr_id:
			return str(a.label)
	return attr_id


static func min_value() -> float:
	return float(data().get("min", 1))


static func max_value() -> float:
	return float(data().get("max", 99))
