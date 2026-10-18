class_name World
extends RefCounted
## Raiz do estado persistente (o "save"). No modelo online, o servidor é a fonte da verdade
## e o cliente guarda uma cópia; o formato é o mesmo.

var schema_version: int = SaveMigrator.CURRENT_SCHEMA
var date: String = ""                     # data do jogo (servidor, UTC, AAAA-MM-DD)
var clubs: Dictionary = {}                # id -> Club
var athletes: Dictionary = {}             # id -> Athlete (inclui aposentados: álbum histórico)
var ext: Dictionary = {}                  # dados globais das mecânicas
var mechanic_data_versions: Dictionary = {}  # id -> data_version usada ao salvar


func add_athlete(a: Athlete) -> void:
	athletes[a.id] = a


func add_club(c: Club) -> void:
	clubs[c.id] = c


func to_dict() -> Dictionary:
	var ath := {}
	for k in athletes:
		ath[k] = athletes[k].to_dict()
	var cl := {}
	for k in clubs:
		cl[k] = clubs[k].to_dict()
	return {
		"schema_version": schema_version, "date": date, "clubs": cl, "athletes": ath,
		"ext": ext.duplicate(true), "mechanic_data_versions": mechanic_data_versions.duplicate(),
	}


static func from_dict(d: Dictionary) -> World:
	var w := World.new()
	w.schema_version = int(d.get("schema_version", SaveMigrator.CURRENT_SCHEMA))
	w.date = str(d.get("date", ""))
	for k in d.get("clubs", {}):
		w.clubs[str(k)] = Club.from_dict(d["clubs"][k])
	for k in d.get("athletes", {}):
		w.athletes[str(k)] = Athlete.from_dict(d["athletes"][k])
	w.ext = d.get("ext", {}).duplicate(true)
	w.mechanic_data_versions = d.get("mechanic_data_versions", {}).duplicate()
	return w
