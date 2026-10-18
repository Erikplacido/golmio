class_name MatchEngine
extends RefCounted
## Laço da partida: passo fixo, sem dependência de tela, taxa de quadros ou relógio do sistema.
## Roda igual no jogo (MatchView), em testes headless e — no futuro — no servidor (Godot headless).
##
##   var engine := MatchEngine.create(setup, registry)
##   var result := engine.run_to_end()        # simulação instantânea
##   # ou: engine.step() a cada tick, para assistir

## Suba quando o comportamento do NÚCLEO mudar (entra na assinatura: replays sabem qual motor usar).
const ENGINE_VERSION := 3
const CELEBRATION_TICKS := 90
## Checksum da trajetória: a cada N ticks, posições quantizadas entram num hash inteiro.
## Cliente e servidor comparam result.checksum para provar que viram a MESMA partida.
const CHECKSUM_EVERY := 50
const CHECKSUM_MOD := 2147483647

var ctx: MatchContext
var result: Dictionary = {}
var _checksum: int = 17


static func create(setup: MatchSetup, registry: MechanicRegistry) -> MatchEngine:
	var e := MatchEngine.new()
	e._build(setup, registry)
	return e


## Libera a partida (quebra referências circulares). Chame ao descartar um motor.
func dispose() -> void:
	if ctx:
		ctx.dispose()
		ctx = null


func is_finished() -> bool:
	return ctx.finished


func total_regular_ticks() -> int:
	return int(round(ctx.setup.match_minutes * 60.0 / MatchContext.TICK_SECONDS))


func run_to_end(max_ticks: int = 400000) -> Dictionary:
	while not ctx.finished and ctx.tick < max_ticks:
		step()
	return result


## Avança até o próximo evento do tipo pedido (ex.: "Pular para lance crítico", GDD 3).
func run_until_event(types: Array, max_ticks: int = 100000) -> Dictionary:
	var start := ctx.events.size()
	var limit := ctx.tick + max_ticks
	while not ctx.finished and ctx.tick < limit:
		step()
		for i in range(start, ctx.events.size()):
			if types.has(ctx.events[i].type):
				return ctx.events[i]
		start = ctx.events.size()
	return {}


func step() -> void:
	if ctx.finished:
		return
	ctx.tick += 1
	ctx.period_ticks += 1
	ctx._compute_pressers()
	if ctx.tick % MatchContext.REFRESH_TICKS == 0:
		_refresh(MatchContext.REFRESH_TICKS * MatchContext.TICK_SECONDS)
	if ctx.bus.has_handlers(Hooks.MATCH_TICK):
		ctx.bus.emit(Hooks.MATCH_TICK, {"ctx": ctx})

	# Alterna quem se move primeiro a cada tick: nenhum time ganha vantagem de ordem.
	var n := ctx.all_players.size()
	if ctx.tick % 2 == 0:
		for i in n:
			ctx.all_players[i].update(ctx)
	else:
		for i in range(n - 1, -1, -1):
			ctx.all_players[i].update(ctx)

	_resolve_collisions()
	if ctx.restart.is_empty():
		_sync_ball_to_holder()
		_update_ball()
	else:
		_update_restart()

	if ctx.tick % CHECKSUM_EVERY == 0:
		_fold_positions()

	if not ctx.finished and ctx.period_ticks >= MatchContext.period_length_ticks(ctx.periods[ctx.period_index]):
		_end_period()


# ------------------------------------------------------------------ montagem
func _build(setup: MatchSetup, registry: MechanicRegistry) -> void:
	ctx = MatchContext.new()
	ctx.setup = setup
	ctx.registry = registry if registry else MechanicRegistry.new()
	ctx.rng = SeededRng.new(setup.rng_seed)
	ctx.tuning = MatchTuning.resolve(ctx.registry.ruleset)
	ctx.ball.friction = float(ctx.tuning.ball_friction)
	var home_dir := -1 if setup.home_dir < 0 else 1
	ctx.home = _make_team("home", setup.home, home_dir)
	ctx.away = _make_team("away", setup.away, -home_dir)
	ctx.all_players = ctx.home.players + ctx.away.players
	var half := setup.match_minutes * 60.0 / 2.0
	ctx.periods = [{"id": "1T", "seconds": half}, {"id": "2T", "seconds": half}]
	ctx.registry.setup_match(ctx)
	ctx.bus.emit(Hooks.MATCH_SETUP, {"ctx": ctx})
	_refresh(0.0)
	_start_period()


