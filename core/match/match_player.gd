class_name MatchPlayer
extends RefCounted
## Atleta em campo (estado transitório da partida). IA portada do protótipo web
## (gemini-code-*.html), agora determinística e com pontos de extensão.
## A função (GK/DEF/MID/FWD) vem do SLOT da escalação; o desempenho vem dos atributos (GDD 5.2).

const PRESSURE_RADIUS := 42.0

var athlete: Athlete
var _team_ref: WeakRef = null
var team: MatchTeam:
	get:
		return _team_ref.get_ref() as MatchTeam if _team_ref != null else null
	set(val):
		_team_ref = weakref(val) if val != null else null
var role: String = "MID"
var slot := Vector2(0.5, 0.5)
var shirt: int = 0
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var target := Vector2.ZERO
var radius := 7.2
var attrs: Dictionary = {}   # atributos EFETIVOS (após hooks), recalculados periodicamente
var max_speed := 3.0
var accel := 0.2
var possession_frames := 0
var decision_cooldown := 0
var tackle_cooldown := 0
var gk_hold_frames := 0
var must_pass := false       # cobrador de reinício: tem que passar, não conduzir
var state: String = "IDLE"
var ext: Dictionary = {}     # estado por mecânica nesta partida


func _init(p_athlete: Athlete, p_team: MatchTeam, p_slot: Dictionary, p_shirt: int) -> void:
	athlete = p_athlete
	team = p_team
	role = str(p_slot.get("role", "MID"))
	slot = Vector2(float(p_slot.get("x", 0.5)), float(p_slot.get("y", 0.5)))
	shirt = p_shirt
	radius = 8.0 if is_gk() else 7.2
	attrs = athlete.attributes.duplicate()
	refresh_derived()


func dispose() -> void:
	_team_ref = null
	athlete = null
	attrs.clear()
	ext.clear()


func is_gk() -> bool:
	return role == "GK"


func a(attr_id: String) -> float:
	return float(attrs.get(attr_id, 50.0))


func display_name() -> String:
	return athlete.name


func refresh_derived() -> void:
	var pace := a("pace") / 100.0
	max_speed = (2.7 + pace * 0.8) if is_gk() else (2.5 + pace * 1.25)
	accel = 0.16 + pace * 0.09


# ------------------------------------------------------------------ posições-base
func home_position() -> Vector2:
	var nx := slot.x if team.dir == 1 else 1.0 - slot.x
	var ny := slot.y if team.dir == 1 else 1.0 - slot.y
	return Vector2(nx * Pitch.W, ny * Pitch.H)


func kickoff_position(kicking: bool) -> Vector2:
	var p := home_position()
	var mid := Pitch.W / 2.0
	if (p.x - mid) * team.dir > -12.0:
		p.x = mid - team.dir * 12.0
	if not kicking:
		var c := Pitch.center()
		var d := DMath.dist(p, c)
		var min_r := Pitch.CENTER_CIRCLE_R + 6.0
		if d < min_r:
			var away_dir := (p - c) / d if d > 0.1 else Vector2(-team.dir, 0.0)
			p = c + away_dir * min_r
	return p


