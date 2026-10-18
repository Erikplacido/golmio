class_name MatchContext
extends RefCounted
## Estado de UMA partida + a API pública que as mecânicas usam durante o jogo.
## Mecânicas leem/escrevem por aqui (ctx.begin_restart, ctx.substitute, ctx.add_event...).

const TICK_SECONDS := 0.2      # 1 tick = 0,2 s de jogo  (90 min = 27.000 ticks)
const REFRESH_TICKS := 25      # a cada 5 s de jogo: MATCH_PERIODIC + recálculo de atributos/knobs

var setup: MatchSetup
var registry: MechanicRegistry
var bus: HookBus
var rng: SeededRng
var tuning: Dictionary = MatchTuning.DEFAULTS   # números de calibração do núcleo (MatchTuning)
var ball := MatchBall.new()
var home: MatchTeam
var away: MatchTeam
var all_players: Array = []
var tick: int = 0
var periods: Array = []         # [{id, seconds}]; mecânicas podem acrescentar (prorrogação)
var period_index: int = 0
## Relógio em ticks INTEIROS (sem acúmulo de float): segundos = ticks * TICK_SECONDS.
var period_ticks: int = 0
var elapsed_ticks_before_period: int = 0
## Bola parada em andamento: {type, team, pos, ticks_left, taker, must_pass, positions}. Vazio = bola rolando.
var restart: Dictionary = {}
var events: Array = []          # linha do tempo serializável
var ext: Dictionary = {}        # estado das mecânicas nesta partida
var result_extra: Dictionary = {}  # dados que mecânicas anexam ao resultado (ex.: pênaltis)
var message: String = ""
var finished: bool = false
var _pressers: Dictionary = {"home": [], "away": []}
var _rng_streams: Dictionary = {}


# ------------------------------------------------------------------ consultas
func teams() -> Array:
	return [home, away]


func other(team: MatchTeam) -> MatchTeam:
	return away if team == home else home


func team_by_side(side: String) -> MatchTeam:
	return home if side == "home" else away


func opponents_of(team: MatchTeam) -> Array:
	return other(team).players


func team_in_possession() -> MatchTeam:
	if not restart.is_empty():
		return restart.team
	if ball.holder != null:
		return ball.holder.team
	if ball.last_kicker != null:
		return ball.last_kicker.team
	return null


## Time que defende o gol localizado na linha x (0 ou Pitch.W).
func team_defending_line(line_x: float) -> MatchTeam:
	return home if is_equal_approx(home.own_goal_x(), line_x) else away


func clock_seconds() -> float:
	return float(elapsed_ticks_before_period + period_ticks) * TICK_SECONDS


## Duração de um período em ticks.
static func period_length_ticks(period: Dictionary) -> int:
	return roundi(float(period.seconds) / TICK_SECONDS)


func minute() -> float:
	return clock_seconds() / 60.0


func period_id() -> String:
	return str(periods[period_index].id) if period_index < periods.size() else "FIM"


func is_presser(p: MatchPlayer) -> bool:
	return _pressers[p.team.side].has(p)


func find_player(athlete_id: String) -> MatchPlayer:
	for p: MatchPlayer in all_players:
		if p.athlete.id == athlete_id:
			return p
	return null


## Energia/condição 0..1 do jogador (1.0 se nenhuma mecânica de cansaço estiver ligada).
func player_condition(p: MatchPlayer) -> float:
	return float(bus.pipe(Hooks.PLAYER_CONDITION, 1.0, {"ctx": self, "player": p}))


## Estado desta partida para a mecânica `mechanic_id` (criado vazio).
func state_for(mechanic_id: String) -> Dictionary:
	if not ext.has(mechanic_id):
		ext[mechanic_id] = {}
	return ext[mechanic_id]


## Parâmetros resolvidos (default_params + ruleset) da mecânica.
func params_of(mechanic_id: String) -> Dictionary:
	var m: Mechanic = registry.get_mechanic(mechanic_id) if registry else null
	return m.params if m else {}


## Fluxo aleatório próprio de uma mecânica (determinístico, independente dos demais).
func rng_for(owner: String) -> SeededRng:
	if not _rng_streams.has(owner):
		_rng_streams[owner] = rng.fork(owner)
	return _rng_streams[owner]


# ------------------------------------------------------------------ ações
func add_event(type: String, player: MatchPlayer = null, data: Dictionary = {}) -> void:
	var ev := {
		"t": DMath.round_to(minute(), 0.01),
		"tick": tick,
		"period": period_id(),
		"type": type,
		"team": player.team.side if player else str(data.get("team", "")),
		"athlete_id": player.athlete.id if player else "",
		"data": data,
	}
	events.append(ev)
	bus.emit(Hooks.MATCH_EVENT, {"ctx": self, "event": ev})


