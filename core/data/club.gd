class_name Club
extends RefCounted
## Clube do usuário. Reputação, finanças, torcida etc. são mecânicas e guardam dados em ext.

var id: String = ""
var name: String = ""
var short_name: String = ""
var colors: Dictionary = {"primary": "#dc2626", "secondary": "#ffffff"}
var athlete_ids: Array = []   # elenco ativo (limite em ruleset.core.squad_limit)
var ext: Dictionary = {}


func ext_for(mechanic_id: String) -> Dictionary:
	if not ext.has(mechanic_id):
		ext[mechanic_id] = {}
	return ext[mechanic_id]


func primary_color() -> Color:
	return Color.from_string(str(colors.get("primary", "#ffffff")), Color.WHITE)


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "short_name": short_name, "colors": colors.duplicate(),
		"athlete_ids": athlete_ids.duplicate(), "ext": ext.duplicate(true),
	}


static func from_dict(d: Dictionary) -> Club:
	var c := Club.new()
	c.id = str(d.get("id", ""))
	c.name = str(d.get("name", ""))
	c.short_name = str(d.get("short_name", ""))
	c.colors = d.get("colors", c.colors).duplicate()
	c.athlete_ids = d.get("athlete_ids", []).duplicate()
	c.ext = d.get("ext", {}).duplicate(true)
	return c