func _make_team(side: String, ts: TeamSetup, dir: int) -> MatchTeam:
	var t := MatchTeam.new()
	t.side = side
	t.setup = ts
	t.name = ts.name
	t.color = ts.color
	t.dir = dir
	for i in ts.lineup.size():
		var ath: Athlete = ts.lineup[i]
		var p := MatchPlayer.new(ath, t, ts.slots[i], ts.shirt_of(ath, i + 1))
		p.pos = p.home_position()
		p.target = p.pos
		t.players.append(p)
		t.participants[ath.id] = true
	t.bench = ts.bench.duplicate()
	return t


# ------------------------------------------------------------------ períodos
func _start_period() -> void:
	var p: Dictionary = ctx.periods[ctx.period_index]
	ctx.period_ticks = 0
	if ctx.period_index > 0:
		for t: MatchTeam in ctx.teams():
			t.dir = -t.dir
	var first := ctx.away if ctx.setup.kickoff_side == "away" else ctx.home
	var kicking := first if ctx.period_index % 2 == 0 else ctx.other(first)
	ctx.begin_restart("kickoff", kicking, Pitch.center(), 5, {"snap": true})
	ctx.message = "Bola rolando: %s." % str(p.id)
	ctx.bus.emit(Hooks.PERIOD_START, {"ctx": ctx, "period": p})


func _end_period() -> void:
	var p: Dictionary = ctx.periods[ctx.period_index]
	ctx.add_event("period_end", null, {"period": p.id, "home": ctx.home.stats.goals, "away": ctx.away.stats.goals})
	ctx.bus.emit(Hooks.PERIOD_END, {"ctx": ctx, "period": p})
	ctx.elapsed_ticks_before_period += ctx.period_ticks
	ctx.period_index += 1
	if ctx.period_index >= ctx.periods.size():
		var extra: Variant = ctx.bus.decide(Hooks.MATCH_END_DECISION, {"ctx": ctx})
		if extra is Array and not extra.is_empty():
			ctx.periods.append_array(extra)
		else:
			_finish()
			return
	_start_period()


## Encerra já, no placar atual (ferramenta de desenvolvimento: "Finalizar agora" da partida).
## O resultado sai pelo caminho normal (MATCH_END) e leva extra.ended_early com o minuto.
func end_now() -> void:
	if ctx.finished:
		return
	ctx.result_extra["ended_early"] = {"minute": DMath.round_to(ctx.minute(), 0.01)}
	_finish()


func _finish() -> void:
	ctx.period_index = ctx.periods.size()
	ctx.finished = true
	ctx.restart = {}
	ctx.message = "Apito final!"
	result = _build_result()
	ctx.bus.emit(Hooks.MATCH_END, {"ctx": ctx, "result": result})


func _build_result() -> Dictionary:
	var hg: int = ctx.home.stats.goals
	var ag: int = ctx.away.stats.goals
	var winner := ""
	if hg > ag:
		winner = "home"
	elif ag > hg:
		winner = "away"
	else:
		winner = str(ctx.result_extra.get("winner", ""))
	var out := {
		"seed": ctx.setup.rng_seed,
		"kind": ctx.setup.kind,
		"knockout": ctx.setup.knockout,
		"date": ctx.setup.date,
		"signature": ctx.registry.signature(),
		"ticks": ctx.tick,
		"minutes": DMath.round_to(ctx.minute(), 0.01),
		"winner": winner,
		"events": ctx.events.duplicate(true),
		"extra": ctx.result_extra.duplicate(true),
	}
	for t: MatchTeam in ctx.teams():
		out[t.side] = {
			"club_id": t.setup.club_id, "name": t.name, "goals": t.stats.goals,
			"stats": t.stats.duplicate(), "participants": t.participants.keys(),
		}
		for k in t.stats:
			_fold(int(t.stats[k]))
	_fold(ctx.events.size())
	_fold(ctx.tick)
	out["checksum"] = "%08x" % _checksum
	return out


# ------------------------------------------------------------------ checksum determinístico
func _fold(v: int) -> void:
	_checksum = posmod(_checksum * 31 + v, CHECKSUM_MOD)


func _fold_positions() -> void:
	for p: MatchPlayer in ctx.all_players:
		_fold(roundi(p.pos.x * 100.0))
		_fold(roundi(p.pos.y * 100.0))
	_fold(roundi(ctx.ball.pos.x * 100.0))
	_fold(roundi(ctx.ball.pos.y * 100.0))