func tactical_home(ctx: MatchContext, tip: MatchTeam) -> Vector2:
	var base := home_position()
	var fwd := float(team.dir)
	var ball := ctx.ball
	var progress := (ball.pos.x / Pitch.W - 0.5) * fwd
	var ball_rel_y := (ball.pos.y - Pitch.H / 2.0) / Pitch.H
	var shift := Vector2(0.0, ball_rel_y * 32.0)
	if tip == team:
		var adv := maxf(0.0, progress + 0.5)
		shift.x = fwd * (48.0 + adv * Pitch.W * 0.18)
		match role:
			"DEF": shift.x += fwd * 38.0
			"MID":
				shift.x += fwd * 85.0
				if absf(slot.y - 0.5) > 0.25:
					shift.x += fwd * float(ctx.tuning.wide_mid_push)
			"FWD": shift.x += fwd * 165.0
	elif tip != null:
		# Pontas recompõem (4-5-1 na fase defensiva) — agora simétrico para os dois times.
		var winger := role == "FWD" and absf(slot.y - 0.5) > 0.2
		var extra := fwd * 95.0 if winger else 0.0
		shift.x = -fwd * (35.0 - progress * Pitch.W * 0.12) - extra
		shift.y *= 0.35
	else:
		shift.x = fwd * progress * Pitch.W * 0.14
	shift.x += fwd * float(team.knobs.line_height)
	var t := base + shift
	if role == "DEF":
		# Profundidade mínima da zaga (medida a partir da própria linha de fundo).
		var line := Pitch.PENALTY_BOX_W + 15.0
		if bool(ctx.tuning.def_box_drop):
			var ball_depth := ball.pos.x if fwd > 0.0 else Pitch.W - ball.pos.x
			line = clampf(ball_depth - float(ctx.tuning.def_drop_margin), float(ctx.tuning.def_min_line), line)
		if fwd > 0.0:
			t.x = clampf(t.x, line, Pitch.W * 0.65)
		else:
			t.x = clampf(t.x, Pitch.W * 0.35, Pitch.W - line)
	elif role != "GK":
		t.x = clampf(t.x, 40.0, Pitch.W - 40.0)
	t.y = clampf(t.y, 35.0, Pitch.H - 35.0)
	return t


# ------------------------------------------------------------------ ciclo
func update(ctx: MatchContext) -> void:
	if decision_cooldown > 0:
		decision_cooldown -= 1
	if tackle_cooldown > 0:
		tackle_cooldown -= 1
	var ball := ctx.ball
	var dist_to_ball := DMath.dist(pos, ball.pos)

	if not ctx.restart.is_empty():
		_update_restart(ctx)
	elif is_gk():
		_update_goalkeeper(ctx, dist_to_ball)
	elif ball.holder == self:
		_update_with_ball(ctx)
	else:
		_update_without_ball(ctx, dist_to_ball, ctx.team_in_possession())

	_apply_separation()
	_move(ctx)

	if ctx.restart.is_empty() and ball.holder == null and dist_to_ball < radius + ball.radius + 5.0:
		# Quem tocou por último não domina a própria bola, exceto o goleiro que dominou mal e vai na sobra.
		if ball.pass_cooldown <= 0 and (ball.last_kicker != self \
				or (is_gk() and ball.loose and bool(ctx.tuning.gk_recovers_fumble))):
			_control_ball(ctx)


func _move(ctx: MatchContext) -> void:
	var d := target - pos
	var dist := DMath.length(d)
	if dist > 1.2:
		var cur_max := max_speed * (0.78 if ctx.ball.holder == self else 1.0)
		vel += (d / dist * cur_max - vel) * accel
	else:
		vel *= 0.55
	pos += vel
	pos.x = clampf(pos.x, 4.0, Pitch.W - 4.0)
	pos.y = clampf(pos.y, 4.0, Pitch.H - 4.0)


func _apply_separation() -> void:
	for o: MatchPlayer in team.players:
		if o == self:
			continue
		var d := DMath.dist(pos, o.pos)
		if d > 0.0 and d < 28.0:
			target += (pos - o.pos) / d * ((28.0 - d) * 0.08)


func is_under_pressure(ctx: MatchContext, threshold: float = PRESSURE_RADIUS) -> bool:
	for o: MatchPlayer in ctx.opponents_of(team):
		if DMath.dist(o.pos, pos) < threshold:
			return true
	return false


# ------------------------------------------------------------------ bola parada
func _update_restart(ctx: MatchContext) -> void:
	state = "RESTART"
	var r := ctx.restart
	var ball := ctx.ball
	if self == r.taker:
		target = ball.pos - Vector2(team.dir * (radius + 2.0), 0.0)
		return
	if r.type == "kickoff":
		target = r.positions.get(self, home_position())
		return
	var home := tactical_home(ctx, r.team)
	target = home
	if team != r.team:
		var d := DMath.dist(home, ball.pos)
		if d < 45.0:
			var away_dir := (home - ball.pos) / d if d > 0.1 else Vector2(-team.dir, 0.0)
			target = ball.pos + away_dir * 45.0


