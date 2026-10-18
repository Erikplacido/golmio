extends Mechanic
## Bolas paradas por saída de campo: lateral, tiro de meta e escanteio.
## Sem esta mecânica o núcleo usa o modo arcade (bola rebate nas linhas).


func _init() -> void:
	id = "set_pieces"
	title = "Lateral, tiro de meta e escanteio"
	description = "Trata BALL_OUT com as reinicializações oficiais."
	version = 1
	layer = "match"
	enabled_by_default = true
	default_params = {
		"throw_in_delay": 20,    # ticks (0,2 s cada) até a cobrança
		"goal_kick_delay": 30,
		"corner_delay": 35,
	}


func setup_match(ctx: MatchContext) -> void:
	ctx.bus.on(Hooks.BALL_OUT, _on_ball_out, id)


func _on_ball_out(payload: Dictionary) -> Variant:
	var ctx: MatchContext = payload.ctx
	var point: Vector2 = payload.point
	var last: MatchTeam = payload.last_team if payload.last_team else ctx.home

	if payload.line == "side":
		var receiving := ctx.other(last)
		var at := Vector2(clampf(point.x, 2.0, Pitch.W - 2.0), 1.0 if point.y <= 0.0 else Pitch.H - 1.0)
		ctx.begin_restart("throw_in", receiving, at, int(param("throw_in_delay")))
		ctx.message = "Lateral para %s." % receiving.name
		return true

	var defending := ctx.team_defending_line(0.0 if point.x <= 0.0 else Pitch.W)
	var line_x := defending.own_goal_x()
	var inward := float(defending.dir)   # direção do campo a partir daquela linha
	if last == defending:
		var attacking := ctx.other(defending)
		var at := Vector2(line_x + inward * 1.0, 1.0 if point.y < Pitch.H / 2.0 else Pitch.H - 1.0)
		attacking.stats.corners += 1
		ctx.begin_restart("corner", attacking, at, int(param("corner_delay")))
		ctx.message = "Escanteio para %s." % attacking.name
	else:
		var at := Vector2(line_x + inward * Pitch.GOAL_AREA_W * 0.6, Pitch.H / 2.0)
		ctx.begin_restart("goal_kick", defending, at, int(param("goal_kick_delay")), {"taker": defending.goalkeeper()})
		ctx.message = "Tiro de meta para %s." % defending.name
	return true