# ------------------------------------------------------------------ física
func _refresh(dt: float) -> void:
	if dt > 0.0:
		ctx.bus.emit(Hooks.MATCH_PERIODIC, {"ctx": ctx, "dt": dt})
	for t: MatchTeam in ctx.teams():
		var base := Ruleset.deep_merge(MatchTeam.DEFAULT_KNOBS, ctx.tuning.knobs)
		t.knobs = ctx.bus.pipe(Hooks.TEAM_KNOBS, base, {"ctx": ctx, "team": t})
	for p: MatchPlayer in ctx.all_players:
		ctx._refresh_player(p)


func _update_restart() -> void:
	var r := ctx.restart
	r.ticks_left -= 1
	if r.ticks_left > 0:
		return
	var taker: MatchPlayer = r.taker
	if DMath.dist(taker.pos, ctx.ball.pos) > 16.0 and r.ticks_left > -60:
		return  # espera o cobrador chegar (no máximo 60 ticks)
	if r.type == "kickoff":
		for p: MatchPlayer in ctx.all_players:
			p.pos = r.positions.get(p, p.kickoff_position(p.team == r.team))
			p.vel = Vector2.ZERO
	var ball := ctx.ball
	if not taker.is_gk():
		taker.pos = ball.pos - Vector2(taker.team.dir * (taker.radius + 2.0), 0.0)
	else:
		taker.pos = ball.pos
	taker.vel = Vector2.ZERO
	ball.holder = taker
	ball.last_kicker = taker
	ball.pass_cooldown = 0
	taker.must_pass = bool(r.must_pass) and not taker.is_gk()
	taker.possession_frames = 0
	taker.decision_cooldown = 2
	taker.gk_hold_frames = 0
	ctx.restart = {}


func _sync_ball_to_holder() -> void:
	var b := ctx.ball
	var h := b.holder
	if h == null:
		return
	if h.is_gk():
		b.pos = h.pos
	else:
		b.pos = h.pos + Vector2(h.team.dir * (h.radius + 3.0), 0.0)
	b.pos.x = clampf(b.pos.x, 1.0, Pitch.W - 1.0)
	b.pos.y = clampf(b.pos.y, 1.0, Pitch.H - 1.0)
	b.vel = h.vel
	b.prev_pos = b.pos


func _update_ball() -> void:
	var b := ctx.ball
	if b.pass_cooldown > 0:
		b.pass_cooldown -= 1
	for side in b.team_shot_cooldown:
		if b.team_shot_cooldown[side] > 0:
			b.team_shot_cooldown[side] -= 1
	if b.holder != null:
		b.holder.team.stats.possession_ticks += 1
		return

	b.prev_pos = b.pos
	b.pos += b.vel
	b.vel *= b.friction
	if DMath.length(b.vel) < 0.08:
		b.vel = Vector2.ZERO
		b.is_shot = false
		b.intended = null
		b.cross_team = null
	if b.is_shot and b.last_kicker != null:
		_check_shot_block(b)

	if b.pos.x <= 0.0 or b.pos.x >= Pitch.W:
		var line_x := 0.0 if b.pos.x <= 0.0 else Pitch.W
		var t := (line_x - b.prev_pos.x) / (b.pos.x - b.prev_pos.x) if b.pos.x != b.prev_pos.x else 1.0
		var cross_y := DMath.lerp(b.prev_pos.y, b.pos.y, t)
		if cross_y >= Pitch.goal_top() and cross_y <= Pitch.goal_bottom():
			_goal(ctx.other(ctx.team_defending_line(line_x)))
			return
		_ball_out("end", Vector2(line_x, cross_y))
		return
	if b.pos.y <= 0.0 or b.pos.y >= Pitch.H:
		var line_y := 0.0 if b.pos.y <= 0.0 else Pitch.H
		var t := (line_y - b.prev_pos.y) / (b.pos.y - b.prev_pos.y) if b.pos.y != b.prev_pos.y else 1.0
		_ball_out("side", Vector2(DMath.lerp(b.prev_pos.x, b.pos.x, t), line_y))