# ------------------------------------------------------------------ goleiro
func _update_goalkeeper(ctx: MatchContext, dist_to_ball: float) -> void:
	state = "GK"
	var ball := ctx.ball
	var goal_x := team.own_goal_x()
	var cy := Pitch.H / 2.0
	var fwd := float(team.dir)

	if ball.holder == self:
		gk_hold_frames += 1
		target = Vector2(goal_x + fwd * 24.0, cy)
		if gk_hold_frames >= 18:
			_distribute(ctx)
			gk_hold_frames = 0
		return

	var to_ball := ball.pos - Vector2(goal_x, cy)
	var dist_bg := maxf(DMath.length(to_ball), 1.0)
	var adv := minf(65.0, dist_bg * 0.18)
	target = Vector2(goal_x + to_ball.x / dist_bg * adv, cy + to_ball.y / dist_bg * adv * 0.85)

	var in_box := ball.pos.x < Pitch.PENALTY_BOX_W + 10.0 if fwd > 0.0 else ball.pos.x > Pitch.W - Pitch.PENALTY_BOX_W - 10.0
	if ball.holder == null and in_box and dist_to_ball < 90.0:
		target = ball.pos
	# Recuo: o goleiro vai ao encontro do passe, como o receptor de linha. Parado na boca do gol,
	# qualquer passe que o errasse seguia para dentro (gol contra).
	if ball.holder == null and ball.intended == self and bool(ctx.tuning.gk_receives_pass):
		target = _meeting_point(ctx, dist_to_ball)
	if bool(ctx.tuning.gk_covers_own_goal):
		var cover: Variant = _own_goal_cover_point(ctx)
		if cover != null:
			target = cover

	var shot_against := ball.is_shot and DMath.length(ball.vel) > 2.0 and ball.last_kicker != null and ball.last_kicker.team != team
	if shot_against:
		target = ball.pos
		if dist_to_ball < 45.0 and ball.holder == null and not ball.shot_resolved:
			ball.shot_resolved = true
			if ball.shot_on_target:
				_try_save(ctx)


## Bola solta de um companheiro (recuo torto, domínio ruim, desvio) que vai entrar no próprio gol:
## devolve o ponto da trajetória mais perto do goleiro, para ele se pôr na frente; null = sem perigo.
func _own_goal_cover_point(ctx: MatchContext) -> Variant:
	var ball := ctx.ball
	var lk := ball.last_kicker
	if ball.holder != null or lk == null or lk == self or lk.team != team:
		return null
	var v := ball.vel
	var goal_x := team.own_goal_x()
	if v.x * float(team.dir) >= -0.05:
		return null   # não vai na direção do próprio gol
	var cross := Vector2(goal_x, ball.pos.y + v.y * (goal_x - ball.pos.x) / v.x)
	if absf(cross.y - Pitch.H / 2.0) > Pitch.GOAL_H / 2.0 + ball.radius:
		return null   # passa ao lado da trave
	var path := DMath.dist(ball.pos, cross)
	if DMath.length(v) / (1.0 - ball.friction) < path:
		return null   # para antes da linha (com atrito, a bola anda no máximo v / (1 - atrito))
	var seg := cross - ball.pos
	var t := clampf(((pos.x - ball.pos.x) * seg.x + (pos.y - ball.pos.y) * seg.y) / maxf(path * path, 0.0001), 0.0, 1.0)
	return ball.pos + seg * t


