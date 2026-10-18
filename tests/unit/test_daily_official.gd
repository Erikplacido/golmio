extends TestCase
## daily_official: um oficial por clube em cada data do servidor; amistoso não gasta a vaga.


func _setup() -> Array:
	var reg := Fixtures.registry_with(["daily_official"])
	var world := World.new()
	var club := Club.new()
	club.id = "c1"
	world.add_club(club)
	return [reg, world, club]


func _status(reg: MechanicRegistry, club: Club, date: String) -> Dictionary:
	return reg.bus.decide("daily_official.status", {"club": club, "date": date})


func _result(kind: String) -> Dictionary:
	return {"kind": kind, "home": {"club_id": "c1", "participants": []}, "away": {"club_id": "outro", "participants": []}}


func test_desligada_no_default_e_ligada_no_dev() -> void:
	check(not Fixtures.registry().is_enabled("daily_official"), "experimental: fora do default")
	check(Fixtures.registry("res://rulesets/dev.json").is_enabled("daily_official"), "ligada no dev")


func test_um_oficial_por_dia() -> void:
	var s := _setup()
	var reg: MechanicRegistry = s[0]
	var world: World = s[1]
	var club: Club = s[2]
	check(bool(_status(reg, club, "2026-10-10").available), "dia novo: oficial disponível")
	MatchReporter.report(reg, world, _result("friendly"), "2026-10-10")
	check(bool(_status(reg, club, "2026-10-10").available), "amistoso não gasta o oficial")
	MatchReporter.report(reg, world, _result("official"), "2026-10-10")
	var st := _status(reg, club, "2026-10-10")
	check(not bool(st.available), "oficial jogado: indisponível no mesmo dia")
	check_eq(int(st.played), 1, "1 oficial contado")
	check_eq(str(st.last_date), "2026-10-10", "data do último oficial")
	check(bool(_status(reg, club, "2026-10-11").available), "no dia seguinte libera de novo")
	reg.dispose()


func test_per_day_vem_do_ruleset() -> void:
	var reg := Fixtures.registry_with(["daily_official"], {"daily_official": {"per_day": 2}})
	var world := World.new()
	var club := Club.new()
	club.id = "c1"
	world.add_club(club)
	MatchReporter.report(reg, world, _result("official"), "2026-10-10")
	check(bool(_status(reg, club, "2026-10-10").available), "per_day=2: ainda tem um")
	MatchReporter.report(reg, world, _result("official"), "2026-10-10")
	check(not bool(_status(reg, club, "2026-10-10").available), "per_day=2: esgotou")
	reg.dispose()


func test_sem_clube_ou_data_nao_libera() -> void:
	var s := _setup()
	var reg: MechanicRegistry = s[0]
	check(not bool(_status(reg, null, "2026-10-10").available), "sem clube")
	check(not bool(_status(reg, s[2], "").available), "sem data")
	reg.dispose()
