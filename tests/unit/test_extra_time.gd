extends TestCase


func test_empate_em_mata_mata_vai_a_prorrogacao_e_penaltis() -> void:
	var reg := Fixtures.registry_with(["extra_time_penalties"])
	var found := false
	for s in range(1, 40):
		var e := Fixtures.engine(reg, s, 1.0, true)
		var r := e.run_to_end()
		if r.home.goals != r.away.goals:
			continue
		found = true
		check(r.events.any(func(ev): return ev.type == "extra_time"), "houve prorrogação")
		check(r.extra.has("shootout"), "houve pênaltis")
		check(r.winner in ["home", "away"])
		check(r.extra.shootout.home != r.extra.shootout.away)
		check_eq(e.ctx.periods.size(), 4, "1T, 2T, P1, P2")
		break
	check(found, "nenhum empate em 40 sementes")


func test_sem_mata_mata_empate_fica_empate() -> void:
	var reg := Fixtures.registry_with(["extra_time_penalties"])
	for s in range(1, 40):
		var r := Fixtures.engine(reg, s, 1.0, false).run_to_end()
		if r.home.goals == r.away.goals:
			check_eq(r.winner, "")
			check(not r.extra.has("shootout"))
			return