func _try_save(ctx: MatchContext) -> void:
	var ball := ctx.ball
	var shooter: MatchPlayer = ball.last_kicker
	var goal := Vector2(team.own_goal_x(), Pitch.H / 2.0)
	var shot_dist := DMath.dist(goal, ball.shot_origin)
	var t := ctx.tuning
	var base := float(t.save_far) if shot_dist > 140.0 else (float(t.save_mid) if shot_dist > 90.0 else float(t.save_close))
	var quality := (a("positioning") * 0.4 + a("reflexes") * 0.35 + a("elasticity") * 0.25) / 100.0
	var q: Dictionary = ctx.bus.pipe(Hooks.SAVE_ATTEMPT,
		{"chance": base * (float(t.save_quality_base) + quality * float(t.save_quality_weight)),
			"hold_chance": float(t.hold_base) + a("reflexes") / 100.0 * float(t.hold_skill)},
		{"ctx": ctx, "keeper": self, "shooter": shooter})
	if not ctx.rng.chance(float(q.chance)):
		return
	team.stats.saves += 1
	ball.is_shot = false
	ctx.add_event("save", self, {"shooter": shooter.athlete.id if shooter else ""})
	if ctx.rng.chance(float(q.hold_chance)):
		ball.holder = self
		ball.last_kicker = self
		ball.vel = Vector2.ZERO
		gk_hold_frames = 0
		ctx.message = "Defesa segura de %s!" % display_name()
		return
	var side := signf(pos.y - Pitch.H / 2.0)
	if side == 0.0:
		side = ctx.rng.pick_sign()
	if ctx.rng.chance(float(t.parry_out_share)):
		ball.vel = Vector2(-team.dir * ctx.rng.between(1.5, 2.5), side * ctx.rng.between(6.0, 9.0))
		ctx.message = "%s espalma para fora!" % display_name()
	else:
		ball.vel = Vector2(team.dir * ctx.rng.between(3.0, 6.0), side * ctx.rng.between(5.0, 9.0))
		ctx.message = "%s espalma e a bola sobra na área!" % display_name()
	ball.last_kicker = self
	ball.pass_cooldown = 18


func _distribute(ctx: MatchContext) -> void:
	var ball := ctx.ball
	ball.holder = null
	ball.is_shot = false
	ball.last_kicker = self
	ball.pass_cooldown = 14
	var open: MatchPlayer = null
	for p: MatchPlayer in team.players:
		if p == self or not (p.role == "DEF" or p.role == "MID"):
			continue
		var d := DMath.dist(p.pos, pos)
		if d > 60.0 and d < 250.0:
			open = p
			break
	if open != null and ctx.rng.chance(0.88):
		_pass_to(ctx, open, 7.5, false)
		ctx.message = "Saída de bola com %s." % open.display_name()
	else:
		ball.vel = Vector2(team.dir * ctx.rng.between(9.0, 12.0), (ctx.rng.next_float() - 0.5) * 5.0)
		team.stats.passes_attempted += 1
		ctx.message = "%s repõe a bola para frente." % display_name()


# ------------------------------------------------------------------ com a bola
func _update_with_ball(ctx: MatchContext) -> void:
	state = "DRIBBLE"
	possession_frames += 1
	var fwd := float(team.dir)
	var ball := ctx.ball
	ball.is_shot = false
	var goal := Vector2(team.opp_goal_x(), Pitch.H / 2.0)
	var dist_goal := DMath.dist(pos, goal)
	var knobs := team.knobs

	var t := ctx.tuning
	var wide := absf(pos.y - Pitch.H / 2.0) > float(t.cross_min_width)
	if not must_pass and decision_cooldown == 0 and wide and float(t.cross_prob) > 0.0:
		var to_byline := Pitch.W - pos.x if fwd > 0.0 else pos.x
		if to_byline < float(t.cross_zone) and ctx.rng.chance(float(t.cross_prob)):
			_cross(ctx)
			return
	var attacker := role == "FWD" or a("finishing") >= 80.0
	var shot_range := float(t.shot_range_attacker if attacker else t.shot_range_other) * float(knobs.shot_range_mult)
	if not must_pass and dist_goal < shot_range and decision_cooldown == 0 and ball.team_shot_cooldown[team.side] <= 0:
		var prob := float(t.shot_prob_close if dist_goal < float(t.shot_close_dist) else t.shot_prob_far) \
			* float(t.shot_attacker_mult if attacker else t.shot_other_mult) * float(knobs.shot_prob_mult)
		var angle_power := float(t.shot_angle_power)
		if angle_power > 0.0:
			var cos_angle := absf(goal.x - pos.x) / maxf(dist_goal, 1.0)
			prob *= pow_int_free(cos_angle, angle_power)
		if ctx.rng.chance(prob):
			_shoot(ctx, goal)
			return

	var pressured := is_under_pressure(ctx)
	var ready := decision_cooldown == 0 and (possession_frames >= int(knobs.tempo_frames) or pressured or must_pass)
	if ready:
		var opt := _best_pass(ctx, pressured)
		if not opt.is_empty():
			_pass_to(ctx, opt.player, opt.speed, opt.through)
			return

	if (possession_frames > 10 or must_pass) and decision_cooldown == 0:
		var em := _emergency_pass(ctx)
		if not em.is_empty():
			_pass_to(ctx, em.player, em.speed, false)
			return
		if must_pass and possession_frames > 30:
			must_pass = false

	var final_third := dist_goal < 220.0
	target.x = pos.x + fwd * (24.0 if final_third else 16.0)
	if wide and bool(t.wide_keep_width):
		target.y = pos.y  # segue pela ponta rumo à linha de fundo
	else:
		target.y = goal.y * (0.35 if final_third else 0.15) + pos.y * (0.65 if final_third else 0.85)
	for o: MatchPlayer in ctx.opponents_of(team):
		if DMath.dist(o.pos, pos) < 32.0:
			target.y += 20.0 if pos.y > o.pos.y else -20.0
			target.x += fwd * 2.0


