extends TestCase
## Gols contra: o goleiro protege o gol de bolas do próprio time (recuo errado, domínio ruim) e
## times fracos não fazem gols contra em série (o recuo de um zagueiro com Passe baixo sai até
## ±0,5 rad e, sem o goleiro reagir, entrava no gol).


## Recuo de um zagueiro a 180 px do gol que sai torto: mira a 40 px do centro do gol em vez do
## goleiro (erro de ~0,27 rad; o de Passe 35 vai até ±0,39). Devolve "gol_contra", "goleiro" (o
## goleiro ficou com a bola) ou "outro".
func _misdirected_back_pass(tuning: Dictionary) -> String:
	var rs := Ruleset.load_file("res://rulesets/default.json")
	rs.core["tuning"] = tuning
	var reg := MechanicRegistry.new()
	reg.discover()
	reg.apply_ruleset(rs)
	var e := Fixtures.engine(reg, 9)
	Fixtures.until_live(e)
	var ctx := e.ctx
	var home := ctx.home
	var gk := home.goalkeeper()
	var defender: MatchPlayer = null
	for p: MatchPlayer in home.players:
		if p.role == "DEF":
			defender = p
			break
	var fwd := float(home.dir)
	var goal_x := home.own_goal_x()
	var cy := Pitch.H / 2.0
	# Todo mundo longe do lance (na metade adversária), parado.
	for p: MatchPlayer in ctx.all_players:
		p.vel = Vector2.ZERO
		p.pos = Vector2(goal_x + fwd * (620.0 + 4.0 * p.shirt), 60.0 + 40.0 * (p.shirt % 12))
	defender.pos = Vector2(goal_x + fwd * 180.0, cy)
	gk.pos = Vector2(goal_x + fwd * 30.0, cy)
	var ball := ctx.ball
	ball.holder = null
	ball.pos = defender.pos - Vector2(fwd * 10.0, 0.0)
	ball.prev_pos = ball.pos
	ball.vel = DMath.normalized(Vector2(goal_x, cy + 40.0) - ball.pos) * 9.0
	ball.last_kicker = defender
	ball.intended = gk
	ball.is_shot = false
	ball.loose = false
	ball.pass_cooldown = 7
	var start := ctx.events.size()
	var out := "outro"
	for _i in 60:
		e.step()
		var goals: Array = ctx.events.slice(start).filter(func(ev): return ev.type == "goal")
		if not goals.is_empty():
			out = "gol_contra" if bool(goals[0].data.own_goal) else "outro"
			break
		if ball.holder == gk:
			out = "goleiro"
			break
	e.dispose()
	reg.dispose()
	return out


func test_goleiro_salva_recuo_torto() -> void:
	check_eq(_misdirected_back_pass({}), "goleiro", "com o goleiro ativo (padrão), ele fica com a bola")
	check_eq(_misdirected_back_pass({"gk_receives_pass": false, "gk_covers_own_goal": false, "gk_recovers_fumble": false}), "gol_contra",
		"com o goleiro parado (motor v2), o mesmo lance é gol contra")


## Dois times de OVR ~34 (os clubes de demonstração deslocados, como no pareamento por força):
## no motor v2 eram 3,3 gols contra por 90 min (32 partidas); no v3, 1,0 — o nível dos times de 66.
func test_times_fracos_nao_fazem_gols_contra_em_serie() -> void:
	var reg := Fixtures.registry()
	var lb := LocalBackend.new()
	var home_snap := lb.fetch_opponent_snapshot({"club_file": DemoData.HOME_CLUB, "target_ovr": 34})
	var away_snap := lb.fetch_opponent_snapshot({"club_file": DemoData.AWAY_CLUB, "target_ovr": 34})
	var own_goals := 0
	var goals := 0
	var minutes := 0.0
	for i in 3:
		var s := MatchSetup.new()
		s.rng_seed = 300 + i
		s.match_minutes = 30.0
		s.home = DemoData.team_setup_from_dict(home_snap)
		s.away = DemoData.team_setup_from_dict(away_snap)
		var e := MatchEngine.create(s, reg)
		var r := e.run_to_end()
		for ev in r.events:
			if ev.type == "goal":
				goals += 1
				if bool(ev.data.own_goal):
					own_goals += 1
		minutes += s.match_minutes
		e.dispose()
	reg.dispose()
	check(own_goals * 90.0 / minutes <= 1.5,
		"gols contra demais entre times fracos: %d em %d min (%d gols)" % [own_goals, int(minutes), goals])