## Inicia uma bola parada. Usado pelo núcleo (saída de bola) e por mecânicas
## (lateral, tiro de meta, escanteio, falta, pênalti...).
## opts: taker (MatchPlayer), must_pass (bool, padrão true), snap (teleporta já; só kickoff).
func begin_restart(type: String, team: MatchTeam, at: Vector2, delay_ticks: int = 20, opts: Dictionary = {}) -> void:
	ball.holder = null
	ball.intended = null
	ball.cross_team = null
	ball.pos = at
	ball.prev_pos = at
	ball.vel = Vector2.ZERO
	ball.is_shot = false
	ball.shot_resolved = false
	ball.pass_cooldown = 0
	var taker: MatchPlayer = opts.get("taker", null)
	if taker == null:
		taker = _nearest_outfield(team, at, type == "kickoff")
	var r := {
		"type": type, "team": team, "pos": at, "ticks_left": delay_ticks, "taker": taker,
		"must_pass": bool(opts.get("must_pass", true)), "positions": {},
	}
	if type == "kickoff":
		for p: MatchPlayer in all_players:
			r.positions[p] = p.kickoff_position(p.team == team)
		if opts.get("snap", false):
			for p: MatchPlayer in all_players:
				p.pos = r.positions[p]
				p.vel = Vector2.ZERO
			taker.pos = at - Vector2(team.dir * (taker.radius + 2.0), 0.0)
	restart = r
	add_event("restart", taker, {"kind": type, "team": team.side})


## Substituição (API do núcleo; regras de QUANDO trocar ficam em mecânicas).
## Retorna o novo MatchPlayer ou null se inválida.
func substitute(team: MatchTeam, out_player: MatchPlayer, in_athlete: Athlete) -> MatchPlayer:
	var idx := team.players.find(out_player)
	if idx < 0 or not team.bench.has(in_athlete):
		return null
	var np := MatchPlayer.new(in_athlete, team,
		{"role": out_player.role, "x": out_player.slot.x, "y": out_player.slot.y},
		team.setup.shirt_of(in_athlete, 12 + team.subs_used))
	np.pos = out_player.pos
	np.target = out_player.pos
	team.players[idx] = np
	all_players[all_players.find(out_player)] = np
	team.bench.erase(in_athlete)
	team.subs_used += 1
	team.participants[in_athlete.id] = true
	if ball.holder == out_player:
		ball.holder = np
	if ball.last_kicker == out_player:
		ball.last_kicker = np
	if not restart.is_empty():
		if restart.taker == out_player:
			restart.taker = np
		if restart.type == "kickoff":
			restart.positions[np] = np.kickoff_position(team == restart.team)
	_refresh_player(np)
	add_event("substitution", np, {"out": out_player.athlete.id, "in": in_athlete.id})
	return np


## Quebra os ciclos jogador <-> time <-> contexto para liberar memória.
func dispose() -> void:
	for t: MatchTeam in [home, away]:
		if t:
			t.dispose()
	for p in all_players:
		if p is MatchPlayer:
			p.dispose()
	all_players.clear()
	home = null
	away = null
	ball.holder = null
	ball.last_kicker = null
	ball.intended = null
	ball.cross_team = null
	ball.block_tried = {}
	restart = {}
	_pressers = {"home": [], "away": []}
	if bus:
		bus.clear()
	bus = null
	setup = null
	registry = null
	rng = null
	_rng_streams.clear()
	events.clear()
	ext.clear()


# ------------------------------------------------------------------ uso interno do motor
func _refresh_player(p: MatchPlayer) -> void:
	p.attrs = bus.pipe(Hooks.PLAYER_ATTRIBUTES, p.athlete.attributes.duplicate(), {"ctx": self, "player": p})
	p.refresh_derived()


func _nearest_outfield(team: MatchTeam, at: Vector2, prefer_fwd: bool) -> MatchPlayer:
	var best: MatchPlayer = null
	var best_d := INF
	for p: MatchPlayer in team.players:
		if p.is_gk():
			continue
		var d := DMath.dist(p.pos, at)
		if prefer_fwd and p.role == "FWD":
			d -= 10000.0
		if d < best_d:
			best_d = d
			best = p
	return best


func _compute_pressers() -> void:
	for team: MatchTeam in [home, away]:
		var n: int = int(team.knobs.get("press_count", 1))
		var chosen: Array = []
		for _i in n:
			var best: MatchPlayer = null
			var best_d := INF
			for p: MatchPlayer in team.players:
				if p.is_gk() or chosen.has(p):
					continue
				var d := DMath.dist2(p.pos, ball.pos)
				if d < best_d:
					best_d = d
					best = p
			if best != null:
				chosen.append(best)
		_pressers[team.side] = chosen