func _best_pass(ctx: MatchContext, pressured: bool) -> Dictionary:
	var fwd := float(team.dir)
	var goal := Vector2(team.opp_goal_x(), Pitch.H / 2.0)
	var passing := a("passing")
	var max_dist := 200.0 + passing / 100.0 * 180.0
	var t := ctx.tuning
	var min_allowed := maxf(float(t.pass_clearance_floor), float(t.pass_clearance_base) - passing / 100.0 * float(t.pass_clearance_skill))
	var recv_free := float(t.pass_receiver_free)
	var risk := float(team.knobs.pass_risk)
	var opps := ctx.opponents_of(team)
	var best: Dictionary = {}
	var best_score := -999.0
	for tm: MatchPlayer in team.players:
		if tm == self or tm.is_gk():
			continue
		var d := DMath.dist(pos, tm.pos)
		if d < 35.0 or d > max_dist:
			continue
		var min_clear := 999.0
		var opp_to_recv := 999.0
		for o: MatchPlayer in opps:
			min_clear = minf(min_clear, Pitch.dist_point_segment(o.pos, pos, tm.pos))
			opp_to_recv = minf(opp_to_recv, DMath.dist(o.pos, tm.pos))
		if min_clear <= min_allowed or opp_to_recv <= recv_free:
			continue
		var progress := (tm.pos.x - pos.x) * fwd
		var score := 25.0 + passing / 100.0 * 8.0
		if progress > 0.0:
			score += minf(40.0, progress * 0.55) * (1.0 + risk)
			if tm.role == "FWD":
				score += 15.0
			elif tm.role == "MID":
				score += 10.0
		else:
			score += progress * 0.10
			if pressured or possession_frames > 6:
				score += 28.0
		var lateral := absf(tm.pos.y - pos.y)
		if lateral > 40.0 and lateral < 260.0:
			score += 16.0
		score += minf(24.0, min_clear * 0.8)
		score += minf(20.0, opp_to_recv * 0.4)
		if d > 220.0:
			score -= (d - 220.0) * 0.20
		if d < 40.0:
			score -= 12.0
		score += (Pitch.W - DMath.dist(goal, tm.pos)) * 0.06
		if score > best_score:
			best_score = score
			var through := tm.role == "FWD" and progress > 35.0 and min_clear > 16.0 and opp_to_recv > 20.0
			var spd := clampf(d * 0.045 + 3.8 + passing / 100.0 * 1.8, 6.6, 9.8)
			best = {"player": tm, "speed": spd, "through": through}
	return best


func _emergency_pass(ctx: MatchContext) -> Dictionary:
	var fwd := float(team.dir)
	var best: Dictionary = {}
	var best_score := -INF
	for tm: MatchPlayer in team.players:
		if tm == self:
			continue
		var d := DMath.dist(pos, tm.pos)
		if d < 35.0 or d > 380.0:
			continue
		var nearest := 999.0
		for o: MatchPlayer in ctx.opponents_of(team):
			nearest = minf(nearest, DMath.dist(o.pos, tm.pos))
		if nearest <= 14.0:
			continue
		var sc := nearest + (tm.pos.x - pos.x) * fwd * 0.3
		if sc > best_score:
			best_score = sc
			best = {"player": tm, "speed": clampf(d * 0.045 + 4.5, 6.5, 9.5), "through": false}
	return best


