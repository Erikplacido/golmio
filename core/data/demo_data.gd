class_name DemoData
extends RefCounted
## Carrega os clubes de demonstração (data/demo/*.json). Nomes fictícios.
## Serve para o visualizador, testes e balanceamento enquanto não há criação de clube/pacotes.

const HOME_CLUB := "res://data/demo/club_rubro.json"
const AWAY_CLUB := "res://data/demo/club_anil.json"
const FORMATIONS_DIR := "res://data/formations"


static func read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func formation(formation_id: String) -> Array:
	var d: Variant = read_json(FORMATIONS_DIR.path_join(formation_id + ".json"))
	return d.slots if d is Dictionary else []


static func team_setup(path: String) -> TeamSetup:
	return team_setup_from_dict(read_json(path))


## TeamSetup a partir dos dados de um clube no formato de data/demo/*.json (o mesmo do snapshot
## defensivo que Backend.fetch_opponent_snapshot devolve).
static func team_setup_from_dict(d: Dictionary) -> TeamSetup:
	var ts := TeamSetup.new()
	var club: Dictionary = d.club
	ts.club_id = str(club.id)
	ts.name = str(club.name)
	ts.short_name = str(club.short_name)
	ts.color = Color.from_string(str(club.colors.primary), Color.WHITE)
	ts.slots = formation(str(d.formation))
	ts.tactics = d.get("tactics", {}).duplicate(true)
	var by_id := {}
	for ad in d.athletes:
		var ath := Athlete.from_dict(ad)
		by_id[ath.id] = ath
		ts.shirts[ath.id] = int(ad.get("shirt", 0))
	for aid in d.lineup:
		ts.lineup.append(by_id[aid])
	for aid in d.bench:
		ts.bench.append(by_id[aid])
	return ts


static func match_setup(rng_seed: int, minutes: float = 90.0, kind: String = "friendly") -> MatchSetup:
	var s := MatchSetup.new()
	s.rng_seed = rng_seed
	s.match_minutes = minutes
	s.kind = kind
	s.date = "2026-09-27"
	s.home = team_setup(HOME_CLUB)
	s.away = team_setup(AWAY_CLUB)
	return s


## Mundo com os dois clubes de demonstração.
static func world() -> World:
	var w := World.new()
	w.date = "2026-09-27"
	for path in [HOME_CLUB, AWAY_CLUB]:
		var d: Dictionary = read_json(path)
		var c := Club.from_dict(d.club)
		for ad in d.athletes:
			var ath := Athlete.from_dict(ad)
			w.add_athlete(ath)
			c.athlete_ids.append(ath.id)
		w.add_club(c)
	return w
