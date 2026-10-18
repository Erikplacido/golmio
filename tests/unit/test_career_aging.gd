extends TestCase


func _setup() -> Array:
	var reg := Fixtures.registry_with(["career_aging"])
	var w := World.new()
	var a := Athlete.new()
	a.id = "x1"
	a.attributes = {"pace": 50.0, "finishing": 98.0, "stamina": 2.0}
	w.add_athlete(a)
	return [reg, w, a]


func _play(reg: MechanicRegistry, w: World, days: int, start: int = 0) -> void:
	for d in range(start, start + days):
		var result := {"kind": "official", "home": {"participants": ["x1"]}, "away": {"participants": []}}
		MatchReporter.report(reg, w, result, "dia-%d" % d)


func test_curva_completa_do_gdd() -> void:
	var s := _setup()
	var reg: MechanicRegistry = s[0]
	var w: World = s[1]
	var a: Athlete = s[2]
	_play(reg, w, 250)
	check_near(MatchReporter.athlete_age(reg, a), 27.0, 0.001, "250 participações = 27 anos")
	check_near(a.attr("pace"), 60.0, 0.001, "+10 no crescimento")
	check_near(a.attr("finishing"), 99.0, 0.001, "teto 99")
	_play(reg, w, 250, 250)
	check_near(a.attr("pace"), 60.0, 0.001, "platô até os 37")
	_play(reg, w, 199, 500)
	check(a.is_active(), "ainda ativo com 699 participações")
	_play(reg, w, 1, 699)
	check_near(a.attr("pace"), 48.0, 0.001, "8 quedas de 1,5")
	check_near(a.attr("stamina"), 1.0, 0.001, "piso 1")
	check_eq(a.status, "retired", "aposenta aos 45 (700 participações)")
	_play(reg, w, 5, 700)
	check_eq(int(a.ext.career_aging.days), 700, "aposentado não soma dias")


func test_um_dia_por_data_e_amistoso_nao_conta() -> void:
	var s := _setup()
	var reg: MechanicRegistry = s[0]
	var w: World = s[1]
	var a: Athlete = s[2]
	var official := {"kind": "official", "home": {"participants": ["x1"]}, "away": {"participants": ["x1"]}}
	MatchReporter.report(reg, w, official, "2026-10-01")
	MatchReporter.report(reg, w, official, "2026-10-01")
	check_eq(int(a.ext.career_aging.days), 1, "mesma data conta uma vez")
	MatchReporter.report(reg, w, {"kind": "friendly", "home": {"participants": ["x1"]}}, "2026-10-02")
	check_eq(int(a.ext.career_aging.days), 1, "amistoso não envelhece")


func test_sem_mecanica_ninguem_envelhece() -> void:
	var reg := Fixtures.registry("res://rulesets/core_only.json")
	var w := World.new()
	var a := Athlete.new()
	a.id = "x1"
	w.add_athlete(a)
	MatchReporter.report(reg, w, {"kind": "official", "home": {"participants": ["x1"]}}, "d")
	check(not a.ext.has("career_aging"))
	check_near(MatchReporter.athlete_age(reg, a), 17.0)
