class_name SaveMigrator
extends RefCounted
## Atualiza saves antigos. Duas trilhas independentes:
##   1. Esquema do núcleo (CURRENT_SCHEMA + _migrate_core).
##   2. Dados de cada mecânica em ext (Mechanic.data_version + Mechanic.migrate_data).
## Dados de mecânicas que não existem mais NÃO são apagados: ficam dormentes e voltam
## a valer se a mecânica for reativada.

const CURRENT_SCHEMA := 1


static func migrate(data: Dictionary, registry: MechanicRegistry) -> Dictionary:
	var v := int(data.get("schema_version", 0))
	while v < CURRENT_SCHEMA:
		data = _migrate_core(v, data)
		v += 1
	data["schema_version"] = CURRENT_SCHEMA

	var versions: Dictionary = data.get("mechanic_data_versions", {})
	for mid in registry.available:
		var m: Mechanic = registry.available[mid]
		var from := int(versions.get(mid, m.data_version))
		while from < m.data_version:
			_migrate_owner_ext(data, "athletes", "athlete", m, from)
			_migrate_owner_ext(data, "clubs", "club", m, from)
			var wext: Dictionary = data.get("ext", {})
			if wext.has(mid):
				wext[mid] = m.migrate_data("world", from, wext[mid])
			from += 1
		versions[mid] = m.data_version
	data["mechanic_data_versions"] = versions
	return data


static func _migrate_owner_ext(data: Dictionary, key: String, kind: String, m: Mechanic, from: int) -> void:
	for oid in data.get(key, {}):
		var ext: Dictionary = data[key][oid].get("ext", {})
		if ext.has(m.id):
			ext[m.id] = m.migrate_data(kind, from, ext[m.id])


static func _migrate_core(from_version: int, data: Dictionary) -> Dictionary:
	match from_version:
		0:
			# Saves sem versão (pré-lançamento): nada a converter ainda.
			pass
	return data