func _pass_to(ctx: MatchContext, tm: MatchPlayer, speed: float, through: bool) -> void:
	var ball := ctx.ball
	ball.holder = null
	ball.is_shot = false
	ball.loose = false
	ball.last_kicker = self
	ball.pass_cooldown = 7
	possession_frames = 0
	decision_cooldown = 16
	must_pass = false
	tm.decision_cooldown = 2
	ball.intended = tm
	ctx.bus.emit(Hooks.PASS_RELEASED, {"ctx": ctx, "passer": self, "receiver": tm, "through": through})
	var t := ctx.tuning
	var travel := DMath.dist(pos, tm.pos)
	var lead := float(t.through_lead if through else t.pass_lead)
	var aim := tm.pos + tm.vel * (travel / (speed * 1.4)) * lead
	var spread := (100.0 - a("passing")) * float(t.pass_spread) * (ctx.rng.next_float() - 0.5)
	ball.vel = DMath.rotated(DMath.normalized(aim - ball.pos), spread) * speed
	team.stats.passes_attempted += 1
	ctx.message = "%s de %s para %s." % ["Passe em profundidade" if through else "Passe", display_name(), tm.display_name()]


func _shoot(ctx: MatchContext, goal: Vector2) -> void:
	var ball := ctx.ball
	ball.holder = null
	ball.is_shot = true
	ball.shot_resolved = false
	ball.last_kicker = self
	ball.pass_cooldown = 25
	ball.shot_origin = pos
	ball.intended = null
	ball.block_tried = {}
	var t := ctx.tuning
	possession_frames = 0
	decision_cooldown = int(t.shooter_cooldown)
	ball.team_shot_cooldown[team.side] = int(t.team_shot_cooldown)
	team.stats.shots += 1
	var fin := a("finishing") / 100.0
	var dist_goal := DMath.dist(pos, goal)
	var spread := (float(t.shot_spread_base) - fin * float(t.shot_spread_skill)) * (1.0 + dist_goal * float(t.shot_spread_per_px))
	var aim_off := (ctx.rng.next_float() - 0.5) * spread
	var on_target := absf(aim_off) <= Pitch.GOAL_H / 2.0 - 2.0
	ball.shot_on_target = on_target
	if on_target:
		team.stats.shots_on_target += 1
	var power := float(t.shot_power_base) + fin * float(t.shot_power_skill) + ctx.rng.next_float() * float(t.shot_power_random)
	ball.vel = DMath.normalized(Vector2(goal.x, goal.y + aim_off) - ball.pos) * power
	ctx.add_event("shot", self, {"on_target": on_target, "distance": DMath.round_to(dist_goal, 0.1)})
	ctx.message = "Finalização %s de %s!" % ["no alvo" if on_target else "para fora", display_name()]


# ------------------------------------------------------------------ sem a bola
func _update_without_ball(ctx: MatchContext, dist_to_ball: float, tip: MatchTeam) -> void:
	var fwd := float(team.dir)
	var ball := ctx.ball
	var home := tactical_home(ctx, tip)

	if tip != team or ball.holder == null:
		if ctx.is_presser(self) and dist_to_ball < float(team.knobs.press_radius):
			state = "PRESS"
			target = ball.pos
		else:
			state = "COVER"
			target = home
		if ball.holder != null and ball.holder.team != team and tackle_cooldown == 0 \
				and dist_to_ball < radius + ball.radius + 4.0:
			_attempt_tackle(ctx, ball.holder)
	elif role == "FWD":
		state = "PENETRATE"
		target = home + Vector2(fwd * 35.0, DMath.dsin(ctx.tick * 0.05 + shirt) * 16.0)
	elif dist_to_ball < 340.0:
		state = "SUPPORT"
		var upper := shirt % 2 == 0
		var lateral := -55.0 if upper else 55.0
		var t: Vector2
		match role:
			"MID": t = Vector2(ball.pos.x + fwd * (30.0 + (shirt % 3) * 15.0), ball.pos.y + lateral)
			"DEF": t = Vector2(ball.pos.x - fwd * 45.0, ball.pos.y + (-35.0 if upper else 35.0))
			_: t = Vector2(ball.pos.x + fwd * 25.0, ball.pos.y + lateral)
		for o: MatchPlayer in ctx.opponents_of(team):
			if Pitch.dist_point_segment(o.pos, ball.pos, t) < 24.0:
				t.y += 26.0 if t.y >= o.pos.y else -26.0
				t.x += fwd * 8.0
		target = t
	else:
		state = "SHAPE"
		target = home

	if ball.holder == null and dist_to_ball < 50.0:
		target = ball.pos
	if ball.holder == null and ball.intended == self and bool(ctx.tuning.receiver_runs_to_ball):
		state = "RECEIVE"
		target = _meeting_point(ctx, dist_to_ball)