## Defensor no caminho do chute pode bloquear (a bola desvia; se sair pela linha de fundo, escanteio).
func _check_shot_block(b: MatchBall) -> void:
	var t := ctx.tuning
	if float(t.block_chance_base) <= 0.0 and float(t.block_chance_skill) <= 0.0:
		return
	var shooter := b.last_kicker
	for o: MatchPlayer in ctx.opponents_of(shooter.team):
		if o.is_gk() or b.block_tried.has(o):
			continue
		if DMath.dist_point_segment(o.pos, b.prev_pos, b.pos) > o.radius + b.radius + float(t.block_reach):
			continue
		b.block_tried[o] = true
		var chance := float(t.block_chance_base) + o.a("tackling") / 100.0 * float(t.block_chance_skill)
		if not ctx.rng.chance(chance):
			continue
		var keep := ctx.rng.between(float(t.block_speed_keep_min), float(t.block_speed_keep_max))
		if ctx.rng.chance(float(t.block_out_share)):
			# desvio para trás da própria linha de fundo, abrindo para longe do gol
			var side := signf(o.pos.y - Pitch.H / 2.0)
			if side == 0.0:
				side = ctx.rng.pick_sign()
			var speed := DMath.length(b.vel) * keep
			b.vel = DMath.normalized(Vector2(-o.team.dir * ctx.rng.between(0.6, 1.0), side * ctx.rng.between(0.8, 1.4))) * speed
		else:
			var turn := ctx.rng.pick_sign() * ctx.rng.between(0.8, 2.2)
			b.vel = DMath.rotated(b.vel, turn) * keep
		b.is_shot = false
		b.last_kicker = o
		b.pass_cooldown = int(t.block_cooldown)
		b.intended = null
		shooter.team.stats.shots_blocked += 1
		if b.shot_on_target:
			shooter.team.stats.shots_on_target -= 1
			b.shot_on_target = false
		ctx.add_event("block", o, {"shooter": shooter.athlete.id})
		ctx.message = "Chute bloqueado por %s!" % o.display_name()
		return


func _ball_out(line: String, point: Vector2) -> void:
	var b := ctx.ball
	var last_team: MatchTeam = b.last_kicker.team if b.last_kicker else null
	var handled: Variant = ctx.bus.decide(Hooks.BALL_OUT,
		{"ctx": ctx, "line": line, "point": point, "last_team": last_team})
	if handled != null:
		return
	# Padrão sem regras de bola parada: rebate (modo arcade do protótipo).
	b.is_shot = false
	if line == "end":
		b.pos.x = 8.0 if point.x <= 0.0 else Pitch.W - 8.0
		b.vel.x = -b.vel.x * 0.55
	else:
		b.pos.y = 6.0 if point.y <= 0.0 else Pitch.H - 6.0
		b.vel.y = -b.vel.y * 0.55


func _goal(scoring: MatchTeam) -> void:
	var b := ctx.ball
	scoring.stats.goals += 1
	var scorer := b.last_kicker
	var own_goal := scorer != null and scorer.team != scoring
	ctx.add_event("goal", scorer, {"team": scoring.side, "own_goal": own_goal,
		"score": "%d-%d" % [ctx.home.stats.goals, ctx.away.stats.goals]})
	ctx.bus.emit(Hooks.GOAL_SCORED, {"ctx": ctx, "team": scoring, "scorer": scorer, "own_goal": own_goal})
	ctx.message = "GOOOOL do %s!%s" % [scoring.name, " (contra)" if own_goal else ""]
	ctx.begin_restart("kickoff", ctx.other(scoring), Pitch.center(), CELEBRATION_TICKS)


## Colisão física só perto da bola (onde importa) — barato e evita atravessar adversários.
## O mais forte (Físico) é empurrado menos: proteção de bola com o corpo (GDD 5.1).
func _resolve_collisions() -> void:
	var near: Array = []
	for p: MatchPlayer in ctx.all_players:
		if DMath.dist2(p.pos, ctx.ball.pos) < 3600.0:
			near.append(p)
	for i in near.size():
		var pa: MatchPlayer = near[i]
		for j in range(i + 1, near.size()):
			var pb: MatchPlayer = near[j]
			var d := pa.pos - pb.pos
			var min_d := pa.radius + pb.radius
			var dist2 := DMath.length2(d)
			if dist2 >= min_d * min_d or dist2 < 0.0001:
				continue
			var dist := sqrt(dist2)
			var push := d / dist * (min_d - dist) * 0.5
			var wa := 0.5
			if pa.team != pb.team:
				wa = clampf(pb.a("physical") / maxf(pa.a("physical") + pb.a("physical"), 1.0), 0.2, 0.8)
			pa.pos += push * wa * 2.0
			pb.pos -= push * (1.0 - wa) * 2.0
