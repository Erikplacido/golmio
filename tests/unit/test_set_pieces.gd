extends TestCase


func _prep(rng_seed: int = 1) -> MatchEngine:
	var e := Fixtures.engine(Fixtures.registry_with(["set_pieces"]), rng_seed)
	Fixtures.until_live(e)
	return e


func _kick(e: MatchEngine, kicker: MatchPlayer, at: Vector2, vel: Vector2) -> void:
	var b := e.ctx.ball
	b.holder = null
	b.last_kicker = kicker
	b.pos = at
	b.vel = vel
	b.pass_cooldown = 30
	for p in e.ctx.all_players:  # afasta todo mundo da bola
		p.pos = Pitch.center()
	e.step()


func test_lateral_para_o_adversario() -> void:
	var e := _prep()
	var home_p: MatchPlayer = e.ctx.home.players[5]
	_kick(e, home_p, Vector2(300, 2), Vector2(0, -6))
	check_eq(e.ctx.restart.get("type"), "throw_in")
	check_eq(e.ctx.restart.get("team"), e.ctx.away)


func test_escanteio_quando_defensor_toca_por_ultimo() -> void:
	var e := _prep()
	var home_def: MatchPlayer = e.ctx.home.players[2]   # mandante defende x = 0 no 1º tempo
	var corners_before: int = e.ctx.away.stats.corners
	_kick(e, home_def, Vector2(3, 60), Vector2(-6, 0))
	check_eq(e.ctx.restart.get("type"), "corner")
	check_eq(e.ctx.restart.get("team"), e.ctx.away)
	check_eq(e.ctx.away.stats.corners, corners_before + 1)


func test_tiro_de_meta_quando_atacante_toca_por_ultimo() -> void:
	var e := _prep()
	var away_fwd: MatchPlayer = e.ctx.away.players[9]
	_kick(e, away_fwd, Vector2(3, 60), Vector2(-6, 0))
	check_eq(e.ctx.restart.get("type"), "goal_kick")
	check_eq(e.ctx.restart.get("team"), e.ctx.home)
	check(e.ctx.restart.get("taker").is_gk(), "goleiro cobra")


func test_sem_mecanica_bola_rebate() -> void:
	var e := Fixtures.engine(Fixtures.registry("res://rulesets/core_only.json"), 1)
	Fixtures.until_live(e)
	_kick(e, e.ctx.home.players[5], Vector2(300, 2), Vector2(0, -6))
	check(e.ctx.restart.is_empty(), "sem set_pieces não há reinício")
	check(e.ctx.ball.vel.y > 0.0, "bola voltou para dentro")