## Ponto de encontro com a bola passada para este jogador (onde ele a alcança no caminho dela).
func _meeting_point(ctx: MatchContext, dist_to_ball: float) -> Vector2:
	var ball := ctx.ball
	var bspeed := DMath.length(ball.vel)
	var look := minf(float(ctx.tuning.receiver_max_lookahead), dist_to_ball / maxf(bspeed + max_speed, 0.1))
	return ball.pos + ball.vel * look


func _cross(ctx: MatchContext) -> void:
	var t := ctx.tuning
	var ball := ctx.ball
	var fwd := float(team.dir)
	var aim := Vector2(team.opp_goal_x() - fwd * ctx.rng.between(40.0, 110.0), Pitch.H / 2.0 + ctx.rng.between(-70.0, 70.0))
	var target_mate: MatchPlayer = null
	var best := INF
	for tm: MatchPlayer in team.players:
		if tm == self or tm.is_gk():
			continue
		var d := DMath.dist2(tm.pos, aim)
		if d < best:
			best = d
			target_mate = tm
	ball.holder = null
	ball.is_shot = false
	ball.loose = false
	ball.last_kicker = self
	ball.cross_team = team
	ball.intended = target_mate
	ctx.bus.emit(Hooks.PASS_RELEASED, {"ctx": ctx, "passer": self, "receiver": target_mate, "through": false})
	ball.pass_cooldown = int(t.cross_cooldown)
	var spread := (100.0 - a("passing")) * float(t.pass_spread) * (ctx.rng.next_float() - 0.5)
	ball.vel = DMath.rotated(DMath.normalized(aim - ball.pos), spread) * ctx.rng.between(float(t.cross_speed_min), float(t.cross_speed_max))
	possession_frames = 0
	decision_cooldown = 16
	team.stats.passes_attempted += 1
	team.stats["crosses"] = int(team.stats.get("crosses", 0)) + 1
	ctx.message = "Cruzamento de %s!" % display_name()


## Zagueiro corta o cruzamento de cabeça: para escanteio ou para longe.
func _clear_cross(ctx: MatchContext) -> void:
	var t := ctx.tuning
	var ball := ctx.ball
	ball.last_kicker = self
	ball.intended = null
	ball.loose = true
	ball.pass_cooldown = 10
	var speed := ctx.rng.between(5.0, 9.0)
	if ctx.rng.chance(float(t.cross_clear_out)):
		var side := signf(pos.y - Pitch.H / 2.0)
		if side == 0.0:
			side = ctx.rng.pick_sign()
		ball.vel = DMath.normalized(Vector2(-team.dir * ctx.rng.between(0.6, 1.0), side * ctx.rng.between(0.8, 1.4))) * speed
		ctx.message = "%s corta de cabeça para escanteio!" % display_name()
	else:
		ball.vel = DMath.normalized(Vector2(team.dir * ctx.rng.between(0.5, 1.0), ctx.rng.between(-0.8, 0.8))) * speed
		ctx.message = "%s afasta o cruzamento!" % display_name()
	if ctx.rng.chance(float(t.interception_stat_chance)):
		team.stats.tackles += 1


