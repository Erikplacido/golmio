class_name Athlete
extends RefCounted
## Atleta único (carta). Campos do núcleo são estáveis; tudo que pertence a uma mecânica
## fica em ext[id_da_mecanica] — assim mecânicas entram e saem sem migrar o modelo.

var id: String = ""
var name: String = ""
var nationality: String = ""
## Posição natural (informativa). Em campo vale o slot da escalação (GDD 5.2: liberdade posicional).
var position: String = "MID"
var status: String = "active"    # active | retired
var attributes: Dictionary = {}  # id do atributo (data/attributes.json) -> float 1..99
var dna: Dictionary = {}         # origem imutável: versão do gerador, semente, traços (GDD 5.4; ver AthleteDna)
## Trajetória de clubes (estado, fora do DNA): [{"club_id", "from", "to", "via"}], "to" = "" no clube atual.
var club_history: Array = []
var ext: Dictionary = {}         # dados das mecânicas, por id


func attr(attr_id: String, fallback: float = 50.0) -> float:
	return float(attributes.get(attr_id, fallback))


func is_goalkeeper() -> bool:
	return position == "GK"


func is_active() -> bool:
	return status == "active"


## Troca o nome de exibição. O DNA guarda o nome de nascimento (birth_name) e não muda.
func rename(new_name: String) -> void:
	name = new_name


## Identidade canônica gravada no DNA ("" em atletas sem DNA selado, ex.: demo).
func dna_hash() -> String:
	return str(dna.get("dna_hash", ""))


## Raridade de nascimento (bronze, prata, ouro, diamante, deus); "" se o DNA não tiver.
func tier() -> String:
	return str(dna.get("tier", ""))


## Dados de uma mecânica neste atleta (cria vazio se não existir).
func ext_for(mechanic_id: String) -> Dictionary:
	if not ext.has(mechanic_id):
		ext[mechanic_id] = {}
	return ext[mechanic_id]


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "nationality": nationality, "position": position,
		"status": status, "attributes": attributes.duplicate(), "dna": dna.duplicate(true),
		"club_history": club_history.duplicate(true), "ext": ext.duplicate(true),
	}


static func from_dict(d: Dictionary) -> Athlete:
	var a := Athlete.new()
	a.id = str(d.get("id", ""))
	a.name = str(d.get("name", ""))
	a.nationality = str(d.get("nationality", ""))
	a.position = str(d.get("position", "MID"))
	a.status = str(d.get("status", "active"))
	for k in d.get("attributes", {}):
		a.attributes[str(k)] = float(d["attributes"][k])
	a.dna = d.get("dna", {}).duplicate(true)
	a.club_history = d.get("club_history", []).duplicate(true)  # saves antigos: ausente = []
	a.ext = d.get("ext", {}).duplicate(true)
	return a
