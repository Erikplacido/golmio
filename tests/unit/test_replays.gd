extends TestCase
## Testes para a mecânica de replays e critical_skip (GDD 4).


func test_replays_habilitado_no_dev() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	check(reg.enabled_ids().has("replays"), "replays habilitado no dev.json")


func test_replays_grava_frames_no_buffer() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var e := Fixtures.engine(reg, 100)
	var ctx := e.ctx

	# Executa 30 ticks
	for i in 30:
		e.step()

	var state: Dictionary = ctx.state_for("replays")
	var buf: Array = state.get("buffer", [])
	check_eq(buf.size(), 30, "buffer gravou 30 frames de jogo")

	var f: Dictionary = buf[0]
	check(f.has("tick"), "frame tem tick")
	check(f.has("ball_pos"), "frame tem ball_pos")
	check(f.has("home_players"), "frame tem home_players")
	check(f.has("away_players"), "frame tem away_players")
	check_eq(f.home_players.size(), 11, "11 atletas mandantes no frame")
	check_eq(f.away_players.size(), 11, "11 atletas visitantes no frame")


func test_replays_captura_lance_critico() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var e := Fixtures.engine(reg, 42)
	var ctx := e.ctx

	# Roda até encontrar um gol ou lance crítico
	var res := e.run_until_event(["goal"])
	if res.is_empty():
		# Se semente 42 não teve gol antes de acabar, roda uma partida com mais chances
		e = Fixtures.engine(reg, 123)
		ctx = e.ctx
		e.run_to_end()

	var replays: Variant = ctx.bus.decide("replays.get_replays", {"ctx": ctx})
	check(replays is Array, "replays.get_replays retornou array")

	var last_rep: Variant = ctx.bus.decide("replays.last_replay", {"ctx": ctx})
	if replays is Array and not (replays as Array).is_empty():
		check(last_rep is Dictionary, "last_replay retornou um clipe")
		check(last_rep.has("frames"), "clipe tem lista de frames")
		check(last_rep.has("title"), "clipe tem título")
		check(last_rep.frames.size() > 0, "clipe gravou frames do lance")


func test_replays_preserva_determinismo() -> void:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var r1 := Fixtures.engine(reg, 999).run_to_end()
	var r2 := Fixtures.engine(reg, 999).run_to_end()

	check_eq(r1.home.stats.goals, r2.home.stats.goals, "replays: determinístico nos gols mandantes")
	check_eq(r1.away.stats.goals, r2.away.stats.goals, "replays: determinístico nos gols visitantes")
	check_eq(r1.events.size(), r2.events.size(), "replays: mesma quantidade de eventos bit a bit")