## Domínio errado: a bola espirra solta (quem recuperar fica com ela; não conta como passe certo).
func _miscontrols(ctx: MatchContext) -> bool:
	var t := ctx.tuning
	var ball := ctx.ball
	var p := float(t.miscontrol_base) + float(t.miscontrol_speed) * DMath.length(ball.vel) / 10.0 \
		- a("passing") / 100.0 * float(t.miscontrol_skill)
	if is_under_pressure(ctx):
		p += float(t.miscontrol_pressure)
	if p <= 0.0 or not ctx.rng.chance(p):
		return false
	var dir := DMath.rotated(Vector2(team.dir, 0.0), ctx.rng.between(-2.4, 2.4))
	ball.vel = dir * ctx.rng.between(2.0, 4.0)
	ball.last_kicker = self
	ball.pass_cooldown = 5
	ball.intended = null
	ball.loose = true
	return true


func _attempt_tackle(ctx: MatchContext, holder: MatchPlayer) -> void:
	var t := ctx.tuning
	tackle_cooldown = int(t.tackle_cooldown)
	var base := a("tackling") / 100.0 * float(t.tackle_rate)
	var strength := 1.0 + (50.0 - holder.a("physical")) / 100.0 * 0.4 + (a("physical") - 50.0) / 100.0 * 0.2
	var chance := base * float(t.tackle_mult_settled if holder.possession_frames > 6 else t.tackle_mult_fresh) * strength
	var r: Dictionary = ctx.bus.pipe(Hooks.TACKLE_ATTEMPT, {"chance": chance, "handled": false},
		{"ctx": ctx, "tackler": self, "holder": holder})
	if r.get("handled", false):
		return
	if not ctx.rng.chance(float(r.chance)):
		holder.possession_frames += 2
		return
	team.stats.tackles += 1
	var ball := ctx.ball
	holder.must_pass = false
	if absf(pos.x - team.own_goal_x()) < 60.0 and ctx.rng.chance(0.28):
		ball.holder = null
		ball.last_kicker = self
		ball.pass_cooldown = 18
		var side := signf(pos.y - Pitch.H / 2.0)
		if side == 0.0:
			side = ctx.rng.pick_sign()
		if absf(pos.y - Pitch.H / 2.0) > Pitch.GOAL_H / 2.0 + 25.0:
			ball.vel = Vector2(-team.dir * 3.0, side * 4.0)   # afasta pela linha de fundo
		else:
			ball.vel = Vector2(team.dir * 2.0, side * 8.0)    # afasta para a lateral
		ctx.message = "Corte de %s!" % display_name()
		return
	ball.holder = self
	ball.last_kicker = self
	ball.is_shot = false
	possession_frames = 0
	decision_cooldown = 2
	ctx.message = "Desarme de %s!" % display_name()


func _control_ball(ctx: MatchContext) -> void:
	var ball := ctx.ball
	var lk := ball.last_kicker
	var was_shot := ball.is_shot
	var was_loose := ball.loose
	var cross_team := ball.cross_team
	ball.cross_team = null
	if cross_team != null and not is_gk():
		if cross_team != team:
			_clear_cross(ctx)
			return
		if ctx.rng.chance(float(ctx.tuning.cross_first_time_shot)):
			team.stats.passes_completed += 1
			ball.holder = self
			ball.intended = null
			_shoot(ctx, Vector2(team.opp_goal_x(), Pitch.H / 2.0))
			return
	if lk != null and lk.team == team and lk != self and not was_shot and not was_loose and _miscontrols(ctx):
		return
	ball.holder = self
	ball.intended = null
	ball.vel = Vector2.ZERO
	ball.pass_cooldown = 0
	ball.is_shot = false
	possession_frames = 0
	decision_cooldown = 2
	ball.loose = false
	if lk != null and lk.team == team and lk != self and not was_shot and not was_loose:
		team.stats.passes_completed += 1
	elif lk != null and lk.team != team and ctx.rng.chance(float(ctx.tuning.interception_stat_chance)):
		team.stats.tackles += 1
		ctx.message = "Interceptação de %s!" % display_name()
	ball.last_kicker = self


## x^p para p >= 0 sem pow() da libm (determinístico): parte inteira por multiplicação,
## fração por interpolação linear entre x^n e x^(n+1).
static func pow_int_free(x: float, p: float) -> float:
	var n := int(floor(p))
	var r := 1.0
	for _i in n:
		r *= x
	var frac := p - float(n)
	return r if frac == 0.0 else DMath.lerp(r, r * x, frac)
